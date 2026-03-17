#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 01_create_monitor.sh - Create V3 Monitoring Infrastructure via Terraform
# =============================================================================
# Creates: EC2 + SG + EIP + S3 Bucket (monitoring data) + IAM Role
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

# --- 1. Source .env ---
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: $SCRIPT_DIR/.env not found. Copy env.example to .env and fill in values."
  exit 1
fi
source "$SCRIPT_DIR/.env"

echo "============================================="
echo " V3 Monitoring Server - Infrastructure Setup"
echo "============================================="
echo "Profile : $AWS_PROFILE"
echo "Region  : $AWS_REGION"
echo "Prefix  : $NAME_PREFIX"
echo "S3      : $S3_MONITORING_BUCKET"
echo ""

# --- 2. Generate tfvars ---
TFVARS_FILE="${TF_DIR}/terraform.tfvars"

cat > "$TFVARS_FILE" <<EOF
region               = "${AWS_REGION}"
aws_profile          = "${AWS_PROFILE}"
name_prefix          = "${NAME_PREFIX}"
vpc_id               = "${VPC_ID}"
vpc_cidr             = "${VPC_CIDR}"
subnet_id            = "${SUBNET_ID}"
ami_id               = "${AMI_ID}"
instance_type        = "${INSTANCE_TYPE}"
volume_size          = ${VOLUME_SIZE:-50}
admin_ip             = "${ADMIN_IP}"
gcp_nat_ip           = "${GCP_NAT_IP:-}"
s3_monitoring_bucket = "${S3_MONITORING_BUCKET}"
extra_admin_ips      = [$(echo "${EXTRA_ADMIN_IPS:-}" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/^""$//')]
k8s_nat_ips          = [$(echo "${K8S_NAT_IPS:-}" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/^""$//')]
EOF

echo "[1/4] Generated terraform.tfvars"

# --- 3. Terraform init ---
echo "[2/4] Running terraform init ..."
cd "$TF_DIR"
terraform init -input=false

# --- 4. Terraform plan ---
echo "[3/4] Running terraform plan ..."
terraform plan -input=false -out=tfplan

echo ""
echo "Review the plan above."
read -rp "Apply? [y/N] " answer
case "$answer" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# --- 5. Terraform apply ---
echo "[4/4] Running terraform apply ..."
terraform apply -input=false tfplan
rm -f tfplan

# --- 6. Extract outputs ---
INSTANCE_ID=$(terraform output -raw instance_id)
PUBLIC_IP=$(terraform output -raw monitor_eip)
PRIVATE_IP=$(terraform output -raw private_ip)
S3_BUCKET=$(terraform output -raw s3_bucket_name)

# --- 7. Update .env ---
cd "$SCRIPT_DIR"
ENV_FILE="$SCRIPT_DIR/.env"

update_env_var() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

update_env_var "MONITOR_INSTANCE_ID" "$INSTANCE_ID"
update_env_var "MONITOR_PUBLIC_IP" "$PUBLIC_IP"
update_env_var "MONITOR_PRIVATE_IP" "$PRIVATE_IP"

echo ""
echo "============================================="
echo " V3 Monitoring Server - Setup Complete"
echo "============================================="
echo " Instance ID : $INSTANCE_ID"
echo " Public IP   : $PUBLIC_IP (EIP)"
echo " Private IP  : $PRIVATE_IP"
echo " S3 Bucket   : $S3_BUCKET"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Wait ~2 min for SSM agent to register"
echo "  2. Run 02_install_stack.sh"

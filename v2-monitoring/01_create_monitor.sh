#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 01_create_monitor.sh - Create V2 Monitoring Server Infrastructure on AWS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Source .env
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: $SCRIPT_DIR/.env not found. Copy env.example to .env and fill in values."
  exit 1
fi

# shellcheck source=/dev/null
source "$SCRIPT_DIR/.env"

# Validate required variables
REQUIRED_VARS=(
  AWS_PROFILE AWS_REGION VPC_ID SUBNET_ID INSTANCE_TYPE VOLUME_SIZE
  AMI_ID NAME_PREFIX ADMIN_IP DEV_VPC_CIDR GCP_NAT_IP S3_BUCKET S3_PREFIX
)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required variable $var is not set in .env"
    exit 1
  fi
done

# Auto-append /32 if ADMIN_IP is a bare IP (no CIDR suffix)
if [[ "$ADMIN_IP" != *"/"* ]]; then
  ADMIN_IP="${ADMIN_IP}/32"
  echo "INFO: ADMIN_IP auto-corrected to CIDR: $ADMIN_IP"
fi

# ---------------------------------------------------------------------------
# 2. AWS CLI shorthand
# ---------------------------------------------------------------------------
AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"

echo "============================================="
echo " V2 Monitoring Server - Infrastructure Setup"
echo "============================================="
echo "Profile : $AWS_PROFILE"
echo "Region  : $AWS_REGION"
echo "VPC     : $VPC_ID"
echo "Prefix  : $NAME_PREFIX"
echo ""

# ---------------------------------------------------------------------------
# 3. Create Security Group
# ---------------------------------------------------------------------------
echo "[1/6] Creating Security Group: ${NAME_PREFIX}-sg ..."

SG_ID=$($AWS ec2 create-security-group \
  --group-name "${NAME_PREFIX}-sg" \
  --description "V2 Monitoring Server SG" \
  --vpc-id "$VPC_ID" \
  --output text --query 'GroupId')

echo "       SG created: $SG_ID"

$AWS ec2 create-tags \
  --resources "$SG_ID" \
  --tags "Key=Name,Value=${NAME_PREFIX}-sg"

echo "       Adding ingress rules ..."

# Grafana (3000) - Admin IP only
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=3000,ToPort=3000,IpRanges=[{CidrIp=${ADMIN_IP},Description=Grafana}]"

# Prometheus remote_write (9090) - Dev VPC + GCP NAT
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=9090,ToPort=9090,IpRanges=[{CidrIp=${DEV_VPC_CIDR},Description=Prometheus-DevVPC},{CidrIp=${GCP_NAT_IP},Description=Prometheus-GCP}]"

# Loki push (3100) - Dev VPC + GCP NAT
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=3100,ToPort=3100,IpRanges=[{CidrIp=${DEV_VPC_CIDR},Description=Loki-DevVPC},{CidrIp=${GCP_NAT_IP},Description=Loki-GCP}]"

# Tempo OTLP gRPC (4317) - Dev VPC + GCP NAT
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=4317,ToPort=4317,IpRanges=[{CidrIp=${DEV_VPC_CIDR},Description=Tempo-gRPC-DevVPC},{CidrIp=${GCP_NAT_IP},Description=Tempo-gRPC-GCP}]"

# Tempo OTLP HTTP (4318) - Dev VPC + GCP NAT
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=4318,ToPort=4318,IpRanges=[{CidrIp=${DEV_VPC_CIDR},Description=Tempo-HTTP-DevVPC},{CidrIp=${GCP_NAT_IP},Description=Tempo-HTTP-GCP}]"

echo "       Ingress rules added (3000, 9090, 3100, 4317, 4318)"

# ---------------------------------------------------------------------------
# 4. Create IAM Role + Instance Profile
# ---------------------------------------------------------------------------
echo "[2/6] Creating IAM Role: ${NAME_PREFIX}-role ..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}'

$AWS iam create-role \
  --role-name "${NAME_PREFIX}-role" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --output text --query 'Role.Arn'

echo "       Attaching AmazonSSMManagedInstanceCore policy ..."

$AWS iam attach-role-policy \
  --role-name "${NAME_PREFIX}-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

echo "       Creating Instance Profile: ${NAME_PREFIX}-profile ..."

$AWS iam create-instance-profile \
  --instance-profile-name "${NAME_PREFIX}-profile" \
  --output text --query 'InstanceProfile.Arn'

$AWS iam add-role-to-instance-profile \
  --instance-profile-name "${NAME_PREFIX}-profile" \
  --role-name "${NAME_PREFIX}-role"

echo "       Attaching S3 read inline policy for bucket: $S3_BUCKET ..."

$AWS iam put-role-policy \
  --role-name "${NAME_PREFIX}-role" \
  --policy-name "${NAME_PREFIX}-s3-read" \
  --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Effect\": \"Allow\",
    \"Action\": [\"s3:GetObject\", \"s3:ListBucket\"],
    \"Resource\": [
      \"arn:aws:s3:::${S3_BUCKET}\",
      \"arn:aws:s3:::${S3_BUCKET}/${S3_PREFIX}/*\"
    ]
  }]
}"

echo "       IAM Role and Instance Profile created"

# ---------------------------------------------------------------------------
# 5. Wait for instance profile propagation
# ---------------------------------------------------------------------------
echo "[3/6] Waiting 10 seconds for instance profile propagation ..."
sleep 10

# ---------------------------------------------------------------------------
# 6. Create EC2 Instance
# ---------------------------------------------------------------------------
echo "[4/6] Creating EC2 Instance ..."

INSTANCE_ID=$($AWS ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${VOLUME_SIZE},VolumeType=gp3}" \
  --iam-instance-profile "Name=${NAME_PREFIX}-profile" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_PREFIX}}]" \
  --associate-public-ip-address \
  --output text --query 'Instances[0].InstanceId')

echo "       Instance launched: $INSTANCE_ID"

# ---------------------------------------------------------------------------
# 7. Wait for instance running
# ---------------------------------------------------------------------------
echo "[5/6] Waiting for instance to reach running state ..."

$AWS ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PRIVATE_IP=$($AWS ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --output text --query 'Reservations[0].Instances[0].PrivateIpAddress')

echo "       Instance is running (Private IP: $PRIVATE_IP)"

# ---------------------------------------------------------------------------
# 8. Allocate and Associate EIP
# ---------------------------------------------------------------------------
echo "[6/6] Allocating and associating Elastic IP ..."

ALLOCATION_ID=$($AWS ec2 allocate-address \
  --domain vpc \
  --output text --query 'AllocationId')

$AWS ec2 create-tags \
  --resources "$ALLOCATION_ID" \
  --tags "Key=Name,Value=${NAME_PREFIX}-eip"

ASSOCIATION_ID=$($AWS ec2 associate-address \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$ALLOCATION_ID" \
  --output text --query 'AssociationId')

PUBLIC_IP=$($AWS ec2 describe-addresses \
  --allocation-ids "$ALLOCATION_ID" \
  --output text --query 'Addresses[0].PublicIp')

echo "       EIP allocated: $PUBLIC_IP (Association: $ASSOCIATION_ID)"

# ---------------------------------------------------------------------------
# 9. Save outputs to .env
# ---------------------------------------------------------------------------
echo ""
echo "Saving outputs to .env ..."

ENV_FILE="$SCRIPT_DIR/.env"

update_env_var() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

update_env_var "MONITOR_INSTANCE_ID" "$INSTANCE_ID"
update_env_var "MONITOR_PUBLIC_IP" "$PUBLIC_IP"
update_env_var "MONITOR_PRIVATE_IP" "$PRIVATE_IP"

echo "       .env updated"

# ---------------------------------------------------------------------------
# 10. Print summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " V2 Monitoring Server - Setup Complete"
echo "============================================="
echo " Instance ID : $INSTANCE_ID"
echo " Public IP   : $PUBLIC_IP"
echo " Private IP  : $PRIVATE_IP"
echo " SG ID       : $SG_ID"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Wait ~2 min for SSM agent to register"
echo "  2. Run 02_install_monitoring.sh to install Prometheus, Loki, Tempo, Grafana"

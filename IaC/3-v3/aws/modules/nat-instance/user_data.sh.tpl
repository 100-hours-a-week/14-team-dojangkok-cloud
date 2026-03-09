#!/bin/bash
# ============================================================
# V3 K8S IaC — NAT Instance user_data
# ASG 교체 시 자동으로 source/dest check 비활성화 + RT route 갱신
# Branch: feat/v3-k8s-iac
# ============================================================
set -euo pipefail

# --- Install AWS CLI ---
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq awscli

REGION="${region}"
ROUTE_TABLE_IDS="${route_table_ids}"
VPC_CIDR="${vpc_cidr}"

# --- Get instance metadata (IMDSv2) ---
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

# --- Disable source/dest check ---
aws ec2 modify-instance-attribute \
  --instance-id "$INSTANCE_ID" \
  --no-source-dest-check \
  --region "$REGION"

# --- Update all private route tables to point to this instance ---
IFS=',' read -ra RT_ARRAY <<< "$ROUTE_TABLE_IDS"
for RT_ID in "$${RT_ARRAY[@]}"; do
  aws ec2 replace-route \
    --route-table-id "$RT_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" 2>/dev/null || \
  aws ec2 create-route \
    --route-table-id "$RT_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION"
done

# --- Enable IP forwarding ---
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-nat.conf
sysctl -p /etc/sysctl.d/99-nat.conf

# --- Configure iptables NAT (detect outbound interface) ---
OUTBOUND_IF=$(ip route show default | awk '{print $5}' | head -1)
iptables -t nat -A POSTROUTING -o "$OUTBOUND_IF" -s "$VPC_CIDR" -j MASQUERADE

# --- Persist iptables (non-interactive) ---
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent
netfilter-persistent save

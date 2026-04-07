#!/bin/bash
# TF output → Ansible inventory 변환
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
INV_FILE="${SCRIPT_DIR}/../ansible/inventory/hosts.ini"

cd "$TF_DIR"

echo "=== Terraform output에서 inventory 생성 ==="

CP=$(terraform output -json control_plane)
CP_PUBLIC=$(echo "$CP" | jq -r '.public_ip')
CP_PRIVATE=$(echo "$CP" | jq -r '.private_ip')

WORKERS=$(terraform output -json workers)

cat > "$INV_FILE" << EOF
[control_plane]
cp ansible_host=${CP_PUBLIC} private_ip=${CP_PRIVATE}

[workers]
$(echo "$WORKERS" | jq -r 'to_entries[] | "w-2\(.value.az)-1 ansible_host=\(.value.public_ip) private_ip=\(.value.private_ip) node_az=ap-northeast-2\(.value.az)"')

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/dojangkok-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

echo "=== 생성 완료: ${INV_FILE} ==="
cat "$INV_FILE"

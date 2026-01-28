#!/usr/bin/env bash
set -euo pipefail

# ===== 사용자 설정 =====
CNF="/root/.mysql/backup.cnf"
BACKUP_DIR="/var/backups/mysql"

S3_BUCKET="ktb-team14-dojangkok-mysql-backup"
S3_PREFIX="mysqldump"

# 특정 DB만 백업하려면 여기에 넣기 (예: ("appdb"))
DB_LIST=("dojangkok")

# 시스템 DB 제외 정규식
EXCLUDE_REGEX='^(information_schema|performance_schema|mysql|sys)$'

# KST 기준 날짜/시간 설정
DATE="$(TZ=Asia/Seoul date +%F)"
TIME="$(TZ=Asia/Seoul date +%H%M%S)"
HOST="$(hostname -s)"
OUT_DIR="${BACKUP_DIR}/${DATE}"
LOG_FILE="${BACKUP_DIR}/backup.log"

log() { echo "[$(TZ=Asia/Seoul date '+%F %T')] $*" | tee -a "${LOG_FILE}"; }

mkdir -p "${OUT_DIR}"

dump_one_db() {
  local db="$1"
  local out="${OUT_DIR}/${HOST}_${db}_${DATE}_${TIME}.sql.gz"

  log "Dump start: ${db} -> ${out}"

  mysqldump --defaults-extra-file="${CNF}" \
    --single-transaction \
    --routines --triggers --events \
    --hex-blob \
    --set-gtid-purged=OFF \
    --databases "${db}" \
    | gzip -1 > "${out}"

  log "Dump done : ${db}"
}

dump_all_dbs_except_system() {
  mapfile -t DBS < <(mysql --defaults-extra-file="${CNF}" -Nse "SHOW DATABASES;")
  for db in "${DBS[@]}"; do
    if [[ ! "${db}" =~ ${EXCLUDE_REGEX} ]]; then
      dump_one_db "${db}"
    fi
  done
}

log "Backup job started (KST: ${DATE} ${TIME})"
log "Crontab Schedule Recommendation: 0 0 * * * (Everyday 00:00 KST)"

# 1) mysqldump
if [[ ${#DB_LIST[@]} -gt 0 ]]; then
  for db in "${DB_LIST[@]}"; do
    dump_one_db "${db}"
  done
else
  dump_all_dbs_except_system
fi

# 2) gzip 무결성 체크
log "Integrity check (gzip -t)"
find "${OUT_DIR}" -type f -name "*.gz" -print0 | xargs -0 -n1 gzip -t

# 3) S3 업로드 및 로컬 삭제
S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}/${HOST}/${DATE}/"
log "S3 upload start -> ${S3_URI}"

if aws s3 cp "${OUT_DIR}/" "${S3_URI}" --recursive; then
  log "S3 upload success. Removing local files..."
  rm -rf "${OUT_DIR}"
  log "Local removed: ${OUT_DIR}"
else
  log "ERROR: S3 upload failed. Keeping local files for safety."
  exit 1
fi

log "Backup job finished"
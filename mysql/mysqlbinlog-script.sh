#!/usr/bin/env bash
set -euo pipefail

# ===== 사용자 설정 =====
BINLOG_BASENAME="mysql-bin"

CNF="/root/.mysql/backup.cnf"
MYSQL_DATA_DIR="/var/lib/mysql/binlog"

S3_BUCKET="ktb-team14-dojangkok-mysql-backup"
S3_PREFIX="binlog"

# KST 날짜 (일자별 폴더 정리를 위함)
DATE="$(TZ=Asia/Seoul date +%F)"
HOST="$(hostname -s)"
LOG_FILE="/var/backups/mysql/binlog_upload.log"

log() { echo "[$(TZ=Asia/Seoul date '+%F %T')] $*" | tee -a "${LOG_FILE}"; }

log "Binlog backup started"
log "Crontab Schedule Recommendation: 0 * * * * (Every hour at minute 0)"

# 1. 예외 처리: 현재 활성 binlog 확인
ACTIVE_FILE=$(mysql --defaults-extra-file="${CNF}" -Nse "SHOW MASTER STATUS" | awk '{print $1}')

if [[ -z "${ACTIVE_FILE}" ]]; then
  log "ERROR: Could not determine active binlog file"
  exit 1
fi

log "Current Active binlog: ${ACTIVE_FILE} - Triggering Rotation..."

# 2. 로그 Rotate (현재 기록중인 파일을 닫고 새 파일을 염)
mysql --defaults-extra-file="${CNF}" -e "FLUSH BINARY LOGS;"

# 3. Rotate 이후 새로운 활성 파일 확인 (이 파일 이전의 파일들은 모두 안전하게 업로드 가능)
ACTIVE_AFTER=$(mysql --defaults-extra-file="${CNF}" -Nse "SHOW MASTER STATUS" | awk '{print $1}')
log "New Active binlog after rotate: ${ACTIVE_AFTER}"

# 4. S3 Sync 수행 (일자별 폴더: .../host/YYYY-MM-DD/ )
S3_URI="s3://${S3_BUCKET}/${S3_PREFIX}/${HOST}/${DATE}/"

log "Syncing files to ${S3_URI} (excluding active file: ${ACTIVE_AFTER})"

# 안전한 업로드를 위해 '현재 활성 파일'은 제외
if aws s3 sync "${MYSQL_DATA_DIR}" "${S3_URI}" \
  --exclude "*" \
  --include "${BINLOG_BASENAME}.*" \
  --exclude "${ACTIVE_AFTER}" \
  --exclude "${BINLOG_BASENAME}.index" \
  --no-progress; then
  
  log "S3 sync successful."

  # 5. 로컬 정리: PURGE BINARY LOGS 명령어 사용
  # '현재 활성 파일' 이전에 생성된 모든 로그(업로드 완료된 것들)를 MySQL이 안전하게 삭제하도록 함.
  # 직접 rm 하는 것보다 인덱스 관리가 되어 훨씬 안전함.
  
  log "Purging local binary logs up to ${ACTIVE_AFTER}..."
  mysql --defaults-extra-file="${CNF}" -e "PURGE BINARY LOGS TO '${ACTIVE_AFTER}';"
  log "Local cleanup done."

else
  log "ERROR: S3 sync failed. Skipping cleanup."
  exit 1
fi

log "Binlog backup completed"
# MySQL 백업 전략

## 배경
현재 도장콕 서비스는 비용 효율성을 극대화하기 위해 **단일 EC2 인스턴스** 내에 웹 애플리케이션과 데이터베이스(MySQL)를 모두 직접 설치하여 운영하고 있습니다.

이러한 구조는 AWS RDS와 같은 완전 관리형 서비스가 제공하는 자동 백업이나 고가용성(HA) 기능을 기본적으로 누릴 수 없다는 취약점이 있습니다. 하지만 서비스의 핵심 자산인 데이터의 안정성을 보장하는 것은 서비스 신뢰도와 직결되는 매우 중요한 과제입니다.

따라서, 본 문서에서는 이러한 환경적 제약을 극복하고 데이터를 안전하게 보호하기 위해 수립한 **두 가지 핵심 백업 전략**과 그 구체적인 구현 방법에 대해 다룹니다.

## mysqldump
우선 가장 기본적으로 mysqldump를 통해 매일 자정(00:00)에 MySQL 전체 상태에 대한 스냅샷을 구성하여 파일로 저장하고, 이를 S3로 전송하여 관리하고 있습니다. mysqldump 수행 시 사용하는 스크립트에 포함된 주요 명령어는 아래와 같습니다.
```bash
mysqldump --defaults-extra-file="${CNF}" \
--single-transaction \
--routines --triggers --events \
--hex-blob \
--set-gtid-purged=OFF \
--databases "${db}" \
| gzip -1 > "${out}"
```

스크립트에서 사용된 각 옵션의 역할은 다음과 같습니다.

| 옵션 | 설명 |
| :--- | :--- |
| **`--defaults-extra-file="${CNF}"`** | • 비밀번호와 같은 민감한 인증 정보를 명령어에 직접 노출하지 않고 별도 설정 파일에서 읽어오도록 합니다.<br>• `ps` 명령어로 프로세스를 조회했을 때 비밀번호가 노출되는 것을 방지하는 보안 옵션입니다. |
| **`--single-transaction`** | • **(핵심)** InnoDB 엔진 사용 시, 테이블을 잠그지(Lock) 않고 트랜잭션을 이용하여 일관된 상태의 백업을 수행합니다.<br>• 백업 중에도 서비스의 읽기/쓰기가 가능하도록 해주는 가장 중요한 옵션입니다. |
| **`--routines`<br>`--triggers`<br>`--events`** | • 데이터뿐만 아니라 데이터베이스에 정의된 **저장 프로시저(Stored Procedures)**, **트리거(Triggers)**, **이벤트 스케줄러(Events)** 등의 로직까지 모두 포함하여 백업합니다. |
| **`--hex-blob`** | • 바이너리 데이터(이미지, 파일 등)를 16진수(Hexadecimal) 문자열로 변환하여 백업합니다.<br>• 특수 문자가 포함된 데이터가 SQL 문법 오류를 일으키거나 깨지는 것을 방지합니다. |
| **`--set-gtid-purged=OFF`** | • 백업 파일에 GTID(Global Transaction ID) 정보를 포함하지 않도록 설정합니다.<br>• 주로 복구할 DB가 새로운 인스턴스이거나, GTID 정보 충돌 없이 데이터를 붓고 싶을 때 사용합니다. |
| **`--databases "${db}"`** | • 특정 데이터베이스를 지정하여 백업합니다.<br>• 백업 결과물에 `CREATE DATABASE` 및 `USE` 문이 포함되어, 복구 시 해당 DB가 없으면 자동으로 생성해 줍니다. |

(mysqldump에 대한 전체 스크립트는 ```mysql/mysqldump-script.sh``` 에서 확인 가능합니다.)

백업 수행 시각을 **매일 자정(KST 00:00)**으로 설정한 근거는 다음과 같습니다.

1. **한국(KST) 중심의 서비스 운영 환경**
    - 도장콕은 국내 주택 임대차 시장을 타겟으로 하는 한국 내수 서비스입니다.
    - 데이터의 관리 및 운영 기준이 모두 한국 시간에 맞춰져 있으므로, 백업 시점 또한 KST를 기준으로 통일하여 운영 효율성을 높였습니다.
2. **데이터 관리 및 운영 정책의 일관성**
    - 일 단위 데이터의 기준점을 날짜가 변경되는 시점(00:00)으로 설정하여, 데이터 이력 관리(History Management)의 명확성을 확보했습니다.
3. **시스템 부하 및 사용자 영향 최소화**
    - 비즈니스 도메인 특성상, 심야 시간대(00:00)는 매물을 탐색하거나 계약 관련 활동을 하는 사용자가 현저히 적은 시간대입니다.
    - 트래픽이 가장 낮은 시간대에 백업을 수행함으로써 시스템 부하를 분산하고 사용자 경험에 미치는 영향을 최소화했습니다.


## binary log
mysqldump를 통한 일일 백업은 데이터 전체의 스냅샷을 저장하는 훌륭한 전략이지만, 백업 주기(24시간) 사이에 발생하는 데이터 변경 사항은 보호하지 못한다는 한계가 있습니다. 만약 이 공백기에 장애가 발생하거나 담당자의 실수가 있을 경우, 마지막 백업 이후의 데이터는 영구적으로 유실될 위험이 있습니다.

따라서 이러한 데이터 손실 가능성을 최소화하고 데이터 안정성을 더욱 강화하기 위해, Binary Log(binlog)를 활용한 실시간 증분 백업 전략을 추가로 도입하였습니다.

```bash
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

# 안전한 업로드를 위해 '현재 활성 파일(ACTIVE_AFTER)'은 제외하고 업로드
aws s3 sync "${MYSQL_DATA_DIR}" "${S3_URI}" \
  --exclude "*" \
  --include "${BINLOG_BASENAME}.*" \
  --exclude "${ACTIVE_AFTER}" \
  --exclude "${BINLOG_BASENAME}.index" \
  --no-progress
```

(mysqlbinlog에 대한 전체 스크립트는 ```mysql/mysqlbinlog-script.sh``` 에서 확인 가능합니다.)

스크립트에서 사용된 핵심 구문과 옵션의 역할은 다음과 같습니다.

| 구문/옵션 | 설명 |
| :--- | :--- |
| **`FLUSH BINARY LOGS`** | • 현재 기록 중인 바이너리 로그 파일을 닫고, 새로운 번호의 빈 로그 파일을 생성합니다.<br>• 파일을 분리함으로써 이미 기록이 완료된 과거 로그 파일들을 안전하게 백업(업로드)할 수 있는 상태로 만듭니다. |
| **`SHOW MASTER STATUS`** | • 현재 MySQL이 기록하고 있는 활성(Active) 바이너리 로그 파일명을 조회합니다.<br>• `FLUSH` 전과 후의 파일명을 비교하여, 어떤 파일이 "완료된 파일"인지 식별하는 데 사용합니다. |
| **`aws s3 sync`** | • 지정된 로컬 디렉토리와 S3 버킷 경로를 동기화합니다.<br>• `cp`와 달리 변경된 파일만 식별하여 업로드하므로 효율적입니다. |
| **`--exclude "${ACTIVE_AFTER}"`** | • **(핵심)** 현재 MySQL이 실시간으로 쓰고 있는(Lock 등이 걸릴 수 있는) 활성 로그 파일은 업로드 대상에서 **제외**합니다.<br>• 데이터 정합성이 깨지거나 전송 중 파일 변경으로 인한 오류를 방지하기 위함입니다. |
| **`--include ...`**<br>**`--exclude ...`** | • `binlog.*` 패턴의 파일만 선택적으로 업로드하고, 인덱스 파일이나 임시 파일 등 불필요한 파일은 제외하여 백업 본을 깔끔하게 유지합니다. |

MySQL의 Binary Log는 데이터베이스에서 발생하는 모든 변경 사항(INSERT, UPDATE, DELETE 등)을 순차적으로 기록합니다. 이 로그를 1시간 단위(매시 정각)로 S3에 안전하게 업로드하여 보관합니다.

S3 업로드는 1시간 주기로 이루어지지만, 로컬 디스크에는 변경 사항이 실시간으로 바이너리 로그 파일에 기록되고 있습니다. 따라서 EC2 인스턴스의 디스크 자체가 손상되는 물리적 장애가 아닌 이상, **실시간에 가까운 데이터 복구**가 가능합니다.

업로드 주기를 1~10분 단위로 짧게 설정하여 안정성을 더 높일 수도 있으나, 잦은 I/O 작업과 S3 요청은 단일 인스턴스에 오버헤드를 유발하여 서비스 성능에 영향을 줄 수 있습니다. 현재 AWS 환경(EBS)의 높은 내구성을 고려했을 때, 1시간 주기의 S3 동기화가 **시스템 성능과 데이터 안정성 사이의 최적의 균형점**이라고 판단하였습니다.
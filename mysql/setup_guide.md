# MySQL 백업 스크립트 사용 가이드

본 문서에서는 단일 인스턴스로 구성한 MySQL을 다음 2가지 형태로 백업 정보를 구성하도록 설정하는 절차를 안내합니다. 각 팀의 상황에서 따라서 적절한 전략을 선택하여 선택적으로 적용하시면 됩니다.
1. mysqldump
2. binarylog

#### 1. MySQL 설치 인스턴스 접속
mysql이 설치 및 실행 중인 인스턴스에 접속합니다.

#### 2. 백업 시 사용하기 위한 mysql 계정생성
root가 아닌 백업에 사용할 수 있는 mysql 계정을 생성합니다.
이때, 생성한 계정에 대해서 다음 권한을 부여합니다.
```sql
CREATE USER 'backup_user_name'@'localhost' IDENTIFIED BY 'password...'
GRANT SELECT, RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT, SHOW VIEW, EVENT, TRIGGER ON *.* TO `backup`@`localhost`
GRANT BINLOG_ADMIN ON *.* TO `backup`@`localhost`
```

#### 3. 백업 시 사용할 설정 파일 생성
다음 명령어들을 통하여 백업 스크립트 수행 시 참조할 설정 파일을 추가합니다.
```bash
# 1. 디렉토리 생성 (이미 있으면 무시됨)
sudo mkdir -p /root/.mysql

# 2. 파일 생성 및 내용 작성
sudo tee /root/.mysql/backup.cnf > /dev/null <<EOF
[client]
user=user_name
password=user_password
host=localhost
EOF

# 3. 보안 설정 (매우 중요: root 이외에는 아무도 못 보게 함)
sudo chmod 600 /root/.mysql/backup.cnf
sudo chown root:root /root/.mysql/backup.cnf
```

#### 4. binary log 저장위치 생성 및 권한 부여
binary 로그를 저장할 경로를 생성 후 권한을 부여합니다. 해당 과정을 수행하지 않을 경우 mysql 재시작이 실패하며 서비스 중단이 발생할 수 있습니다. 해당 설정을 적용하는 과정에서는 mysql을 재시작해야하기에 서비스 다운타임이 발생하므로 가급적 운영 서버에 올리기 전에 인프라를 구성하는 과정에서 미리 진행할 것을 권장드립니다.
```bash
sudo mkdir -p /var/lib/mysql/binlog
sudo chown -R mysql:mysql /var/lib/mysql/binlog
sudo systemctl restart mysql
sudo systemctl status mysql
```

#### 5. mysql binarylog 관련 옵션 활성화
mysql은 기본적으로 binary 관련 옵션이 비활성화 되어있어 해당 옵션을 별도의 설정을 통해 활성화해주는 작업이 필요합니다. 설정 파일을 열고 들어가서 직접 수정하기 보다는 별도의 파일을 만들어서 관련 설명을 명시적으로 쉽게 관리할 수 있도록 구성합니다.

mysql 설정 파일이 위치한 경로인 아래 경로로 이동해서 binlog 설정 파일을 추가합니다.
> /etc/mysql/mysql.conf.d
```ini
[mysqld]
# Binary Logging ON
log_bin = /var/lib/mysql/binlog/mysql-bin
server_id = 101

# PITR에 가장 안전한 포맷
binlog_format = ROW

# 로그 파일 롤링 사이즈
max_binlog_size = 256M

# 자동 만료 (7일)
binlog_expire_logs_seconds = 604800

# 트랜잭션마다 바로 디스크에 로그를 기록
sync_binlog = 1
```

#### 6. 백업 파일 저장경로 생성 및 권한부여
mysqldump 파일이 저장될 수 있는 로컬 경로를 생성 후, 쓰기 권한을 부여합니다.
> mkdir /var/backups/mysql

binlog의 경우 mysql이 사전에 지정해둔 아래의 경로로 저장되어 따로 설정하지 않습니다.
> /var/lib/mysql

#### 7. 백업 스크립트 작성 및 저장
아래 경로에 백업 스크립트를 작성 및 저장합니다.
> /usr/local/sbin

해당 문서와 동일한 경로에 있는 *.sh 파일을 복사하고 저장합니다. 파일을 구성한 뒤 chmod 700 * 을 입력하여 실행권한을 부여합니다. 실행 권한을 부여해야 해당 스크립트를 실행하여 원하는 동작을 수행할 수 있습니다.

#### 8. service, timer 파일 생성
백업 스크립트는 일정 주기에 따라 주기적으로 실행될 수 있도록 설정해야 합니다. 이에 따라 리눅스에서 일정 주기마다 해당 스크립트를 실행하여 주기적으로 백업을 수행할 수 있도록 service, timer 파일을 생성하여 스크립트를 구성합니다. 마찬가지로 해당 설정파일도 해당 문서와 동일 경로에 있는 service, timer 파일을 참고하여 적용하시면 됩니다.

아래 경로에 다음 service, timer 파일 한 쌍을 구성합니다.
> /etc/systemd/system

(mysql-backup-s3.service)
```ini
[Unit]
Description=MySQL mysqldump backup and upload to S3

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mysql_backup_to_s3.sh
```

(mysql-backup-s3.timer)
```ini
[Unit]
Description=Run MySQL backup to S3 daily at midnight

[Timer]
OnCalendar=*-*-* 00:00:00 Asia/Seoul
Persistent=true

[Install]
WantedBy=timers.target
```

(mysql-binlog-s3.service)
```ini
[Unit]
Description=Upload MySQL binlog to S3

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mysql_binlog_to_s3.sh
```

(mysql-binlog-s3.timer)
```ini
[Unit]
Description=Run MySQL binlog backup hourly

[Timer]
OnCalendar=*-*-* *:00:00 Asia/Seoul
Persistent=true

[Install]
WantedBy=timers.target
```

#### 9. service, timer 파일 적용
systemd가 새로운 설정파일이 생겼음을 인식할 수 있도록 다음 명령어를 입력합니다.
> sudo systemctl daemon-reload

추가한 타이머를 각각 추가 및 시작합니다.
> sudo systemctl enable ${timer_file_name}

> sudo systemctl start ${timer_file_name}

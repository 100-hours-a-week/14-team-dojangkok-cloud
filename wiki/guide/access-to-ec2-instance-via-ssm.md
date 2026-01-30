## 배경
AWS 인프라의 보안 강화를 위해 불필요한 포트 개방을 최소화하고 **SSM(Systems Manager)** 접속 방식을 도입했다. 하지만 이로 인해 서버 접속 절차가 기존보다 다소 복잡해져 접근성이 낮아진 측면이 있다. 따라서 본 문서는 이러한 복잡함을 해소하고, 인프라 담당자와 개발자가 장소에 구애받지 않고 **안전하고 간편하게** 서버에 접속할 수 있도록 표준화된 절차와 필수 명령어들을 안내하는 것을 목적으로 한다.

## 1. 최초 세팅
해당 과정은 한 번만 수행하면 되는 과정으로 SSM 접속 방식을 클라이언트 PC에서 사용하기 위해 필요한 런타임을 세팅합니다.
#### 1. AWS CLI, SSM 플러그인 설치
SSM 접속방식을 사용하기 위해서는 클라이언트 PC에 다음 2가지 런타임을 설치해야 한다.
1. awscli
2. session-manager-plugin

다음 명령어들을 순차적으로 실행하여 설치를 진행합니다. (이때, 각 클라이언트 PC에는 Homebrew가 설치되어 있음을 가정한다)
```zsh
brew update
brew install awscli
brew install --cask session-manager-plugin
```

설치가 완료되면 다음 명령어로 정상 설치 여부를 확인합니다.
```zsh
session-manager-plugin --version
```
#### 2. AWS CLI 로그인
다음 명령어를 입력한 뒤 기존에 전달드린 IAM 정보(Access Key ID, Secret Access Key)를 입력하여 설정을 진행합니다.
```zsh
aws configure --profile default
```

## 2. 서버 Shell 접속
해당 단계에서는 대상 인스턴스에 서버 Shell 접속을 위한 명령어를 안내합니다.
```zsh
aws ssm start-session --target ${instance_id} --region ap-northeast-2
# SSM 접속 시 SSM 전용 계정으로 로그인 되므로 /home/ubuntu에 접근할 수 없습니다.
# 따라서 로그인 후 해당 명령어를 통해 ubuntu로 계정을 전환해야 합니다.
sudo su - ubuntu
```
instance_id의 경우 관리자에게 문의하여 전달 받으시면 됩니다.

## 3. MySQL 접속
해당 단계에서는 MySQL 접속을 위한 명령어를 안내합니다.
```zsh
aws ssm start-session --target ${instance_id} \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3306"],"localPortNumber":["13306"]}' --region ap-northeast-2
```
1. 위 예시 명령어에서 **localPortNumber**의 경우 임의로 할당해둔 값이며 클라이언트 PC에서 충돌되지 않은 포트 번호를 할당하여 사용하시면 됩니다.
2. instance_id의 경우 관리자에게 문의하여 전달 받으시면 됩니다.
3. 접속하고자 하는 IDE에서 **host는 127.0.0.1**, **포트번호는 localPortNumber**로 할당하시면 됩니다.
4. 기타 MySQL 계정, 데이터베이스, 비밀번호는 기존에 전달드린 정보를 사용하시면 됩니다.
5. 이 명령어를 실행 중인 터미널 창을 닫으면 연결이 끊어지니, 백그라운드에서 작업하거나 별도의 터미널 창을 유지해주세요.

## 4. Redis 접속
해당 단계에서는 Redis 접속을 위한 명령어를 안내합니다.
```zsh
aws ssm start-session --target ${instance_id} \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6379"],"localPortNumber":["16379"]}' --region ap-northeast-2
```
1. 위 예시 명령어에서 **localPortNumber**의 경우 임의로 할당해둔 값이며 클라이언트 PC에서 충돌되지 않은 포트 번호를 할당하여 사용하시면 됩니다.
2. instance_id의 경우 관리자에게 문의하여 전달 받으시면 됩니다.
3. 접속하고자 하는 IDE에서 **host는 127.0.0.1**, **포트번호는 localPortNumber**로 할당하시면 됩니다.
4. Redis 비밀번호는 기존에 전달드린 정보를 사용하시면 됩니다.
5. 이 명령어를 실행 중인 터미널 창을 닫으면 연결이 끊어지니, 백그라운드에서 작업하거나 별도의 터미널 창을 유지해주세요.

## 5. 모니터링 페이지 접속
해당 단계에서는 모니터링 페이지에 접속하기 위한 명령어를 안내합니다.
```zsh
aws ssm start-session --target ${instance_id} \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}' --region ap-northeast-2
```
1. 위 예시 명령어에서 **localPortNumber**의 경우 임의로 할당해둔 값이며 클라이언트 PC에서 충돌되지 않은 포트 번호를 할당하여 사용하시면 됩니다.
2. instance_id의 경우 관리자에게 문의하여 전달 받으시면 됩니다.
3. 웹 브라우저 주소창에 **http://localhost:{localPortNumber}**를 입력하여 접속하시면 됩니다. (모니터링 페이지 사용법에 대한 세부 안내는 별도 페이지에서 안내합니다.)
4. 이 명령어를 실행 중인 터미널 창을 닫으면 연결이 끊어지니, 백그라운드에서 작업하거나 별도의 터미널 창을 유지해주세요.
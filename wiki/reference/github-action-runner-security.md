# Github Actions 보안 전략

### 배경
현재 도장콕의 인프라는 단일 Public Subnet에 인스턴스를 배치하는 형태로, 접근성과 관리 편의성은 높지만 WAS와 DB 같은 중요 리소스가 인터넷에 노출되어 보안 취약점이 존재합니다.

이를 보완하기 위한 가장 보편적인 대책은 **"보안그룹(Security Group)을 엄격하게 관리하는 것"**입니다. 불필요한 IP와 포트를 차단하고 접근을 최소화한다면, 단일 Subnet 구조에서도 충분한 보안 수준을 유지할 수 있습니다.

하지만 **Github Actions 기반의 CI/CD를 도입할 경우 이 방법은 유효하지 않습니다.** Github Action Runner는 실행 시마다 IP가 변경되며 그 대역이 매우 광범위하기 때문에, 배포를 위해 사실상 모든 IP(0.0.0.0/0)에 대해 SSH(22) 접근을 허용해야 하는 상황이 발생합니다.

즉, Github Action Runner의 'IP 비고정성'으로 인해, 단일 Public Subnet의 보안을 지탱하는 핵심인 '보안그룹 접근 제어'를 적용할 수 없는 딜레마에 빠지게 됩니다.

따라서, 이어지는 내용에서는 단일 Public Subnet 환경에서 Github Actions를 사용할 때 겪게 되는 이러한 문제를 해결하고, 보안 취약점을 최소화하기 위한 구체적인 전략을 정리합니다.

## 별도 배포 서버 구축 (Self-Hosted Runner / Jenkins)
가장 쉽게 고려할 수 있는 대안은 **Github Actions Self-Hosted Runner**나 **Jenkins**와 같은 별도의 배포 전용 서버를 구축하는 것입니다. 배포 서버에 고정 IP를 할당하고 보안그룹에서 해당 IP만 허용한다면, SSH(22) 접속 대상을 '불특정 다수'에서 '극히 일부'로 좁힐 수 있어 보안성을 크게 높일 수 있습니다.

하지만 이 방식 역시 **관리용 포트(22)를 외부에 개방해야 한다는 근본적인 보안 취약점은 여전히 존재합니다.** 또한, '단일 인스턴스'로 비용 효율을 추구하는 현재 단계의 도장콕 프로젝트에서 배포만을 위한 추가 서버(인스턴스) 운영은 **불필요한 비용 낭비**로 이어지므로 합리적인 해결책이라 보기 어렵습니다.

## 해결책: 보안그룹 동적 업데이트 (Dynamic Security Group Update)

비용 효율성과 보안성을 모두 만족하는 현실적인 대안은 **"워크플로우 실행 시점에만 보안그룹을 동적으로 수정하는 방식"**입니다.

이 방식은 Github Actions 워크플로우가 시작될 때 실행 중인 Runner의 Public IP를 확인하여 AWS 보안그룹(Security Group) 인바운드 규칙에 해당 IP를 추가(22번 포트 허용)하고, 배포 작업이 완료되면 해당 규칙을 즉시 삭제하는 전략입니다.

이를 통해 평상시에는 22번 포트를 완전히 차단하여 외부 위협을 방지하고, 배포가 진행되는 극히 짧은 시간에만 특정 IP 접근을 허용함으로써 **추가 인프라 비용 없이** 보안 취약점을 최소화할 수 있습니다.

더불어, **관리자(운영자)의 서버 접근** 역시 22번 포트를 사용할 필요가 없습니다. AWS Systems Manager (SSM)를 활용하면 포트 개방 없이도 안전하게 인스턴스에 접속할 수 있으므로, 결과적으로 보안그룹에는 웹 서비스를 위한 **80(HTTP), 443(HTTPS) 포트만 상시 개방**하여 인프라의 보안성을 극대화할 수 있습니다.

## CI/CD 스크립트 상의 구현
해당 동작은 CI/CD 스크립트 상에서 다음과 같이 구현됩니다.
```yaml
# ... 배포 이전에 필요한 CI Workflow

  deploy: # 배포를 수행하는 단계
    needs: build
    runs-on: ubuntu-latest
    steps:
      # 0. Github Action Runner IP 획득
      - name: Get GitHub Actions Runner IP
        id: ip
        run: echo "ipv4=$(curl -s https://checkip.amazonaws.com)" >> $GITHUB_OUTPUT
      # 1. AWS 자격증명 설정
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}
      # 2. Github Action Runner IP 를 보안그룹에 임시허용
      - name: Add GitHub IP to Security Group
        run: |
          aws ec2 authorize-security-group-ingress \
            --group-id ${{ secrets.AWS_SG_ID }} \
            --protocol tcp --port 22 \
            --cidr ${{ steps.ip.outputs.ipv4 }}/32 \
            --tag-specifications 'ResourceType=security-group-rule,Tags=[{Key=Name,Value=GithubActions}]' || true
      # 3 ~ 5. 배포 (Artifacts 다운로드 및 전송, SSH 접속 등)
      # ...
      # 6. Github Action Runner IP 임시허용 해제
      - name: Revoke GitHub IP from Security Group
        if: always()
        run: |
          aws ec2 revoke-security-group-ingress \
            --group-id ${{ secrets.AWS_SG_ID }} \
            --protocol tcp --port 22 \
            --cidr ${{ steps.ip.outputs.ipv4 }}/32 || true

```

#### 0. Github Action Runner IP 획득
`checkip.amazonaws.com` 서비스를 호출하여 현재 실행 중인 Github Actions Runner의 Public IP를 확인합니다. 이 IP는 후속 단계에서 보안그룹 규칙을 추가할 때 사용됩니다.

#### 1. AWS 자격증명 설정
AWS CLI를 사용하여 보안그룹을 제어하기 위해 인증 과정을 수행합니다. Github Secrets에 저장된 Access Key와 Region 정보를 활용하여 권한을 획득합니다.

#### 2. 보안그룹 인바운드 규칙 추가 (임시 허용)
배포 대상 인스턴스가 속한 보안그룹에 0번 단계에서 획득한 IP에 한해 22번 포트(SSH) 접근을 허용하는 인바운드 규칙을 추가합니다.

#### 3 ~ 5. 배포 수행
SSH 접속을 통해 실제 배포 작업을 수행하는 단계입니다. (본 문서에서는 보안 전략에 집중하기 위해 상세 배포 스크립트는 생략했습니다.)

#### 6. 보안그룹 인바운드 규칙 삭제 (허용 해제)
배포가 완료되면(성공/실패 여부와 관계없이), 2번 단계에서 추가했던 인바운드 규칙을 즉시 삭제하여 보안 취약점을 제거합니다. `if: always()` 조건을 통해 스크립트 실패 시에도 반드시 실행되도록 보장합니다.

## 참고
SSM 적용에 따른 각 서비스 접근 방식의 경우 다음 문서를 참고 부탁드립니다.
https://github.com/100-hours-a-week/14-team-dojangkok-cloud/blob/main/wiki/guide/access-to-ec2-instance-via-ssm.md
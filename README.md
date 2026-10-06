# Gangwon-Infra

## 이 저장소가 하는 일

강원도 여행 동행 서비스 **Gangwon Companion** 운영 인프라를 Terraform으로 관리하는 저장소입니다.

웹 사용자는 여행지·숙박·음식점 정보를 조회하고, AI 기반 여행 코스를 추천받으며, 커뮤니티 기능을 이용할 수 있습니다. React 웹 프론트엔드는 S3와 CloudFront로 제공하고, API와 AI 서비스는 AWS ECS Fargate에서 운영합니다.

- 네트워크 격리 — Public·Private App·DB Subnet을 분리하고 RDS는 퍼블릭 접근 차단
- 컨테이너 오케스트레이션 — ECS Fargate에서 Spring Boot API와 FastAPI AI를 한 Task로 함께 실행
- 데이터 저장소 — RDS PostgreSQL(암호화, 7일 백업), 커뮤니티 이미지용 비공개 S3 Bucket
- 웹 배포 — React SPA는 비공개 S3와 CloudFront로 배포하고 API는 동일 도메인의 `/api/*` 경로로 제공
- 이미지 저장소 — ECR(BE·AI), 최신 10개 이미지만 유지하는 Lifecycle Policy
- 비밀 관리 — Secrets Manager, 평문 비밀번호 없음(RDS 비밀번호는 RDS가 직접 관리)
- CI/CD 인증 — 저장소별 GitHub Actions OIDC Role, 장기 Access Key 없음
- 모니터링 — CloudWatch Dashboard·Alarm으로 ALB·ECS·RDS·애플리케이션 에러 로그 감시

## 관련 저장소

| 저장소 | 역할 |
| --- | --- |
| [Gangwon-FE](https://github.com/Gangwon-Companion/Gangwon-FE) | React 기반 웹 프론트엔드 |
| [Gangwon-Companion](https://github.com/Gangwon-Companion/Gangwon-Companion) | Spring Boot API 서버 |
| [Gangwon-AI](https://github.com/Gangwon-Companion/Gangwon-AI) | FastAPI 기반 AI 여행 코스 추천 서버 |
| [Gangwon-Infra](https://github.com/Gangwon-Companion/Gangwon-Infra) | Terraform 기반 AWS 인프라 (현재 저장소) |

## 실행 경로

- 웹 주소: `terraform output cloudfront_domain_name` (운영 도메인 연결 전까지는 CloudFront 기본 도메인)
- API 주소: 웹 주소의 `/api` 경로
- 상태 확인: ALB 또는 CloudFront에 연결된 운영 health endpoint
- AWS 리전: `ap-northeast-2` (서울)
- CloudWatch 대시보드: `gangwon-companion-prod-operations`

API 루트 경로 `/`는 Spring Security 보호 대상이므로 `401 UNAUTHORIZED`가 정상입니다. 서버 상태는 `/actuator/health`로 확인합니다.

## 아키텍처

```text
Web Browser
       |
       v
CloudFront (현재는 *.cloudfront.net 기본 도메인)
              |-> Private S3 (React/Vite dist)
              `-> ALB (/api/*)
                    `-> ECS Fargate Service (Private App Subnet)
                          └─ Task (1 vCPU, 2 GiB)
                              ├─ BE / Spring Boot :8080
                              │   ├─ RDS PostgreSQL :5432
                              │   ├─ S3 Community Bucket
                              │   └─ AI http://localhost:8000
                              │
                              └─ AI / FastAPI :8000
                                  └─ External AI API (OpenAI, 선택적)

ECR ───────────────> BE·AI 컨테이너 이미지
Secrets Manager ───> DB 비밀번호·JWT·암호화 키·외부 API 키
CloudWatch <──────── BE·AI 로그·ALB/ECS/RDS 지표·알람
GitHub Actions ─────> OIDC 임시 자격 증명으로 ECR·ECS 배포, S3 동기화 및 CloudFront 무효화
```

### 웹 배포 구성

CloudFront가 React 정적 파일은 S3에서 제공하고 `/api/*` 요청은 ALB를 통해 BE·AI ECS Service로 전달합니다. BE와 AI는 같은 Task 안에서 `localhost`로 통신하며, FastAPI는 ALB나 인터넷에 노출하지 않습니다.

- 웹 호스팅용 S3 Bucket은 커뮤니티 이미지 Bucket과 분리합니다.
- CloudFront Origin Access Control(OAC)로 S3를 비공개로 유지하고, SPA 새로고침을 위해 403·404 응답을 `index.html`로 돌립니다.
- 운영 도메인이 아직 없어 CloudFront 기본 도메인(`*.cloudfront.net`)을 사용합니다. 도메인을 확보하면 ACM 인증서와 Route 53 레코드를 추가해 CloudFront에 연결합니다.
- 웹 배포는 GitHub Actions OIDC로 S3 동기화 후 CloudFront 캐시를 무효화합니다.
- ECS Task는 Private App Subnet에 배치합니다.
- 각 가용 영역에 NAT Gateway를 배치하고 S3, ECR, CloudWatch Logs, Secrets Manager VPC Endpoint를 구성합니다.

## 설계 원칙

- 외부 노출은 ALB로만 한정합니다. RDS는 프라이빗 서브넷에 있고 퍼블릭 IP가 없으며, FastAPI(8000)는 어떤 보안 그룹에서도 인바운드를 열지 않습니다.
- BE와 AI는 같은 Fargate Task 안에서 `localhost`로 통신합니다. ALB나 인터넷을 거치지 않습니다.
- 비밀은 Secrets Manager에만 둡니다. JWT·암호화 키·외부 API 키는 Task의 `secrets` 필드로 주입되고, RDS 비밀번호는 RDS가 직접 관리해 Git에 남지 않습니다.
- React 웹은 이 인프라의 S3·CloudFront에서 호스팅하며, 운영 API 주소는 빌드 환경 변수로 주입합니다.
- Task Definition과 desired count는 GitHub Actions와 운영자가 관리하며, Terraform은 `lifecycle.ignore_changes`로 되돌리지 않습니다.

## 관리 리소스

| 영역 | 관리 리소스 |
| --- | --- |
| Network | VPC, Public Subnet 2개, Private App Subnet 2개, DB Subnet 2개, NAT Gateway, VPC Endpoint, Internet Gateway |
| Security | ALB·ECS·RDS·VPC Endpoint Security Group과 최소 인바운드 규칙 |
| ALB | Application Load Balancer, BE Target Group, HTTP Listener, 선택적 HTTPS Listener |
| ECS | ECS Cluster, Fargate Task Definition, ECS Service, 배포 Circuit Breaker |
| ECR | BE·AI 이미지 저장소, 최신 10개 이미지 Lifecycle Policy |
| RDS | PostgreSQL, DB Subnet Group, 암호화 스토리지, 7일 백업 |
| S3 | React 웹 호스팅용 비공개 Bucket(CloudFront OAC 전용), 커뮤니티 이미지용 비공개 Bucket |
| CloudFront | Web Distribution(S3 Origin + ALB Origin `/api/*`), Origin Access Control |
| Secrets | RDS 관리형 비밀번호, 애플리케이션 Secrets Manager Secret |
| IAM | ECS 실행·Task Role, GitHub Actions 배포 Role |
| Monitoring | 서비스별 Log Group, CloudWatch Dashboard, Metric Filter, Alarm |
| CI/CD | GitHub OIDC Provider, BE·AI·FE·Infra 저장소별 Role |

## 주요 스펙

| 항목 | 값 |
| --- | --- |
| 리전 | `ap-northeast-2` (서울) |
| VPC CIDR | `10.0.0.0/16`, 가용 영역 2개(`ap-northeast-2a`, `ap-northeast-2b`) |
| ECS | Fargate, `awsvpc`, Task 1 vCPU/2 GiB (BE 512/1 GiB + AI 512/768 MiB) |
| RDS | PostgreSQL `db.t4g.micro`, gp3 20→100 GiB, Single-AZ, 비공개 접근 |
| Task 수 | 초기값 0, GitHub Actions·운영자가 조정 (Terraform 미간섭) |
| 로그 보존 | CloudWatch Logs 14일 |
| Terraform | `>= 1.10.0, < 2.0.0` |
| AWS Provider | `>= 6.0, < 7.0` |

## 저장소 구조

```text
.
├── alb.tf                    # ALB, Target Group, HTTP·HTTPS Listener
├── cloudfront.tf             # CloudFront Distribution, OAC, 관리형 Cache/Origin Request Policy
├── cloudwatch.tf             # Dashboard, Metric Filter, Alarm
├── ecr.tf                    # BE·AI ECR와 Lifecycle Policy
├── ecs.tf                    # ECS Cluster, Task Definition, Service
├── github_oidc.tf            # GitHub OIDC Provider와 BE·AI·FE·Infra 저장소별 Role
├── iam.tf                    # ECS Execution Role과 Task Role
├── network.tf                # VPC, Public·Private App·DB Subnet, NAT Gateway, VPC Endpoint
├── outputs.tf                # API·CloudFront·ECR·RDS·Secret·IAM 출력
├── providers.tf              # AWS Provider와 공통 태그
├── rds.tf                    # PostgreSQL RDS와 DB Subnet Group
├── s3.tf                     # 웹 호스팅용 Bucket, 커뮤니티 이미지 Bucket
├── security_groups.tf        # ALB·ECS·RDS·VPC Endpoint Security Group
├── variables.tf              # 입력 변수와 검증
├── versions.tf               # Terraform·Provider 버전 제약
├── terraform.tfvars.example  # 운영 변수 예시
├── docs/                     # 아키텍처·웹 배포·비용·중단 운영 가이드
└── README.md
```

모듈이나 환경 디렉터리로 분리하지 않고 리소스 종류별로 `.tf` 파일 하나씩 두는 단일 환경(prod) 구조입니다. Terraform state는 관리 PC의 로컬 state를 사용합니다. GitHub Actions에서 Terraform을 실행하지 않으며 `terraform.tfstate`와 `terraform.tfvars`는 Git에 커밋하지 않습니다.

## Terraform 실행 방법

### 사전 준비

- Terraform 1.10 이상 (AWS Provider `>= 6.0, < 7.0`)
- AWS CLI v2, 배포 대상 계정에 대한 자격 증명 (SSO 프로필 전제 없이 `aws configure` 또는 환경 변수로 설정한 자격 증명을 사용)
- Docker Desktop — 최초 부트스트랩 시 BE·AI 이미지를 ECR에 직접 push할 때만 필요하며, 이후 배포는 각 애플리케이션 저장소의 GitHub Actions가 담당합니다.

### 1. 자격 증명 확인

```powershell
aws sts get-caller-identity
```

출력된 계정 ID가 `terraform.tfvars`의 `aws_account_id`와 일치하는지 확인합니다.

### 2. 변수 파일 준비

`terraform.tfvars.example`을 참고해 Git에 커밋되지 않는 `terraform.tfvars`를 저장소 루트에 작성합니다. 이 저장소는 `environments/` 디렉터리를 두지 않고 루트의 `terraform.tfvars` 하나만 사용합니다.

### 3. 초기화 및 검증

```powershell
terraform init
terraform fmt -recursive
terraform validate
```

State는 S3 등 원격 backend 없이 로컬 파일(`terraform.tfstate`)로 관리합니다. Windows에서 로컬 Provider 실행이 제한되면 공식 Terraform Docker 이미지를 사용할 수 있습니다.

### 4. 계획과 적용

```powershell
terraform plan -out=prod.tfplan
terraform show prod.tfplan
terraform apply prod.tfplan
```

`-var-file` 옵션은 필요 없습니다. 루트의 `terraform.tfvars`를 Terraform이 자동으로 읽습니다. 계획 내용을 직접 확인한 뒤에만 적용합니다.

## Secrets Manager

애플리케이션 Secret에는 다음 JSON 키를 저장합니다.

```json
{
  "JWT_SECRET": "...",
  "PERSONAL_DATA_ENCRYPTION_KEY": "32-byte-encryption-key",
  "TOUR_API_KEY": "..."
}
```

`ai_response_llm_enabled = true`일 때만 `OPENAI_API_KEY`가 추가로 필요합니다. RDS 마스터 비밀번호는 RDS가 Secrets Manager에서 직접 관리합니다.

## 애플리케이션 CI/CD

Terraform은 인프라를 관리하고, 컨테이너 이미지 빌드와 배포는 각 애플리케이션 저장소의 GitHub Actions가 담당합니다.

| 변경 대상 | 배포 방법 |
| --- | --- |
| BE 코드 | BE 저장소 PR → `main` 병합 → prod 승인 → ECR·ECS 배포 |
| AI 코드 | AI 저장소 PR → `main` 병합 → prod 승인 → ECR·ECS 배포 |
| FE 코드 | React 빌드 → 웹 호스팅용 S3 동기화 → CloudFront 캐시 무효화 |
| 인프라 | Infra 저장소 PR 병합 후 관리 PC에서 `terraform apply` |

BE와 AI는 하나의 Task Definition을 공유합니다. 각 워크플로는 현재 Task Definition을 내려받아 자신의 컨테이너 이미지만 교체합니다. 이미지 덮어쓰기를 피하기 위해 BE와 AI 배포는 순차적으로 진행합니다. 웹 프론트엔드는 컨테이너가 아닌 S3·CloudFront로 배포합니다.

### Task Definition 갱신 정책

ECS Service에는 다음 설정이 있습니다.

```hcl
lifecycle {
  ignore_changes = [task_definition, desired_count]
}
```

CI/CD가 배포한 이미지 리비전을 Terraform이 되돌리지 않습니다. 같은 이유로 `terraform apply`만으로는 새 Task Definition이 서비스에 반영되지 않으며, 인프라 변경 후에는 아래처럼 강제 배포가 필요합니다.

```powershell
aws ecs update-service --cluster gangwon-companion-prod --service gangwon-companion-prod-app --force-new-deployment --region ap-northeast-2
```

### GitHub Actions OIDC

장기 AWS Access Key 대신 GitHub OIDC가 발급하는 짧은 수명의 자격 증명을 사용합니다. Trust Policy가 저장소와 Environment를 고정합니다. BE·AI·Infra 저장소뿐 아니라 프론트엔드(Gangwon-FE) 저장소에도 S3 동기화·CloudFront 무효화 권한만 가진 별도 Role이 있습니다.

```
repo:Gangwon-Companion/Gangwon-Companion:environment:prod
```

Role ARN은 apply 후 출력에서 확인해 각 저장소의 `prod` Environment 변수에 `AWS_ROLE_ARN`으로 등록합니다.

```powershell
terraform output github_deploy_role_arns
```

배포 가능 브랜치 제한이 필요합니다. Trust Policy의 `sub` 조건은 Environment만 구분하고 브랜치는 구분하지 않습니다. 각 저장소 `prod` Environment에서 배포 가능 브랜치를 `main`으로 제한해야 실질적인 방어가 됩니다. Required reviewer가 설정된 경우 팀원 승인 후 배포됩니다.

## 웹 배포 및 확인

React 웹은 GitHub Actions에서 빌드한 뒤 웹 호스팅용 S3에 업로드하고 CloudFront 캐시를 무효화합니다. 장기 AWS Access Key 대신 GitHub Actions OIDC Role을 사용합니다.

빌드 시 운영 API 주소를 환경 변수로 주입합니다.

```text
API_BASE_URL=https://<terraform output cloudfront_domain_name>/api
```

```powershell
cd ..\Gangwon-FE
npm install
npm run build
```

생성된 `dist` 디렉터리를 S3에 동기화한 후 CloudFront 캐시를 무효화합니다. 운영 URL에서 SPA 최초 진입, 새로고침, 로그인, API 호출, 이미지 업로드를 확인합니다.

현재는 운영 도메인이 없어 CloudFront 기본 도메인을 그대로 사용합니다(`viewer_certificate.cloudfront_default_certificate = true`). 도메인을 확보하면 ACM 인증서(CloudFront는 `us-east-1` 리전 인증서 필요)와 Route 53 레코드를 추가해 연결합니다. API를 별도 도메인으로 운영할 경우 백엔드 CORS 허용 목록에 운영 웹 도메인만 등록합니다.

## 운영

### 서비스 수 조정

```powershell
# 비용 절감을 위해 중지
aws ecs update-service --cluster gangwon-companion-prod --service gangwon-companion-prod-app --desired-count 0 --region ap-northeast-2

# 서비스 시작
aws ecs update-service --cluster gangwon-companion-prod --service gangwon-companion-prod-app --desired-count 1 --region ap-northeast-2
```

태스크를 0으로 내려도 ALB, NAT Gateway, RDS 비용은 계속 발생합니다. ElastiCache는 사용하지 않습니다.

### 강제 재배포

인프라 변경 후 새 Task Definition을 반영하는 방법은 [Task Definition 갱신 정책](#task-definition-갱신-정책)을 참고하세요.

### 로그

```powershell
aws logs tail /ecs/gangwon-companion-prod/be --since 10m --follow --region ap-northeast-2
aws logs tail /ecs/gangwon-companion-prod/ai --since 10m --follow --region ap-northeast-2
```

## 모니터링

CloudWatch 대시보드 `gangwon-companion-prod-operations`에서 다음 항목을 확인합니다.

- ALB 요청 수, Target 5xx, p95 응답 시간
- ECS CPU·메모리 사용률
- RDS CPU·연결 수·잔여 스토리지
- BE·AI ERROR 로그 발생 수

구성된 주요 알람:

- ALB Unhealthy Target, Target 5xx, p95 Latency
- ECS CPU·Memory 80% 초과
- RDS CPU 80% 초과, 잔여 스토리지 2 GiB 미만
- BE·AI ERROR 로그 5분 동안 5건 이상

알람 알림을 받으려면 `alarm_action_arns`에 SNS Topic ARN을 설정합니다.

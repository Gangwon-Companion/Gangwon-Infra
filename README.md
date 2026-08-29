# Gangwon-Infra

Gangwon Companion의 AWS 운영 인프라를 Terraform으로 관리한다.

## 시스템 아키텍처

```text
Expo Mobile/Web
      |
      | HTTPS (ACM 설정 전 초기 배포는 HTTP)
      v
Application Load Balancer
      |
      | :8080 /actuator/health
      v
ECS Fargate Service (public subnets, awsvpc)
  +-- BE / Spring Boot :8080
  |     +-- RDS PostgreSQL :5432 (private DB subnets)
  |     +-- S3 community/*
  |     +-- AI http://localhost:8000
  |
  +-- AI / FastAPI :8000
        +-- BE http://localhost:8080/internal/search/places
        +-- OpenAI-compatible API (optional)

CloudWatch Logs <-- BE, AI
Secrets Manager --> ECS task definition
ECR --> BE, AI container images
```

BE와 AI는 같은 Fargate task의 컨테이너이므로 network namespace를 공유하며 서로 `localhost`로 통신한다. ALB에는 BE만 등록되고 AI 포트는 외부에 공개하지 않는다. RDS는 private DB subnet에 있으며 ECS security group에서만 5432 접근을 허용한다.

FE 정적 호스팅은 이 Terraform 범위에 포함하지 않는다. Expo 앱 빌드 시 `EXPO_PUBLIC_API_URL`에 `terraform output -raw alb_url` 또는 연결한 API 도메인을 사용한다.

## 주요 리소스

- VPC, 2개 public subnet, 2개 private DB subnet
- Public ALB와 선택적 ACM HTTPS listener
- ECS Fargate service와 BE/AI 통합 task definition
- BE/AI ECR repository 및 10개 이미지 보존 정책
- PostgreSQL RDS, 암호화 스토리지, 7일 백업
- Community 파일용 private S3 bucket
- 애플리케이션/RDS Secrets Manager secret
- BE/AI CloudWatch log group
- ALB/ECS/RDS/application-error CloudWatch alarms and operations dashboard

## 배포 전 준비

`terraform.tfvars.example`을 참고해 추적되지 않는 `terraform.tfvars`를 작성한다. 초기 인프라 생성은 `ecs_desired_count = 0`으로 수행한다.

Terraform이 생성한 application secret에는 task 시작 전에 다음 JSON 키를 저장해야 한다.

```json
{
  "JWT_SECRET": "...",
  "PERSONAL_DATA_ENCRYPTION_KEY": "0123456789abcdef0123456789abcdef",
  "TOUR_API_KEY": "...",
  "OPENAI_API_KEY": "optional-when-llm-is-disabled"
}
```

`OPENAI_API_KEY`는 `ai_response_llm_enabled = true`일 때만 ECS에 주입된다. `PERSONAL_DATA_ENCRYPTION_KEY`는 애플리케이션이 요구하는 정확한 길이를 사용한다.

웹 FE를 공개할 때는 ACM 인증서 ARN과 실제 FE origin을 설정한다.

```hcl
acm_certificate_arn          = "arn:aws:acm:ap-northeast-2:ACCOUNT_ID:certificate/CERTIFICATE_ID"
cors_allowed_origin_patterns = "https://app.example.com"
```

## 배포 순서

1. `terraform init` 및 `terraform plan -out main.tfplan`
2. `terraform apply main.tfplan`로 기반 리소스 생성 (`ecs_desired_count = 0`)
3. 출력된 ECR 주소에 BE/AI 이미지를 build 및 push
4. 출력된 application secret에 필수 JSON 키 저장
5. 이미지 tag를 고정하고 `ecs_desired_count = 1`로 변경
6. 다시 plan/apply 후 ALB health와 CloudWatch log 확인
7. FE 빌드에 HTTPS API URL 주입

초기에는 `spring_jpa_ddl_auto = "update"`로 스키마를 생성한다. 정식 migration 도구를 도입한 뒤에는 `validate`로 전환한다.

## GitHub Actions OIDC

장기 AWS access key 대신 GitHub OIDC가 발급하는 단기 자격 증명을 사용한다. Terraform 적용 후 다음 출력의 ARN을 각 저장소 `prod` Environment의 `AWS_ROLE_ARN` 변수로 등록한다.

```powershell
terraform output github_deploy_role_arns
```

각 role의 trust policy는 해당 저장소의 `environment:prod` subject로 제한된다. GitHub 저장소 설정에서 `prod` Environment의 deployment branch를 `main`으로 제한해야 한다.

ECS service는 CI가 등록한 task definition revision과 운영자가 조절한 desired count를 Terraform이 되돌리지 않는다. 인프라 변경 후 task를 재기동하려면 다음 명령을 사용한다.

```powershell
aws ecs update-service --cluster gangwon-companion-prod --service gangwon-companion-prod-app --force-new-deployment --region ap-northeast-2
```

비용 절감을 위해 task를 중지하거나 다시 시작할 수 있다. ALB와 RDS 비용은 task를 내려도 계속 발생한다.

```powershell
aws ecs update-service --cluster gangwon-companion-prod --service gangwon-companion-prod-app --desired-count 0 --region ap-northeast-2
aws ecs update-service --cluster gangwon-companion-prod --service gangwon-companion-prod-app --desired-count 1 --region ap-northeast-2
```

서비스 로그는 컨테이너별 log group에서 확인한다.

```powershell
aws logs tail /ecs/gangwon-companion-prod/be --since 10m --follow --region ap-northeast-2
aws logs tail /ecs/gangwon-companion-prod/ai --since 10m --follow --region ap-northeast-2
```

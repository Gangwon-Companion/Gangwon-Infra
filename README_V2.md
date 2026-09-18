# Gangwon Companion v2 배포 환경

## 이 문서가 다루는 환경

이 문서는 2026-09-18에 구축한 `gangwon-v2` 운영 환경을 팀에 공유하기 위한
진입 문서입니다. 기존 루트 [README.md](README.md)와 Terraform 구성은 그대로
유지합니다.

`gangwon-v2`는 현재 AWS Console과 CloudShell에서 구축된 별도 운영 환경이며,
아직 이 저장소의 Terraform state로 관리되지 않습니다. 현재 서비스를 다시
배포하거나 삭제하지 않고, 팀 검토 후 기존 자원을 Terraform에 import할 예정입니다.

## 서비스 주소

- 프런트엔드: <https://main.d2pv5x1bch76t6.amplifyapp.com>
- API: <https://d3k1n6opsrtmw0.cloudfront.net>
- 상태 확인: <https://d3k1n6opsrtmw0.cloudfront.net/actuator/health>
- AWS 리전: `ap-northeast-2` (서울)

## 구성 요약

```text
Web user
  -> AWS Amplify Hosting (Gangwon-FE/main)
  -> CloudFront (gangwon-v2-api)
  -> Application Load Balancer (gangwon-v2-alb)
  -> ECS Fargate (gangwon-v2-service)
       |- backend / Spring Boot :8080
       `- ai / FastAPI :8000

backend
  |- RDS PostgreSQL
  |- S3 community image bucket
  `- Data EC2
       |- Kafka :29092
       |- Debezium Connect :8083 (localhost only)
       `- Elasticsearch :9200
```

BE와 AI는 같은 ECS Task Definition을 공유하며 `localhost`로 통신합니다.
검색 데이터는 RDS 변경 사항을 Debezium과 Kafka로 전달한 뒤 Elasticsearch에
점진적으로 반영합니다.

## 배포 방식

| 대상 | 운영 브랜치 | 배포 방식 |
| --- | --- | --- |
| FE | `main` | Amplify 자동 배포 |
| BE | `feature/aws-data-deploy` | GitHub Actions `Deploy BE to ECS` 수동 실행 |
| AI | `feature/aws-deploy` | GitHub Actions `Deploy AI to ECS` 수동 실행 |

기능 변경은 먼저 각 저장소의 `main`에 PR로 병합합니다. 이후 원격 `main`을
배포 브랜치에 병합하고 해당 브랜치에서 workflow를 실행합니다. BE와 AI가 같은
Task Definition을 갱신하므로 두 배포는 동시에 실행하지 않습니다.

## 상세 문서

- [v2 시스템 아키텍처](docs/V2_SYSTEM_ARCHITECTURE.md)
- [v2 리소스 목록](docs/V2_RESOURCE_INVENTORY.md)
- [v2 배포 및 운영 절차](docs/V2_DEPLOYMENT_RUNBOOK.md)
- [v2 Terraform 편입 계획](docs/V2_TERRAFORM_MIGRATION.md)

## 현재 관리 경계

- 기존 루트 Terraform: 기존 `gangwon-companion-prod` 환경
- 이 문서의 대상: 별도로 구축된 `gangwon-v2` 환경
- 현재 v2 관리 방식: AWS Console/CloudShell과 애플리케이션 GitHub Actions
- 향후 목표: 현재 자원을 삭제하지 않고 별도 v2 state에 import

기존 Terraform state와 실제 AWS 자원을 대조하기 전에는 루트에서
`terraform apply`를 실행하지 않습니다.

## 보안 주의사항

이 저장소는 공개 저장소입니다. 다음 정보는 문서나 Git에 기록하지 않습니다.

- 비밀번호, API key, access token
- Secret ARN 전체 값과 Secret 내용
- 데이터 EC2 사설 IP
- 민감한 환경 변수와 Terraform state


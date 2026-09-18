# gangwon-v2 리소스 목록

## 문서 기준

- 작성 기준일: 2026-09-18
- AWS 리전: `ap-northeast-2`
- 환경: `prod`
- 프로젝트 접두사: `gangwon-v2`

이 저장소는 공개 저장소입니다. 계정 ID, Secret ARN 전체 값, 사설 IP, 비밀번호,
API key와 access token은 기록하지 않습니다.

## 애플리케이션 진입점

| 영역 | 이름 또는 식별자 | 비고 |
| --- | --- | --- |
| Amplify App | `Gangwon-FE` | GitHub `Gangwon-FE/main` 자동 빌드 |
| Amplify App ID | `d2pv5x1bch76t6` | 프로덕션 브랜치 `main` |
| FE URL | `https://main.d2pv5x1bch76t6.amplifyapp.com` | 사용자 접속 주소 |
| CloudFront | `gangwon-v2-api` | Distribution ID `E1D6RD447KHOLK` |
| API URL | `https://d3k1n6opsrtmw0.cloudfront.net` | 캐시 비활성화, HTTPS 진입점 |
| ALB | `gangwon-v2-alb` | CloudFront origin |

## 컴퓨팅과 이미지

| 영역 | 이름 | 비고 |
| --- | --- | --- |
| ECS Cluster | `gangwon-v2-cluster` | Fargate |
| ECS Service | `gangwon-v2-service` | BE와 AI 공동 Task |
| Task family | `gangwon-v2-app` | 1 vCPU, 2 GiB |
| BE container | `backend` | Spring Boot, port 8080 |
| AI container | `ai` | FastAPI, port 8000 |
| BE ECR | `gangwon-v2-be` | SHA와 workflow Run ID 기반 image tag |
| AI ECR | `gangwon-v2-ai` | SHA와 workflow Run ID 기반 image tag |
| Log group | `/ecs/gangwon-v2` | stream prefix `backend`, `ai` |

## 데이터와 저장소

| 영역 | 이름 | 비고 |
| --- | --- | --- |
| RDS | `gangwon-v2-db` | PostgreSQL, database `gangwon` |
| Data EC2 security group | `gangwon-v2-data-sg` | Kafka, Debezium, Elasticsearch 실행 |
| Kafka | Data EC2 Docker Compose | backend에서 port 29092 접근 |
| Debezium Connect | Data EC2 Docker Compose | localhost port 8083 |
| Elasticsearch | Data EC2 Docker Compose | backend에서 port 9200 접근 |
| Search alias | `gangwon-places` | version index의 write alias |
| S3 | `gangwon-v2-community-<account-id>` | 커뮤니티 이미지 저장 |
| Secrets Manager | `gangwon-v2/application` | 실제 값과 전체 ARN은 기록하지 않음 |

데이터 EC2 instance ID와 사설 IP, RDS endpoint 등 변동 가능하거나 민감한 값은
AWS Console에서 태그와 접두사 `gangwon-v2`로 조회합니다.

## IAM과 배포

| 역할 | 이름 |
| --- | --- |
| ECS task role | `gangwon-v2-ecs-task-role` |
| ECS execution role | `gangwon-v2-ecs-execution-role` |
| BE GitHub deploy role | `gangwon-v2-github-be-deploy-role` |
| AI GitHub deploy role | `gangwon-v2-github-ai-deploy-role` |

GitHub Actions는 OIDC 임시 자격 증명으로 ECR과 ECS에 접근합니다. 장기 AWS Access
Key를 애플리케이션 저장소에 저장하지 않습니다.

## Terraform 관리 상태

위 리소스는 현재 기존 Terraform state의 관리 대상이 아닙니다. 이 목록은 운영
공유를 위한 inventory이며 Terraform 코드나 state를 대신하지 않습니다.


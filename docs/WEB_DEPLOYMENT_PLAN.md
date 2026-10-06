# React 웹 전환 및 배포 계획 (초안)

## 1. 문서 목적

Gangwon Companion의 프론트엔드를 모바일 앱 중심에서 일반 React 웹 애플리케이션으로 전환할 가능성에 대비한 인프라 초안이다.

아직 프론트엔드 코드와 배포 방식이 확정되지 않았으므로 이 문서는 실제 Terraform 변경 사항이 아니라 의사결정을 위한 계획이다. 우선 React와 Vite로 빌드되는 SPA(Single Page Application)를 가정한다.

## 2. 제안 아키텍처

```text
User
  -> Web Browser
  -> Route 53
  -> CloudFront
       |-> React Web S3
       `-> ALB
            -> Spring Boot ECS Service
                 |-> RDS PostgreSQL
                 |-> Community S3
                 `-> FastAPI ECS Service
                       |-> Spring Boot ECS Service
                       `-> External AI API
```

CloudFront에서 웹 정적 파일과 API를 하나의 도메인으로 제공하는 방식을 우선 검토한다. 예를 들어 `https://example.com`은 React 웹을 제공하고 `https://example.com/api/*`는 ALB로 전달한다. 백엔드의 실제 API 경로 구조와 충돌한다면 `app.example.com`과 `api.example.com`처럼 도메인을 분리할 수 있다.

Spring Boot와 FastAPI는 하나의 Task Definition을 공유하지 않는다. 각각 별도의 ECS Service와 Task Definition으로 구성하고 두 가용 영역에 최소 1개씩, 서비스별 총 2개 이상의 Task를 실행한다. 외부 요청은 ALB를 통해 Spring Boot에만 전달하며 FastAPI는 외부에 공개하지 않는다.

각 Private App Subnet에는 서로 독립된 Task 두 개가 배치된다.

```text
Private App Subnet A             Private App Subnet B
|- Spring Boot Task A            |- Spring Boot Task B
`- FastAPI Task A                `- FastAPI Task B
```

Spring Boot Task 안에 FastAPI Task가 포함되거나 FastAPI Task 안에 Spring Boot Task가 포함되는 구조가 아니다. Spring Boot ECS Service는 Spring Boot Task A와 B만 관리하고, FastAPI ECS Service는 FastAPI Task A와 B만 관리한다. 아키텍처 그림에서는 두 AZ를 가로지르는 큰 ECS Service 박스를 만들지 않고 각 Task에 소속 서비스 이름을 표시한다.

두 서비스 간 통신에는 ECS Service Connect를 사용한다.

```text
Spring Boot -> http://ai:8000
FastAPI     -> http://backend:8080
```

이 구성은 각 서비스의 배포, 확장, 장애 복구 및 CPU·메모리 설정을 독립적으로 관리할 수 있게 한다.

### 사용자 요청 흐름

```text
웹 화면:
User -> Web Browser -> Route 53 -> CloudFront -> React Web S3

API 요청:
User -> Web Browser -> Route 53 -> CloudFront -> ALB
     -> Spring Boot ECS Service -> RDS PostgreSQL

AI 요청:
User -> Web Browser -> Route 53 -> CloudFront -> ALB
     -> Spring Boot ECS Service -> FastAPI ECS Service
     -> Spring Boot ECS Service -> ALB -> CloudFront -> Web Browser -> User
```

FastAPI가 장소 조회를 위해 Spring Boot 내부 API를 호출하는 경우 Service Connect의 내부 서비스 주소를 사용한다. 사용자에게 반환되는 최종 응답은 Spring Boot가 담당한다.

## 3. 새로 필요한 AWS 리소스

- React 빌드 결과물을 저장할 비공개 S3 버킷
- S3에 안전하게 접근하기 위한 CloudFront Origin Access Control(OAC)
- CloudFront Distribution
- SPA 라우팅을 위한 403/404 응답 처리 또는 CloudFront Function
- 사용자 도메인과 HTTPS 적용을 위한 Route 53 레코드 및 ACM 인증서
- 프론트엔드 GitHub Actions용 OIDC 배포 권한
- 배포 후 CloudFront 캐시 무효화 권한

기존 커뮤니티 이미지 저장용 S3 버킷과 웹 호스팅용 S3 버킷은 목적과 권한이 다르므로 분리한다.

## 4. 프론트엔드 배포 흐름

1. 프론트엔드 저장소의 `main` 브랜치에 변경 사항을 병합한다.
2. GitHub Actions가 의존성을 설치하고 테스트한다.
3. 운영 API 주소를 환경 변수로 주입해 React 앱을 빌드한다.
4. 생성된 `dist` 디렉터리를 웹 호스팅용 S3 버킷에 동기화한다.
5. 변경된 정적 파일이 즉시 제공되도록 CloudFront 캐시를 무효화한다.
6. 운영 URL에서 SPA 진입, 새로고침, API 호출을 확인한다.

장기 AWS Access Key 대신 현재와 동일하게 GitHub Actions OIDC를 사용한다.

## 5. API, HTTPS, CORS

- 운영 웹과 API는 모두 HTTPS로 제공한다.
- CloudFront에서 `/api/*`를 ALB로 전달하면 브라우저 기준 동일 출처 구성이 가능해 CORS 관리가 단순해진다.
- 웹과 API 도메인을 분리하면 백엔드 CORS 허용 목록에는 정확한 운영 웹 도메인만 등록한다.
- 쿠키 인증을 사용한다면 `Secure`, `HttpOnly`, `SameSite` 정책과 CloudFront 전달 정책을 함께 검토한다.
- JWT를 브라우저 저장소에 보관하는 방식은 XSS 영향을 고려해 프론트엔드와 백엔드가 함께 결정한다.

## 6. NAT Gateway 및 네트워크 구성

정적 React 웹 배포 자체에는 NAT Gateway가 필요하지 않지만, 운영 환경의 네트워크 격리와 가용성을 우선해 ECS에는 NAT Gateway를 사용하는 구성을 목표로 한다.

- S3와 CloudFront는 VPC 외부의 관리형 서비스이므로 웹 배포를 위해 NAT Gateway가 필요하지 않다.
- 현재 ECS Task는 Public Subnet에서 Public IP를 사용하지만, 목표 구성에서는 Spring Boot와 FastAPI Task를 별도의 Private App Subnet 배치로 이전하고 Public IP 할당을 제거한다.
- Public Subnet에는 ALB와 NAT Gateway만 배치한다.
- ECS 인바운드는 ALB Security Group에서 오는 애플리케이션 포트만 허용한다.
- RDS는 계속 Private DB Subnet에 두고 ECS에서만 접근하도록 유지한다.

가용 영역 장애에 대비해 `ap-northeast-2a`, `ap-northeast-2b`의 Public Subnet에 NAT Gateway를 각각 하나씩 둔다. 각 Private App Subnet의 기본 경로는 같은 가용 영역의 NAT Gateway를 향하게 하여 교차 AZ 의존성과 단일 장애점을 줄인다.

ECS가 사용하는 AWS 서비스 트래픽은 가능한 경우 VPC Endpoint로 분리한다.

- S3 Gateway Endpoint
- ECR API Interface Endpoint
- ECR Docker Interface Endpoint
- CloudWatch Logs Interface Endpoint
- Secrets Manager Interface Endpoint

OpenAI, 관광 API, 패키지 저장소 등 외부 인터넷 서비스로 나가는 요청은 NAT Gateway를 통과한다. NAT Gateway는 인바운드 연결을 허용하는 장치가 아니므로 외부에서 ECS로 직접 접속하는 경로는 생기지 않는다.

목표 네트워크 배치는 다음과 같다.

| Subnet 종류 | AZ별 배치 항목 | 외부 연결 |
| --- | --- | --- |
| Public | ALB, NAT Gateway | Internet Gateway |
| Private App | Spring Boot Task, FastAPI Task, VPC Endpoint ENI | NAT Gateway를 통한 아웃바운드 |
| Private DB | RDS PostgreSQL | 인터넷 경로 없음 |

## 7. ECS 서비스 분리

| 구분 | Spring Boot ECS Service | FastAPI ECS Service |
| --- | --- | --- |
| 역할 | 공개 API, 인증, 비즈니스 로직, DB 접근 | AI 추천 및 응답 처리 |
| 외부 진입점 | ALB | 없음 |
| 내부 통신 | Service Connect를 통해 FastAPI 호출 | Service Connect를 통해 Spring Boot 호출 |
| 기본 Task 수 | 2개, AZ별 1개 이상 | 2개, AZ별 1개 이상 |
| 배포 | 독립 Task Definition 및 ECS Service | 독립 Task Definition 및 ECS Service |
| 확장 | API 부하 기준 독립 확장 | AI 부하 기준 독립 확장 |
| 장애 영향 | FastAPI 장애 시 일반 API 유지 가능 | Spring Boot Task와 독립적으로 교체 가능 |

ALB Target Group에는 Spring Boot ECS Service만 등록한다. FastAPI Security Group은 Spring Boot Service의 요청만 허용한다. RDS Security Group은 Spring Boot Service의 PostgreSQL 연결만 허용한다.

아키텍처 다이어그램에서는 다음 포함 관계를 지킨다.

- Private App Subnet A: Spring Boot Task A, FastAPI Task A
- Private App Subnet B: Spring Boot Task B, FastAPI Task B
- Spring Boot ECS Service: Spring Boot Task A와 B를 관리
- FastAPI ECS Service: FastAPI Task A와 B를 관리
- Task 또는 Subnet 박스가 Availability Zone 경계를 넘어가면 안 된다.

## 8. 단계별 전환안

### 1단계: 프론트엔드 방식 확정

- React + Vite SPA 여부 확인
- 프론트엔드 저장소와 빌드 명령 확인
- 사용할 도메인과 API 경로 결정
- 브라우저 인증 및 파일 업로드 방식 확인

### 2단계: 정적 웹 배포 추가

- 웹 전용 S3와 CloudFront 구성
- ACM 인증서와 DNS 연결
- GitHub Actions OIDC 권한 및 배포 워크플로 구성
- 백엔드 CORS와 API 주소 조정

### 3단계: 운영 안정화

- CloudFront 접근 로그와 오류율 관찰
- 보안 헤더(Content-Security-Policy 등) 적용
- S3 객체 캐시 정책 최적화
- 배포 롤백 절차 마련

### 4단계: 네트워크 강화

- ECS를 Private Subnet으로 이전
- 기존 공동 Task Definition을 Spring Boot와 FastAPI용으로 분리
- Spring Boot와 FastAPI ECS Service를 각각 생성
- ECS Service Connect로 내부 서비스 통신 구성
- 가용 영역별 NAT Gateway 구성
- S3, ECR, CloudWatch Logs, Secrets Manager VPC Endpoint 구성
- ECS Public IP 제거 및 라우팅·Security Group 검증

## 9. 현재 결정 사항

- 기존 ECS, ALB, RDS, ECR, Secrets Manager, 모니터링 구성은 우선 유지한다.
- React 웹은 S3와 CloudFront를 이용한 정적 배포를 우선안으로 한다.
- 웹 호스팅용 버킷은 기존 커뮤니티 이미지 버킷과 분리한다.
- Spring Boot와 FastAPI는 별도의 ECS Service와 Task Definition으로 분리한다.
- 서비스별 Task를 두 가용 영역에 분산한다.
- ALB에는 Spring Boot만 연결하고 FastAPI는 내부 서비스로 운영한다.
- 서비스 간 통신에는 ECS Service Connect를 사용한다.
- 운영 목표 구성에는 가용 영역별 NAT Gateway와 주요 AWS 서비스용 VPC Endpoint를 추가한다.
- 프론트엔드 기술과 도메인이 확정된 뒤 Terraform을 변경한다.

## 10. 현재 구성과 목표 구성의 차이

이 문서는 목표 아키텍처를 설명한다. 현재 Terraform은 Spring Boot와 FastAPI를 동일한 Fargate Task에서 실행하며 Public Subnet과 Public IP를 사용한다. 따라서 이 문서의 ECS Service 분리, Private App Subnet, NAT Gateway, VPC Endpoint, Multi-AZ Task 배치는 아직 실제 인프라에 반영되지 않았다.

## 11. 확정 전에 필요한 정보

- 프론트엔드가 React + Vite SPA인지 여부
- 프론트엔드 GitHub 저장소 이름
- 운영 도메인 보유 여부와 Route 53 사용 여부
- `/api` 단일 도메인 구성 또는 별도 API 서브도메인 선택
- 로그인 인증 방식과 소셜 로그인 리디렉션 주소
- OpenAI 및 관광 API 등 ECS에서 호출할 외부 서비스 목록

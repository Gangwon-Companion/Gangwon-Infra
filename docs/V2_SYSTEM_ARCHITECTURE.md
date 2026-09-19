# Gangwon Companion v2 시스템 아키텍처

## 1. 아키텍처 요약

`gangwon-v2`는 웹 프런트엔드를 Amplify에, Spring Boot BE와 FastAPI AI를
ECS Fargate에 배포합니다. 외부 API 진입점은 CloudFront이며 ALB를 origin으로
사용합니다. PostgreSQL은 RDS에서, 검색 파이프라인은 별도의 데이터 EC2에서
실행합니다.

이 환경은 현재 기존 Terraform state에 포함되지 않습니다.

## 2. 전체 시스템 구조

```text
Browser
  |
  | HTTPS
  v
AWS Amplify Hosting
  |  Gangwon-FE / main
  |
  | API request
  v
CloudFront
  |  cache disabled
  v
Application Load Balancer
  |
  | :8080
  v
ECS Fargate Service
  `- Task: gangwon-v2-app
      |- backend / Spring Boot :8080
      |   |- RDS PostgreSQL :5432
      |   |- S3 community image bucket
      |   |- AI http://localhost:8000
      |   `- Data EC2
      |       |- Kafka :29092
      |       `- Elasticsearch :9200
      `- ai / FastAPI :8000
          `- BE http://localhost:8080/internal/search/places

RDS PostgreSQL
  -> Debezium Connect :8083
  -> Kafka
  -> backend search indexer
  -> Elasticsearch alias: gangwon-places
```

## 3. 애플리케이션 요청 흐름

1. 사용자가 Amplify의 FE URL에 접속합니다.
2. FE는 `EXPO_PUBLIC_API_URL`에 설정된 CloudFront API 주소를 호출합니다.
3. CloudFront는 요청의 `Host`를 제외한 viewer 정보를 ALB origin으로 전달합니다.
4. ALB는 ECS의 Spring Boot 컨테이너 8080 포트로 요청을 전달합니다.
5. BE가 AI 기능을 호출할 때 같은 Task의 `localhost:8000`을 사용합니다.

## 4. 검색 데이터 흐름

1. 스케줄러 또는 관리자 요청으로 Tour API 데이터를 RDS에 동기화합니다.
2. Debezium이 RDS 변경 사항을 Kafka에 발행합니다.
3. BE search indexer가 Kafka 이벤트를 소비합니다.
4. 변경 내용을 Elasticsearch의 `gangwon-places` alias에 반영합니다.
5. AI는 BE 내부 검색 API로 장소 후보를 조회합니다.

전체 재색인은 최초 구성, 매핑 변경, 장애 복구에만 사용합니다. 일반적인 데이터
동기화는 CDC 파이프라인을 통해 점진적으로 반영합니다.

## 5. 네트워크와 보안 경계

- 외부에는 Amplify, CloudFront와 ALB만 공개합니다.
- AI 8000 포트는 외부에 공개하지 않습니다.
- Kafka 29092와 Elasticsearch 9200은 backend security group에서만 접근합니다.
- Debezium Connect 8083은 데이터 EC2의 localhost에만 바인딩합니다.
- Elasticsearch security가 비활성화돼 있으므로 9200을 인터넷에 열지 않습니다.
- 비밀값은 Secrets Manager에서 ECS Task로 주입합니다.

## 6. CI/CD 흐름

```text
feature branch
  -> PR to main
  -> merge origin/main into deployment branch
  -> Run workflow
  -> GitHub OIDC temporary credentials
  -> Docker build
  -> ECR push with immutable tag
  -> render current ECS Task Definition
  -> replace one container image
  -> ECS service deployment and stability check
```

BE와 AI는 하나의 Task Definition을 공유합니다. 각각의 workflow는 현재 Task
Definition을 내려받고 자신의 컨테이너 이미지만 교체합니다. 두 workflow는
순차적으로 실행합니다.

## 7. 기존 환경과의 관계

기존 루트 Terraform은 `gangwon-companion-prod` 이름을 사용하는 이전 운영 환경을
기준으로 작성됐습니다. v2는 `gangwon-v2` 접두사, CloudFront/Amplify 웹 진입점,
데이터 EC2 기반 검색 파이프라인을 추가로 사용합니다. 기존 Terraform을 v2에 바로
적용하지 않습니다.


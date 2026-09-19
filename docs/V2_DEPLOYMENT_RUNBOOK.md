# gangwon-v2 배포 및 운영 절차

## 1. 배포 전 확인

- 기능 브랜치를 각 애플리케이션 저장소 `main`에 PR로 병합합니다.
- 원격 `main`의 최신 커밋을 배포 브랜치에 병합합니다.
- BE와 AI는 같은 ECS Task Definition을 갱신하므로 동시에 배포하지 않습니다.
- 한쪽 배포가 성공하고 ECS service가 안정화된 후 다른 쪽을 배포합니다.

## 2. 프런트엔드

- 저장소: `Gangwon-Companion/Gangwon-FE`
- 운영 브랜치: `main`
- 배포 방식: `main` push/merge 시 AWS Amplify 자동 배포
- 빌드 명령: `npm run build`
- 빌드 출력: `dist`
- 환경 변수: `EXPO_PUBLIC_API_URL=https://d3k1n6opsrtmw0.cloudfront.net`

## 3. 백엔드

- 저장소: `Gangwon-Companion/Gangwon-Companion`
- 배포 브랜치: `feature/aws-data-deploy`
- workflow: `Deploy BE to ECS`

```bash
git fetch origin
git switch feature/aws-data-deploy
git merge origin/main
git push origin feature/aws-data-deploy
```

GitHub의 **Actions > Deploy BE to ECS > Run workflow**에서
`feature/aws-data-deploy`를 선택합니다. 성공하면 새 BE 이미지를 ECR에 push하고
ECS Task Definition의 `backend` 이미지만 교체합니다.

## 4. AI

- 저장소: `Gangwon-Companion/Gangwon-AI`
- 배포 브랜치: `feature/aws-deploy`
- workflow: `Deploy AI to ECS`

```bash
git fetch origin
git switch feature/aws-deploy
git merge origin/main
git push origin feature/aws-deploy
```

GitHub의 **Actions > Deploy AI to ECS > Run workflow**에서 `feature/aws-deploy`를
선택합니다. 성공하면 새 AI 이미지를 ECR에 push하고 ECS Task Definition의 `ai`
이미지만 교체합니다.

배포 브랜치를 `main`에 다시 병합하지 않습니다. 기능 변경은 먼저 `main`에
병합하고, 반대 방향으로 `main`을 배포 브랜치에 반영합니다.

## 5. 배포 확인

```bash
curl -i https://d3k1n6opsrtmw0.cloudfront.net/actuator/health
```

정상 기준:

- HTTP status `200`
- response body의 `status`가 `UP`
- ECS service의 running task 수가 desired task 수와 일치
- CloudWatch `/ecs/gangwon-v2` 로그에 반복적인 시작 실패가 없음

AI 여행 생성은 비동기 job이므로 `PENDING`, `RUNNING`, `COMPLETED` 순서까지
확인합니다. 검색 장애가 발생하면 API 오류뿐 아니라 Kafka, Elasticsearch와 검색
alias 상태도 함께 확인합니다.

## 6. 데이터 서비스 확인

데이터 EC2에 접속한 상태에서 실행합니다.

```bash
curl -fsS http://localhost:9200/_cluster/health
curl -fsS http://localhost:9200/_cat/aliases/gangwon-places?v
curl -fsS http://localhost:8083/connectors
sudo docker compose ps
```

`gangwon-places`가 version index를 가리키고 `is_write_index`가 `true`인지
확인합니다. Elasticsearch가 비어 있거나 mapping이 변경된 경우에만 전체 재색인을
검토합니다.

## 7. 현재 운영 주의사항

- 장소 동기화와 Elasticsearch 반영 사이에는 처리 시간이 있을 수 있습니다.
- 상세 데이터 동기화의 회당 처리 개수 제한을 확인해야 합니다.
- `gangwon-places`라는 이름으로 concrete index를 직접 생성하지 않습니다.
- 전체 재색인 전에 현재 alias와 version index를 확인합니다.
- 수동 동기화 및 재색인 API의 운영 권한 제한을 보강해야 합니다.


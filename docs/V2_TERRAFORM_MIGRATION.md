# gangwon-v2 Terraform 편입 계획

## 1. 목표

현재 정상 운영 중인 `gangwon-v2` AWS 자원을 삭제하거나 다시 만들지 않고,
Terraform 코드와 state에 안전하게 편입합니다.

## 2. 현재 상태

- 기존 저장소 루트 Terraform은 `gangwon-companion-prod` 환경을 관리합니다.
- 기존 state는 관리 PC의 로컬 state를 사용합니다.
- `gangwon-v2`는 AWS Console과 CloudShell에서 별도로 구축했습니다.
- 따라서 현재 루트에서 바로 `terraform apply`하면 안 됩니다.

## 3. 제안 구조

팀 합의 후 기존 단일 환경 구조를 다음처럼 분리하는 방안을 검토합니다.

```text
environments/
  legacy-prod/
  v2-prod/
modules/
  network/
  compute/
  data/
  edge/
```

처음부터 모듈화를 강제하지 않고 `environments/v2-prod`에 리소스 종류별 `.tf`
파일을 두는 방식으로 시작해도 됩니다.

## 4. 편입 순서

1. 기존 로컬 Terraform state의 소유자와 최신 파일을 확인합니다.
2. AWS에서 `gangwon-v2` 태그와 이름을 기준으로 전체 자원을 inventory합니다.
3. 별도의 `v2-prod` backend와 state를 준비합니다.
4. 실제 설정과 동일한 Terraform resource block을 작성합니다.
5. `import` block 또는 `terraform import`로 기존 AWS 자원을 state에 연결합니다.
6. `terraform plan`에서 예상하지 않은 생성, 교체, 삭제가 없어질 때까지 조정합니다.
7. 팀 리뷰 후 작은 변경부터 Terraform으로 검증합니다.

## 5. state 관리 권장안

팀원이 함께 관리할 수 있도록 로컬 state 대신 버전 관리와 암호화를 적용한 S3
remote backend 사용을 권장합니다. state에는 민감한 값이 포함될 수 있으므로 Git에
커밋하지 않습니다.

```text
terraform.tfstate
terraform.tfstate.*
terraform.tfvars
*.tfplan
```

## 6. 금지 사항

- import 전에 기존 루트에서 `terraform apply`하지 않습니다.
- plan을 검토하지 않고 apply하지 않습니다.
- 현재 운영 자원을 삭제한 뒤 Terraform으로 다시 만들지 않습니다.
- 비밀번호, API key, access token, Secret 값 또는 사설 IP를 Git에 기록하지 않습니다.
- 기존 state를 확인하지 않고 새 state로 같은 리소스를 관리하지 않습니다.

## 7. 완료 기준

- 모든 `gangwon-v2` 핵심 자원이 Terraform state에 연결됨
- `terraform plan`에 의도하지 않은 변경이 없음
- 팀원이 동일한 remote state로 plan을 재현할 수 있음
- 문서가 실제 배포 및 장애 대응 절차와 일치함
- 인프라 변경은 Infra PR, 애플리케이션 배포는 각 앱 Actions로 책임이 분리됨


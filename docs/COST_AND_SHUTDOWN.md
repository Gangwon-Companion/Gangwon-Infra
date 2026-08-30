# AWS 비용 및 중단 운영 가이드

## 1. 계속 과금되는 리소스

| 리소스 | 과금 원인 | 중단 방법 | 데이터 영향 |
| --- | --- | --- | --- |
| ECS Fargate | 실행 중인 Task의 vCPU·메모리 | desired count를 0으로 변경 | 없음 |
| RDS PostgreSQL | DB 인스턴스·스토리지·백업 | 단기 Stop, 장기 Snapshot 후 삭제 | 삭제 시 주의 |
| Application Load Balancer | ALB 실행 시간·LCU | 중지 기능 없음, 삭제 필요 | API 주소 소멸 |
| Public IPv4 | ALB와 실행 Task의 Public IP | Task 중지, ALB 삭제 | 없음 |
| CloudWatch | 로그 저장·알람·대시보드 | 로그·알람 삭제 | 관측 데이터 손실 |
| Secrets Manager | Secret 개수와 API 호출 | Secret 삭제 | 앱 재기동 불가 |
| ECR | 컨테이너 이미지 저장 용량 | 오래된 이미지 삭제 | 해당 버전 재배포 불가 |
| S3 | 객체 저장·요청·전송량 | 객체 또는 Bucket 삭제 | 이미지 손실 |

ECS Cluster, IAM Role, Security Group, VPC, Subnet, Route Table, Internet Gateway는 존재만으로는 일반적으로 직접 실행 비용이 발생하지 않습니다.

현재 구성에는 NAT Gateway와 ElastiCache Redis가 없습니다.

## 2. 단기 중단

### Fargate 중지

```powershell
aws ecs update-service `
  --cluster gangwon-companion-prod `
  --service gangwon-companion-prod-app `
  --desired-count 0 `
  --region ap-northeast-2
```

중지 확인:

```powershell
aws ecs describe-services `
  --cluster gangwon-companion-prod `
  --services gangwon-companion-prod-app `
  --region ap-northeast-2 `
  --query "services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}"
```

Fargate Task가 0이 되면 BE·AI API는 중단됩니다. ALB와 RDS는 계속 과금됩니다.

### RDS 일시 중지

```powershell
aws rds stop-db-instance `
  --db-instance-identifier gangwon-companion-prod-postgres `
  --region ap-northeast-2
```

RDS를 중지해도 스토리지와 백업 비용은 남습니다. RDS 일시 중지는 영구 중단 수단이 아니며 AWS 정책에 따라 자동으로 다시 시작될 수 있으므로 상태를 주기적으로 확인합니다.

## 3. 서비스 재시작

RDS를 먼저 시작하고 사용 가능 상태가 된 후 Fargate를 시작합니다.

```powershell
aws rds start-db-instance `
  --db-instance-identifier gangwon-companion-prod-postgres `
  --region ap-northeast-2

aws rds wait db-instance-available `
  --db-instance-identifier gangwon-companion-prod-postgres `
  --region ap-northeast-2

aws ecs update-service `
  --cluster gangwon-companion-prod `
  --service gangwon-companion-prod-app `
  --desired-count 1 `
  --force-new-deployment `
  --region ap-northeast-2
```

최종 확인:

```powershell
Invoke-RestMethod http://gangwon-companion-prod-alb-1949114334.ap-northeast-2.elb.amazonaws.com/actuator/health
```

## 4. 중단 수준별 권장안

### 몇 시간 또는 며칠

- Fargate를 0으로 내립니다.
- RDS는 재시작 시간을 고려해 유지하거나 잠시 중지합니다.
- ALB, S3, ECR, Secrets Manager는 유지합니다.

### 몇 주

- Fargate를 0으로 내립니다.
- RDS를 일시 중지하되 자동 재시작 여부를 확인합니다.
- ALB 비용이 부담되면 Terraform에 일시 비활성화 옵션을 추가한 후 삭제합니다.
- ECR 이미지는 최신 정상 버전만 남깁니다.

### 장기 철거

1. RDS 수동 스냅샷 생성
2. S3 데이터 백업
3. Secrets Manager Secret 백업 또는 복구 계획 확인
4. Terraform plan으로 삭제 범위 검토
5. 삭제 방지와 최종 스냅샷 정책 수정
6. 승인 후 Terraform destroy

## 5. 중요 경고

현재 RDS Terraform 설정:

```hcl
deletion_protection = false
skip_final_snapshot = true
```

이 상태에서 `terraform destroy`를 실행하면 최종 스냅샷 없이 RDS가 삭제될 수 있습니다. 장기 철거 전에 반드시 다음 방향으로 코드를 변경하고 plan을 검토합니다.

```hcl
deletion_protection       = true
skip_final_snapshot       = false
final_snapshot_identifier = "gangwon-companion-prod-final-YYYYMMDD"
```

ALB는 Stop 기능이 없습니다. 콘솔에서 개별 리소스를 임의 삭제하면 Terraform state와 실제 AWS가 어긋날 수 있으므로, 인프라 코드에 옵션을 추가하거나 검토된 Terraform 작업으로 삭제합니다.

## 6. 비용 확인

AWS Billing and Cost Management에서 확인합니다.

1. Bills → Charges by service
2. Cost Explorer → Current month → Daily → Group by Service
3. Cost allocation tags에서 `Project`, `Environment` 활성화
4. Cost Explorer에서 다음 필터 적용

```text
Project = gangwon-companion
Environment = prod
```

주요 서비스 항목:

- Amazon RDS
- Elastic Load Balancing
- Amazon ECS / AWS Fargate
- Amazon VPC / Public IPv4
- Amazon CloudWatch
- AWS Secrets Manager
- Amazon ECR
- Amazon S3

Cost Explorer 데이터와 Cost Allocation Tag는 바로 보이지 않고 반영까지 시간이 걸릴 수 있습니다.

## 7. 비용 알림 권장

AWS Budgets에서 월 비용 예산을 생성하고 다음 임계값을 권장합니다.

- 실제 비용 50%
- 실제 비용 80%
- 실제 비용 100%
- 예측 비용 100%

비용 이상 탐지를 추가하면 예상하지 못한 Task 재시작, 트래픽 급증, 로그 증가를 더 빨리 확인할 수 있습니다.


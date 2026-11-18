# AI Image Recognition — Infrastructure

Đồ án DevOps đề tài 10. Repo này dành cho cấu hình hạ tầng và vận hành.

## Backend trên Kubernetes — Issue #15

Manifest API/Worker, Job tạo schema, cấu hình runtime, shared upload PVC, requests/limits
và probes nằm trong `kubernetes/backend/`. Có overlay k3s local-path cùng node hoặc
RWX nhiều node; PostgreSQL/Redis staging và Prometheus mẫu được tách riêng.

Hướng dẫn biến môi trường, Secret/GHCR, thứ tự triển khai, nghiệm thu và rollback:
[Runbook Backend Kubernetes](docs/BACKEND-KUBERNETES.md).

Liên quan: [Issue #15 của repo ứng dụng](https://github.com/01PhamTien/ai-recognition-app/issues/15).
Source API đã có health/readiness/metrics và JSON stdout, không cần làm lại API.
Chỉ dùng tag image đã publish; tạo Secret theo runbook và chạy nghiệm thu trên cluster
trước khi đóng Issue. Không đưa secret thật hoặc kubeconfig vào Git.

Jenkins runtime hiện có trong `jenkins/`. Terraform/Ansible và monitoring tổng thể
do các phần việc hạ tầng khác của nhóm quản lý.

Yêu cầu chính: Terraform tạo hạ tầng, Ansible cấu hình máy, k3s chạy ứng dụng, staging/production tách namespace, Prometheus/Grafana, Alertmanager, log tập trung và bảo mật.

Không commit khóa SSH, mật khẩu, Ansible Vault password, Terraform state hoặc bất kỳ secret nào.

Mọi thay đổi qua Pull Request với ít nhất một người review. Commit theo Conventional Commits.

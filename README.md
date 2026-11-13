# AI Image Recognition — Infrastructure

Đồ án DevOps đề tài 10. Repo này dành cho cấu hình hạ tầng và vận hành.

> Trạng thái: khởi tạo repo. Chưa có hạ tầng được tạo.

Dự kiến bổ sung: `terraform/`, `ansible/`, `kubernetes/`, `monitoring/`, `security/`, `docs/`.

Yêu cầu chính: Terraform tạo hạ tầng, Ansible cấu hình máy, k3s chạy ứng dụng, staging/production tách namespace, Prometheus/Grafana, Alertmanager, log tập trung và bảo mật.

Không commit khóa SSH, mật khẩu, Ansible Vault password, Terraform state hoặc bất kỳ secret nào.

Mọi thay đổi qua Pull Request với ít nhất một người review. Commit theo Conventional Commits.

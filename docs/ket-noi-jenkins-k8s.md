
## 3. Phân quyền cho môi trường Staging (i-recognition-staging)
- Đã khởi tạo namespace i-recognition-staging và cấu hình Role + RoleBinding tại k8s/rbac/jenkins-rbac.yaml.
- RoleBinding trong i-recognition-staging trỏ trực tiếp tới ServiceAccount jenkins-deployer thuộc namespace i-recognition, đảm bảo nguyên tắc quyền tối thiểu (không dùng cluster-admin) và dùng chung file kubeconfig hiện tại mà không cần cấp lại token.
- Đã cập nhật jenkins-deploy-role bổ sung quyền triển khai statefulsets (pps), persistentvolumeclaims và serviceaccounts (core), jobs (atch) phục vụ Backend Staging (PR #7), đồng thời xác nhận StorageClass mặc định local-path hoạt động bình thường trên cụm k3s.

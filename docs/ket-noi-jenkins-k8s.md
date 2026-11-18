
## 3. Phân quyền cho môi trường Staging (i-recognition-staging)
- Đã khởi tạo namespace i-recognition-staging và cấu hình Role + RoleBinding tại k8s/rbac/jenkins-rbac.yaml.
- RoleBinding trong i-recognition-staging trỏ trực tiếp tới ServiceAccount jenkins-deployer thuộc namespace i-recognition, đảm bảo nguyên tắc quyền tối thiểu (không dùng cluster-admin) và dùng chung file kubeconfig hiện tại mà không cần cấp lại token.

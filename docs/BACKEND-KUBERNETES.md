# Runbook Backend trên Kubernetes — TV2 Sang

Theo [Issue #15 của repo ứng dụng](https://github.com/01PhamTien/ai-recognition-app/issues/15).
Dùng nguyên API/Worker đã bàn giao; không thay hợp đồng API.

## Thành phần và thứ tự triển khai

1. Cluster/kubeconfig, namespace, storage và image GHCR đã publish.
2. Secret ứng dụng và Secret pull image.
3. ConfigMap, ServiceAccount và shared upload PVC.
4. PostgreSQL/Redis đã sẵn sàng (dịch vụ hiện có hoặc mẫu staging).
5. Job tạo schema ban đầu, đợi Complete trước khi chạy ứng dụng.
6. Deployment/Service API và Worker; Worker tải model trong initContainer.
7. Prometheus hoặc tích hợp scrape vào stack TV5.
8. Kiểm thử health/readiness, upload → inference, metrics và JSON stdout.

Cấu trúc:

| Đường dẫn | Vai trò |
|---|---|
| kubernetes/backend/base | ConfigMap, ServiceAccount, PVC RWX, schema Job, API/Worker Deployment và Service |
| kubernetes/backend/overlays/staging | k3s local-path RWO, API/Worker cùng một node |
| kubernetes/backend/overlays/staging-rwx | PVC RWX, có thể dùng các node khác nhau |
| kubernetes/backend/dependencies/staging | PostgreSQL/Redis đơn instance, dữ liệu trên PVC local-path |
| kubernetes/backend/monitoring | Prometheus tối thiểu, RBAC theo namespace, khám phá từng Pod |
| kubernetes/backend/examples | Secret mẫu, không được Kustomize apply tự động |
| scripts/Deploy-Backend.ps1 | Render image tag, server dry-run, deploy theo thứ tự và chờ rollout |
| scripts/Test-Backend.ps1 | Nghiệm thu thật trong cluster, có kiểm tra Prometheus up |
| scripts/New-GhcrPullSecret.ps1 | Nhập token ẩn, tạo pull Secret qua stdin |

## Điều kiện trước khi chạy

Chạy lệnh từ gốc repository ai-recognition-infra. Cần kubectl có Kustomize
(đã kiểm tra client 1.32.2), PowerShell 5.1+ hoặc PowerShell 7 và quyền tạo
Deployment/Service/ConfigMap/Secret/Job/PVC trong namespace staging. Người tạo
namespace/gắn label node cần quyền tương ứng; Prometheus mẫu cần thêm Role/RoleBinding.

Cluster phải có đủ CPU/memory theo requests. Tổng requests của backend khoảng
600m CPU/640Mi RAM; có thêm DB, Redis, model-init và Prometheus thì cần dung lượng
dư để khởi tạo. Node chạy image GHCR phải đúng kiến trúc mà Jenkins đã build
(hiện pipeline không build multi-arch; kiểm tra manifest trước khi chọn node).

Jenkins của repo ứng dụng phải đã chạy thành công stage Push Images - GHCR.
Chọn **cùng tag commit SHA** cho hai image:

- ghcr.io/01phamtien/ai-recognition-api:<TAG>
- ghcr.io/01phamtien/ai-recognition-worker:<TAG>

Không giả định tag của main đã được publish chỉ vì PR pipeline đã merge.
Manifest chứa CHON_TAG_GHCR; script bắt buộc ImageTag và thay đồng bộ image của
API, Worker, model-init và db-init. Không dùng latest. Với Docker CLI đã đăng nhập
GHCR bằng tài khoản có quyền read:packages, kiểm tra trước:

~~~powershell
$imageTag = Read-Host 'Tag commit SHA đã publish từ Jenkins'
docker buildx imagetools inspect "ghcr.io/01phamtien/ai-recognition-api:$imageTag"
if ($LASTEXITCODE -ne 0) { throw 'Image API chưa truy cập được' }
docker buildx imagetools inspect "ghcr.io/01phamtien/ai-recognition-worker:$imageTag"
if ($LASTEXITCODE -ne 0) { throw 'Image Worker chưa truy cập được' }
kubectl config current-context
kubectl get nodes -o wide
~~~

Image private cần quyền đọc package, không chỉ quyền đọc source repository.

## Namespace và shared upload storage

~~~powershell
kubectl apply -f kubernetes/backend/overlays/staging/namespace.yaml
~~~

Với **k3s local-path**, chọn đúng một node Ready, còn đủ tài nguyên và label nó:

~~~powershell
$uploadNode = Read-Host 'Tên node chạy cả API và Worker'
kubectl label node $uploadNode ai-recognition/upload-node=true --overwrite
kubectl get nodes -l ai-recognition/upload-node=true
~~~

Chỉ để đúng một node có label này. Overlay staging ép cả hai Deployment tới node
đó, dùng PVC ReadWriteOnce và strategy Recreate. RWO cho nhiều Pod trên cùng node;
nó không phải shared storage giữa nhiều node. Không đổi label sang node khác khi
PVC local-path đã bind: dữ liệu upload vẫn nằm ở node cũ. Phương án này có gián đoạn
khi rollout và không có HA khi node mất.

Với CSI/NFS hỗ trợ **ReadWriteMany**, chọn overlay staging-rwx, bỏ bước gắn label
và đặt storageClassName trong base/uploads-pvc.yaml theo StorageClass của cluster
trước khi PVC được tạo. Default StorageClass phải hỗ trợ RWX nếu để trống.
Storage driver cần cấp quyền ghi cho fsGroup 10001; với NFS root_squash, chuẩn bị
owner/group trên server nếu driver không xử lý fsGroup. Không đổi accessModes hoặc
storageClass của PVC đã bind; di chuyển dữ liệu sang PVC mới theo quy trình riêng.

Không dùng hai emptyDir riêng cho upload: Worker phải đọc được file API đã lưu.
Model dùng emptyDir riêng từng Worker, tải lại khi Pod được tạo; initContainer kiểm
tra SHA256 từ models/manifest.json trong image. Worker mount model read-only.
Node cần truy cập ghcr.io và initContainer cần HTTPS tới raw.githubusercontent.com,
media.githubusercontent.com. Không commit trọng số model.

## Secret ứng dụng và GHCR

~~~powershell
New-Item -ItemType Directory -Force .secrets | Out-Null
Copy-Item kubernetes/backend/examples/backend-secrets.env.example .secrets/backend.env
notepad.exe .secrets/backend.env
~~~

Thay mọi CHANGEME. Với DB mẫu, DATABASE_URL dùng service postgres:5432,
Redis dùng redis:6379; password trong URL cần URL-encode, POSTGRES_PASSWORD giữ
giá trị nguyên bản. Với DB/Redis bên ngoài, thay hostname, database, username,
password/TLS cho môi trường đó. Không để localhost trong URL của Pod.

~~~powershell
if (Select-String -Path .secrets/backend.env -Pattern 'CHANGEME') { throw 'Chưa thay mật khẩu mẫu' }
kubectl -n ai-recognition-staging create secret generic backend-secrets --from-env-file=.secrets/backend.env
~~~

Tạo pull Secret cho image private. Script hỏi token dưới dạng ẩn; token không đi
vào command line hoặc file:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/New-GhcrPullSecret.ps1 -Username TEN_GITHUB_CO_QUYEN_DOC_PACKAGE
~~~

Nếu hai package đã được public, dùng:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/New-GhcrPullSecret.ps1 -PublicImages
~~~

Không dùng trực tiếp Docker Desktop config.json có credsStore: Kubernetes không
chạy credential helper của máy Windows. Không commit .secrets/, .env, token,
kubeconfig hoặc manifest Secret đã render. Secret mẫu được tách khỏi kustomization.

## Biến môi trường

API và Worker cùng đọc Settings của repo ứng dụng. envFrom nạp ConfigMap
backend-config và Secret backend-secrets.

| Biến | Nguồn | Giá trị/ý nghĩa |
|---|---|---|
| DATABASE_URL | Secret | SQLAlchemy URL PostgreSQL; dùng service DNS hoặc endpoint môi trường |
| REDIS_URL | Secret | Redis URL; có thể dùng redis:// hoặc rediss:// có auth/TLS |
| POSTGRES_PASSWORD | Secret | Chỉ PostgreSQL staging dùng; bỏ nếu dùng DB ngoài |
| UPLOAD_DIR | ConfigMap | /app/data/uploads, trùng mount PVC ở cả API/Worker |
| REDIS_STREAM / REDIS_GROUP | ConfigMap | recognition:jobs / recognition-workers; phải cùng nhau |
| MAX_UPLOAD_BYTES / MAX_IMAGE_PIXELS | ConfigMap | 5242880 / 20000000 |
| CORS_ORIGINS | ConfigMap | JSON array, mặc định []; điền origin frontend khi khác domain |
| MODEL_PATH / LABELS_PATH | ConfigMap | /app/model-assets/mobilenetv2-7.onnx và synset.txt |
| MODEL_VERSION | ConfigMap | mobilenetv2-7-v1 |
| MODEL_SHA256 / LABELS_SHA256 | ConfigMap | Checksum artifact đã cố định |
| TOP_K | ConfigMap | 5 |
| JOB_LEASE_SECONDS | ConfigMap | 300; thời gian chờ claim lại job khi Worker chết |
| LOG_LEVEL | ConfigMap | INFO |

Đổi model cần image/manifest tải artifact và checksum tương ứng; đổi riêng
MODEL_VERSION không thay trọng số. Port/host do CMD image đặt: API 0.0.0.0:8000,
Worker 0.0.0.0:8001. Mỗi Pod chạy một Uvicorn process vì registry metrics nằm
trong memory. Scale bằng số Pod, không dùng --workers.

## Triển khai staging

Nếu chưa có DB/Redis, dùng mẫu staging:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Deploy-Backend.ps1 -ImageTag $imageTag -Overlay staging -WithDemoDependencies -WithPrometheus
~~~

Nếu DB/Redis và Prometheus đã được nhóm vận hành:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Deploy-Backend.ps1 -ImageTag $imageTag -Overlay staging
~~~

Dùng -Overlay staging-rwx khi đã chuẩn bị storage RWX và DB/Redis bên ngoài.
Không kết hợp staging-rwx với WithDemoDependencies vì DB/Redis demo dùng local-path.

Script server dry-run trước khi apply; Job schema cũ được tạo lại có kiểm soát
do trường template của Job là immutable. DB init thất bại sẽ dừng trước bước
apply workload mới. Các Deployment đang chạy từ lần trước không bị xóa khi DB init
thất bại. Schema init hiện chỉ create_all, không có versioned migration. Backup DB
trước nâng cấp schema; không coi script này là cơ chế migration cho thay đổi API tương lai.

Startup/liveness dùng /health để tránh restart liên tục khi DB/Redis lỗi.
Readiness dùng /ready, timeout 15 giây cho truy vấn DB và Redis.
Worker được cấp startup tối đa 600 giây sau initContainer. Model download nằm ngoài
startup budget và lỗi tải sẽ hiện tại initContainer. Requests/limits là mốc ban đầu,
cần điều chỉnh bằng số đo CPU, memory, latency và OOM thực tế.

Service api:8000 phục vụ /jobs, /health, /ready, /metrics. Service worker:8001
phục vụ health/readiness/metrics, không nhận job HTTP từ người dùng.
Phối hợp TV3/TV4 để Ingress chuyển đúng path đến api:8000; không tạo Ingress trùng.

## Prometheus và nghiệm thu

WithPrometheus triển khai Prometheus tối thiểu trong namespace staging.
Pod discovery scrape trực tiếp từng API/Worker Pod qua port http, giữ nhãn
service, namespace, pod. Annotation đơn lẻ không làm Prometheus tự scrape.

Nếu dùng stack TV5, ghép job trong monitoring/prometheus-config.yaml vào
scrape_configs và cấp RBAC get/list/watch pods trong namespace staging cho
ServiceAccount của Prometheus. Sửa subject namespace/name của RoleBinding theo
stack thật. Không chạy đồng thời hai collector nếu không muốn scrape trùng.
Prometheus mẫu dùng emptyDir, giữ tối đa 6 giờ/512 MB; cần stack TV5 với retention,
persistence và alert cho vận hành lâu dài.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Backend.ps1
kubectl -n ai-recognition-staging get pods,svc,pvc,jobs
kubectl -n ai-recognition-staging port-forward svc/backend-prometheus 9090:9090
~~~

Mở http://127.0.0.1:9090/targets, phải có API và Worker UP.
Test-Backend tạo ảnh PNG, gửi POST /jobs qua Service DNS, đợi completed, xác nhận
dự đoán và model version/hash; việc này đồng thời kiểm tra DB, Redis và shared PVC.
Script kiểm tra HTTP 200 /health, /ready, metrics, query Prometheus up cho cả hai
service và parse từng dòng JSON stdout của application container.

Nếu dùng Prometheus bên ngoài, có thể chạy -SkipPrometheus để kiểm tra ứng dụng;
cần tự kiểm tra target UP và query up trên Prometheus thật, lưu bằng chứng riêng.
SkipPrometheus không phải nghiệm thu hoàn chỉnh tiêu chí scrape.

Để xem API từ máy cá nhân:

~~~powershell
kubectl -n ai-recognition-staging port-forward svc/api 8000:8000
~~~

Lưu vào biên bản: ngày giờ, commit/tag và imageID digest thực chạy, context/namespace,
output script, target UP và reviewer. Chỉ đóng Issue #15 sau khi chạy nghiệm thu
trên cluster thật và được review.

## Vận hành, cập nhật và rollback

- Cập nhật ConfigMap/Secret rồi chạy Deploy-Backend lại với tag đã publish.
  Script restart Deployment để envFrom nhận giá trị mới.
- Đổi Secret hiện có bằng create secret --dry-run=client -o yaml rồi pipe ngay
  vào kubectl apply -f -; không in/lưu YAML Secret vào Git, không đưa password vào
  tham số command line. Đổi password DB còn cần đồng bộ password thật phía DB;
  POSTGRES_PASSWORD không tự đổi user trên PostgreSQL đã có dữ liệu.
- Rollback image bằng chạy Deploy-Backend với tag đã nghiệm thu trước đó.
  Không rollback DB schema bằng create_all. Ghi lại tag trước/sau và backup phù hợp.
- Recreate gây gián đoạn ngắn. Khi đổi sang RWX và đã đo tải có thể thiết kế
  RollingUpdate/replicas lớn hơn. Không tăng replica trên local-path rồi kỳ vọng HA.
- Worker dùng delivery at least once, lease và ACK sau commit. SIGTERM không
  bảo đảm chờ mọi inference kết thúc: code hiện join thread tối đa 10 giây.
  Job đang chạy có thể cần tối đa JOB_LEASE_SECONDS để Worker mới claim lại.
- Giữ PVC DB/Redis/upload. Không xóa Redis PVC độc lập khi còn job; mất toàn bộ Redis
  nằm ngoài cơ chế outbox/pending hiện tại. DB/Redis staging đơn instance không có HA.
- File upload được Worker dọn sau completed/failed; API crash giữa ghi file và commit
  DB có thể để file mồ côi. Theo dõi dung lượng PVC và lập lịch dọn có kiểm soát.
- Không apply các manifest staging vào production. Tạo overlay/namespace/Secret riêng,
  dùng storage và DB/Redis đã có chính sách backup/khôi phục.

Chẩn đoán:

~~~powershell
kubectl -n ai-recognition-staging get events --sort-by=.lastTimestamp
kubectl -n ai-recognition-staging describe pod TEN_POD
kubectl -n ai-recognition-staging logs deployment/api -c api --tail=50
kubectl -n ai-recognition-staging logs deployment/worker -c worker --tail=50
kubectl -n ai-recognition-staging logs deployment/worker -c model-init --tail=50
kubectl -n ai-recognition-staging logs job/backend-db-init --tail=50
~~~

ImagePullBackOff: kiểm tra tag, kiến trúc image, quyền package và ghcr-pull.
PVC Pending: kiểm tra StorageClass/accessModes và label node.
Worker init lỗi: kiểm tra HTTPS outbound, checksum và quyền model volume.
Ready 503: kiểm tra Secret URL, DNS/port DB/Redis, schema và heartbeat Worker.
Prometheus thiếu target: kiểm tra RoleBinding, pod labels/port http và cấu hình scrape.

## Kiểm tra trước commit

~~~powershell
python -m pip install -r kubernetes/backend/requirements-validation.txt
python scripts/validate_backend.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-DeploymentFlow.ps1
kubectl kustomize kubernetes/backend/overlays/staging | kubeconform -strict -summary -kubernetes-version 1.32.0
git diff --check
~~~

CI chạy các kiểm tra cấu hình và kubeconform cho base, cả hai overlay, dependencies,
monitoring; pin phiên bản công cụ và xác minh checksum download.
Đây là kiểm tra offline/schema; không thay bằng chứng chạy thật trên cluster.

Tham khảo: [Kubernetes probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/),
[Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/),
[Prometheus Kubernetes discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config).

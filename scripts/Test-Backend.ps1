[CmdletBinding()]
param(
    [string]$Namespace = 'ai-recognition-staging',
    [switch]$SkipPrometheus
)
$ErrorActionPreference = 'Stop'

# Chạy từ Pod API: xác nhận Service DNS, model Worker và shared upload PVC trong cluster.
$check = @'
import io
import json
import time
import urllib.parse
import urllib.request
from PIL import Image

def get(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        assert response.status == 200, url
        return response.read().decode()

for service, port in (("api", 8000), ("worker", 8001)):
    for path in ("/health", "/ready"):
        result = json.loads(get(f"http://{service}:{port}{path}"))
        assert result["status"] in ("ok", "ready"), (service, path)
    metrics = get(f"http://{service}:{port}/metrics")
    assert "# HELP http_requests_total" in metrics
    assert "# HELP recognition_jobs_total" in metrics

image = io.BytesIO()
Image.new("RGB", (32, 24), (200, 80, 40)).save(image, format="PNG")
boundary = "backend-kubernetes-smoke"
payload = (
    f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"smoke.png\"\r\n"
    "Content-Type: image/png\r\n\r\n"
).encode() + image.getvalue() + f"\r\n--{boundary}--\r\n".encode()
request = urllib.request.Request(
    "http://api:8000/jobs", data=payload,
    headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}, method="POST",
)
with urllib.request.urlopen(request, timeout=20) as response:
    assert response.status == 202
    accepted = json.load(response)
deadline = time.monotonic() + 120
while True:
    job = json.loads(get("http://api:8000" + accepted["status_url"]))
    if job["status"] in ("completed", "failed"):
        break
    if time.monotonic() > deadline:
        raise AssertionError("Worker không hoàn thành job trong 120 giây")
    time.sleep(2)
assert job["status"] == "completed", job
assert len(job["predictions"]) > 0
assert job["model_version"] and job["model_sha256"]
print(json.dumps({"health": "ok", "metrics": "ok", "upload": "completed", "job_id": job["job_id"]}))

CHECK_PROMETHEUS = __CHECK_PROMETHEUS__
if CHECK_PROMETHEUS:
    query = urllib.parse.quote('up{job="ai-recognition-backend"}')
    deadline = time.monotonic() + 90
    while True:
        result = json.loads(get("http://backend-prometheus:9090/api/v1/query?query=" + query))
        samples = result["data"]["result"]
        services = {s["metric"].get("service") for s in samples if s["value"][1] == "1"}
        if {"api", "worker"} <= services:
            break
        if time.monotonic() > deadline:
            raise AssertionError("Prometheus chưa scrape thành công cả API và Worker")
        time.sleep(3)
    print(json.dumps({"prometheus": "ok", "services": sorted(services)}))
'@
$check = $check.Replace('__CHECK_PROMETHEUS__', $(if ($SkipPrometheus) { 'False' } else { 'True' }))
$check | & kubectl -n $Namespace exec -i deployment/api -c api -- python -
if ($LASTEXITCODE -ne 0) { throw 'Kiểm thử health/metrics/upload/Prometheus thất bại.' }

foreach ($name in @('api', 'worker')) {
    $lines = & kubectl -n $Namespace logs "deployment/$name" -c $name --tail=30
    if ($LASTEXITCODE -ne 0) { throw "Không đọc được stdout của $name." }
    $count = 0
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { throw "Có dòng stdout không phải JSON trong container $name." }
        if (-not $entry.timestamp -or -not $entry.message -or $entry.service -ne $name) {
            throw "Log $name thiếu timestamp/message/service."
        }
        $count++
    }
    if ($count -eq 0) { throw "Container $name chưa có log để kiểm chứng." }
    Write-Output ('{0}: {1} dòng JSON stdout hợp lệ.' -f $name, $count)
}
Write-Output 'Nghiệm thu Backend thành công; lưu output cùng image tag/commit và context vào biên bản.'

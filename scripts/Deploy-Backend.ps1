[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$')]
    [string]$ImageTag,
    [ValidateSet('staging', 'staging-rwx')]
    [string]$Overlay = 'staging',
    [switch]$WithDemoDependencies,
    [switch]$WithPrometheus
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$namespace = 'ai-recognition-staging'
$backendRoot = Join-Path $repoRoot 'kubernetes/backend'

function Invoke-Kube {
    param([string[]]$Arguments)
    & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('kubectl thất bại: ' + ($Arguments -join ' ')) }
}

if ($ImageTag -in @('latest', 'CHON_TAG_GHCR')) {
    throw 'Dùng tag commit SHA đã publish trên GHCR, không dùng latest hoặc placeholder.'
}
if ($WithDemoDependencies -and $Overlay -ne 'staging') {
    throw 'DB/Redis demo dùng local-path; chỉ dành cho overlay staging.'
}
# Không đọc/in nội dung Secret. Namespace và credentials được tạo theo runbook trước bước này.
$currentContext = & kubectl config current-context
if ($LASTEXITCODE -ne 0) { throw 'Chưa có Kubernetes context.' }
Write-Output "Triển khai context=$currentContext namespace=$namespace image-tag=$ImageTag"
Invoke-Kube -Arguments @('-n', $namespace, 'get', 'secret', 'backend-secrets', 'ghcr-pull', '-o', 'name')

if ($Overlay -eq 'staging') {
    $nodes = & kubectl get nodes -l 'ai-recognition/upload-node=true' -o json
    if ($LASTEXITCODE -ne 0) { throw 'Không đọc được node.' }
    $nodeList = ($nodes -join [Environment]::NewLine) | ConvertFrom-Json
    if (@($nodeList.items).Count -ne 1) {
        throw 'Overlay local-path cần đúng một node có label ai-recognition/upload-node=true.'
    }
}
$rendered = & kubectl kustomize (Join-Path $backendRoot "overlays/$Overlay")
if ($LASTEXITCODE -ne 0) { throw 'Kustomize render thất bại.' }
$manifest = ($rendered -join [Environment]::NewLine).Replace(':CHON_TAG_GHCR', ':' + $ImageTag)
$manifestPath = Join-Path ([IO.Path]::GetTempPath()) ('backend-' + [guid]::NewGuid() + '.yaml')
try {
    [IO.File]::WriteAllText($manifestPath, $manifest, (New-Object Text.UTF8Encoding($false)))
    # Bỏ Job cũ khỏi dry-run trước khi thay image vì Job có trường immutable.
    Invoke-Kube -Arguments @('apply', '--dry-run=server', '-f', $manifestPath, '-l', 'backend.ai-recognition/phase!=schema')
    Invoke-Kube -Arguments @('apply', '-f', $manifestPath, '-l', 'backend.ai-recognition/phase=bootstrap')

    if ($WithDemoDependencies) {
        Invoke-Kube -Arguments @('apply', '-k', (Join-Path $backendRoot 'dependencies/staging'))
        foreach ($name in @('postgres', 'redis')) {
            Invoke-Kube -Arguments @('-n', $namespace, 'rollout', 'status', "statefulset/$name", '--timeout=300s')
        }
    }

    # Job tạo schema ban đầu có thể chạy lại; không phải hệ thống migration cho schema tương lai.
    Invoke-Kube -Arguments @('-n', $namespace, 'delete', 'job', 'backend-db-init', '--ignore-not-found=true')
    Invoke-Kube -Arguments @('apply', '--dry-run=server', '-f', $manifestPath, '-l', 'backend.ai-recognition/phase=schema')
    Invoke-Kube -Arguments @('apply', '-f', $manifestPath, '-l', 'backend.ai-recognition/phase=schema')
    Invoke-Kube -Arguments @('-n', $namespace, 'wait', '--for=condition=complete', 'job/backend-db-init', '--timeout=330s')
    Invoke-Kube -Arguments @('apply', '-f', $manifestPath, '-l', 'backend.ai-recognition/phase=workload')

    # envFrom không tự reload khi ConfigMap/Secret thay đổi; restart để nhận cấu hình mới.
    foreach ($name in @('api', 'worker')) {
        Invoke-Kube -Arguments @('-n', $namespace, 'rollout', 'restart', "deployment/$name")
        Invoke-Kube -Arguments @('-n', $namespace, 'rollout', 'status', "deployment/$name", '--timeout=900s')
    }

    if ($WithPrometheus) {
        Invoke-Kube -Arguments @('apply', '-k', (Join-Path $backendRoot 'monitoring'))
        Invoke-Kube -Arguments @('-n', $namespace, 'rollout', 'restart', 'deployment/backend-prometheus')
        Invoke-Kube -Arguments @('-n', $namespace, 'rollout', 'status', 'deployment/backend-prometheus', '--timeout=180s')
    }
    Write-Output 'Triển khai thành công. Chạy scripts/Test-Backend.ps1 để nghiệm thu.'
}
finally {
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath }
}

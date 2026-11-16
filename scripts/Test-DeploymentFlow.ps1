$ErrorActionPreference = 'Stop'
$global:backendRealKubectl = (Get-Command kubectl -CommandType Application).Source
$global:backendCalls = New-Object 'System.Collections.Generic.List[string]'
$global:backendFailSchema = $false
$global:backendNodeCount = 1
function global:kubectl {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    $call = $arguments -join ' '
    $global:backendCalls.Add($call)
    if ($call -eq 'config current-context') { return 'mock-context' }
    if ($arguments[0] -eq 'kustomize') {
        & $global:backendRealKubectl @arguments
        return
    }
    if ($call -like 'get nodes *') {
        return (@{items = @(1..$global:backendNodeCount | ForEach-Object { @{metadata = @{name = 'node'}} })} | ConvertTo-Json -Depth 5 -Compress)
    }
    if ($arguments[0] -eq 'apply' -and $arguments -contains '-f') {
        $path = $arguments[[Array]::IndexOf($arguments, '-f') + 1]
        $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($manifest.Contains('CHON_TAG_GHCR')) { throw 'Còn placeholder image sau render.' }
        if (-not $manifest.Contains(':72405d63cbfe')) { throw 'Tag GHCR không được truyền vào manifest.' }
    }
    if ($global:backendFailSchema -and $call -like '*wait*job/backend-db-init*') {
        $global:LASTEXITCODE = 1
    }
}
try {
    & "$PSScriptRoot/Deploy-Backend.ps1" -ImageTag '72405d63cbfe' -WithDemoDependencies -WithPrometheus | Out-Null
    $calls = $global:backendCalls
    $schemaIndex = -1
    $workloadIndex = -1
    for ($i = 0; $i -lt $calls.Count; $i++) {
        if ($calls[$i] -like '*apply*' -and $calls[$i] -notlike '*dry-run*') {
            if ($calls[$i] -like '*phase=schema*') { $schemaIndex = $i }
            if ($calls[$i] -like '*phase=workload*') { $workloadIndex = $i }
        }
    }
    if ($schemaIndex -lt 0 -or $workloadIndex -le $schemaIndex) { throw 'Sai thứ tự schema và workload.' }
    if (-not ($calls | Where-Object { $_ -like '*dry-run=server*phase!=schema*' })) {
        throw 'Dry-run sẽ lỗi immutable Job khi cập nhật image.'
    }
    Write-Output 'PASS: render image, thứ tự bootstrap/DB/schema/workload/monitoring.'

    $global:backendCalls.Clear()
    $global:backendFailSchema = $true
    $failed = $false
    try { & "$PSScriptRoot/Deploy-Backend.ps1" -ImageTag '72405d63cbfe' | Out-Null }
    catch { $failed = $true }
    if (-not $failed -or ($global:backendCalls | Where-Object { $_ -like '*phase=workload*' })) {
        throw 'Script không dừng trước workload khi schema thất bại.'
    }
    Write-Output 'PASS: schema thất bại thì không triển khai workload.'

    $global:backendCalls.Clear()
    $global:backendFailSchema = $false
    $global:backendNodeCount = 2
    $failed = $false
    try { & "$PSScriptRoot/Deploy-Backend.ps1" -ImageTag '72405d63cbfe' | Out-Null }
    catch { $failed = $true }
    if (-not $failed -or ($global:backendCalls | Where-Object { $_ -like 'apply*' })) {
        throw 'Script không chặn trường hợp RWO có nhiều node được chọn.'
    }
    Write-Output 'PASS: chặn local-path khi label chọn nhiều node.'

    $global:backendCalls.Clear()
    $failed = $false
    try { & "$PSScriptRoot/Deploy-Backend.ps1" -ImageTag 'latest' | Out-Null }
    catch { $failed = $true }
    if (-not $failed -or $global:backendCalls.Count) { throw 'Không chặn latest trước khi gọi cluster.' }
    Write-Output 'PASS: chặn tag latest trước khi thay đổi cluster.'
}
finally {
    Remove-Item Function:\kubectl
    Remove-Variable backendRealKubectl, backendCalls, backendFailSchema, backendNodeCount -Scope Global
}

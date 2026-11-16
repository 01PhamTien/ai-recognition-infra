[CmdletBinding(DefaultParameterSetName = 'Private')]
param(
    [string]$Namespace = 'ai-recognition-staging',
    [Parameter(Mandatory = $true, ParameterSetName = 'Private')]
    [string]$Username,
    [Parameter(Mandatory = $true, ParameterSetName = 'Public')]
    [switch]$PublicImages
)
$ErrorActionPreference = 'Stop'
$tokenPointer = [IntPtr]::Zero
try {
    $auths = @{}
    if (-not $PublicImages) {
        $secureToken = Read-Host 'GHCR token có read:packages (không ghi vào Git)' -AsSecureString
        $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
        if ([string]::IsNullOrWhiteSpace($plainToken)) { throw 'Token không được rỗng.' }
        $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Username + ':' + $plainToken))
        $auths['ghcr.io'] = @{ auth = $auth }
    }
    $dockerConfig = @{ auths = $auths } | ConvertTo-Json -Depth 5 -Compress
    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        metadata = @{ name = 'ghcr-pull'; namespace = $Namespace }
        type = 'kubernetes.io/dockerconfigjson'
        data = @{ '.dockerconfigjson' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dockerConfig)) }
    }
    # Truyền qua stdin, không đưa token vào command line hoặc file.
    $secret | ConvertTo-Json -Depth 6 -Compress | & kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Không tạo được ghcr-pull.' }
}
finally {
    if ($tokenPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    }
    $plainToken = $null
    $auth = $null
    $dockerConfig = $null
    $secret = $null
}

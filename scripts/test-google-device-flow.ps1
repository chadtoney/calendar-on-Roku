param(
    [string]$EnvFile = ".env",
    [string]$Scope = "https://www.googleapis.com/auth/calendar.readonly"
)

$ErrorActionPreference = "Stop"

function Get-VarFromEnvFile {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $content = Get-Content -Raw -Path $Path
    if ($null -eq $content) {
        return $null
    }

    $pattern = '(?m)^\s*{0}\s*=\s*"?([^"\r\n]+)"?\s*$' -f [regex]::Escape($Name)
    $match = [regex]::Match($content, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return $null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
if (-not (Test-Path $envPath) -and $EnvFile -eq ".env") {
    $fallbackEnv = Join-Path $repoRoot "env"
    if (Test-Path $fallbackEnv) {
        $envPath = $fallbackEnv
    }
}

$clientId = Get-VarFromEnvFile -Path $envPath -Name "CLIENT_ID"
if (-not $clientId) {
    throw "CLIENT_ID not found in '$envPath'. Add CLIENT_ID and rerun."
}

$body = @{
    client_id = $clientId
    scope     = $Scope
}

$response = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/device/code" -ContentType "application/x-www-form-urlencoded" -Body $body

if (-not $response.device_code) {
    throw "No device_code returned. Verify OAuth client type is 'TV and Limited Input devices'."
}

Write-Host "Device flow started successfully."
Write-Host "verification_url: $($response.verification_url)"
Write-Host "user_code:        $($response.user_code)"
Write-Host "expires_in:       $($response.expires_in)s"
Write-Host "interval:         $($response.interval)s"

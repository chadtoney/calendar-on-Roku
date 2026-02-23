param(
    [string]$EnvFile = ".env",
    [string]$RokuIp,
    [string]$RokuPassword,
    [string]$RokuUser,
    [string]$OutputZip = "dist/GoogleCalendar.zip",
    [switch]$AllowPlaceholders,
    [switch]$DryRun
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

function Resolve-LocalEnvPath {
    param(
        [string]$RepoRoot,
        [string]$EnvFile
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $RepoRoot $EnvFile }
    if (Test-Path $candidate) {
        return $candidate
    }

    if ($EnvFile -eq ".env") {
        $fallback = Join-Path $RepoRoot "env"
        if (Test-Path $fallback) {
            return $fallback
        }
    }

    return $candidate
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envPath = Resolve-LocalEnvPath -RepoRoot $repoRoot -EnvFile $EnvFile

if (-not $RokuIp -and (Test-Path $envPath)) {
    $RokuIp = Get-VarFromEnvFile -Path $envPath -Name "ROKU_IP"
    if (-not $RokuIp) {
        $RokuIp = Get-VarFromEnvFile -Path $envPath -Name "ROKU_HOST"
    }
    if (-not $RokuIp) {
        $RokuIp = Get-VarFromEnvFile -Path $envPath -Name "ROKU_HTTP"
    }

    if ($RokuIp -and ($RokuIp.StartsWith("http://") -or $RokuIp.StartsWith("https://"))) {
        try {
            $RokuIp = ([System.Uri]$RokuIp).Host
        } catch {
            throw "ROKU_HTTP must be a valid URL like http://192.168.1.100"
        }
    }
}

if (-not $RokuPassword -and (Test-Path $envPath)) {
    $RokuPassword = Get-VarFromEnvFile -Path $envPath -Name "ROKU_PASSWORD"
}

if (-not $RokuUser) {
    if (Test-Path $envPath) {
        $RokuUser = Get-VarFromEnvFile -Path $envPath -Name "ROKU_USER"
        if (-not $RokuUser) {
            $RokuUser = Get-VarFromEnvFile -Path $envPath -Name "ROKU_USERNAME"
        }
    }
    if (-not $RokuUser) {
        $RokuUser = "rokudev"
    }
}

if (-not $RokuIp) {
    throw "Missing Roku IP. Set ROKU_IP in '$envPath' or pass -RokuIp."
}

if (-not $RokuPassword) {
    throw "Missing Roku password. Set ROKU_PASSWORD in '$envPath' or pass -RokuPassword."
}

$packageScript = Join-Path $PSScriptRoot "package-roku.ps1"
$packageArgs = @{
    EnvFile = $EnvFile
    OutputZip = $OutputZip
}
if ($AllowPlaceholders) {
    $packageArgs.AllowPlaceholders = $true
}

Write-Host "Packaging app..."
& $packageScript @packageArgs

$zipPath = if ([System.IO.Path]::IsPathRooted($OutputZip)) { $OutputZip } else { Join-Path $repoRoot $OutputZip }
if (-not (Test-Path $zipPath)) {
    throw "Package not found: $zipPath"
}

$installUri = "http://$RokuIp/plugin_install"

if ($DryRun) {
    Write-Host "Dry run complete."
    Write-Host "Would upload '$zipPath' to $installUri"
    return
}

Write-Host "Uploading package to Roku at $RokuIp..."
$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($null -eq $curl) {
    throw "curl.exe is required for Roku Digest auth sideload on this machine."
}

$curlArgs = @(
    "--silent",
    "--show-error",
    "--fail",
    "--digest",
    "--user", "$RokuUser`:$RokuPassword",
    "-F", "mysubmit=Install",
    "-F", "passwd=$RokuPassword",
    "-F", "archive=@$zipPath",
    $installUri
)

& $curl.Source @curlArgs
if ($LASTEXITCODE -ne 0) {
    throw "Sideload upload failed (curl exit code $LASTEXITCODE). Check Roku credentials and Developer Mode password."
}

Write-Host "Sideload complete. App installed on Roku."

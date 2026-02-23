param(
    [string]$EnvFile = ".env",
    [string]$OutputZip = "dist/GoogleCalendar.zip",
    [switch]$AllowPlaceholders
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
$outputPath = if ([System.IO.Path]::IsPathRooted($OutputZip)) { $OutputZip } else { Join-Path $repoRoot $OutputZip }

$stagingRoot = Join-Path $repoRoot ".build"
$stagingPath = Join-Path $stagingRoot "package"

if (Test-Path $stagingPath) {
    Remove-Item -Recurse -Force $stagingPath
}

New-Item -ItemType Directory -Path $stagingPath | Out-Null

foreach ($entry in @("manifest", "source", "components", "images")) {
    $sourcePath = Join-Path $repoRoot $entry
    if (-not (Test-Path $sourcePath)) {
        throw "Required path not found: $entry"
    }

    if ((Get-Item $sourcePath).PSIsContainer) {
        Copy-Item -Recurse -Path $sourcePath -Destination (Join-Path $stagingPath $entry)
    } else {
        Copy-Item -Path $sourcePath -Destination (Join-Path $stagingPath $entry)
    }
}

$clientId = $null
$clientSecret = $null

if (Test-Path $envPath) {
    $clientId = Get-VarFromEnvFile -Path $envPath -Name "CLIENT_ID"
    $clientSecret = Get-VarFromEnvFile -Path $envPath -Name "CLIENT_SECRET"
}

if ($clientId -and $clientSecret) {
    $calendarTaskPath = Join-Path $stagingPath "components/CalendarTask.brs"
    $calendarTask = Get-Content -Raw -Path $calendarTaskPath

    $calendarTask = [regex]::Replace(
        $calendarTask,
        "(?m)^\s*const\s+GOOGLE_CLIENT_ID\s*=\s*.*$",
        ('const GOOGLE_CLIENT_ID     = "{0}"' -f $clientId)
    )

    $calendarTask = [regex]::Replace(
        $calendarTask,
        "(?m)^\s*const\s+GOOGLE_CLIENT_SECRET\s*=\s*.*$",
        ('const GOOGLE_CLIENT_SECRET = "{0}"' -f $clientSecret)
    )

    Set-Content -Path $calendarTaskPath -Value $calendarTask -NoNewline
    Write-Host "Using credentials from $envPath"
} elseif (-not $AllowPlaceholders) {
    throw "Missing CLIENT_ID/CLIENT_SECRET in '$envPath'. Add values to env or rerun with -AllowPlaceholders."
} else {
    Write-Host "No env credentials found. Packaging with placeholder constants."
}

$outputDir = Split-Path -Parent $outputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

if (Test-Path $outputPath) {
    Remove-Item -Force $outputPath
}

Compress-Archive -Path (Join-Path $stagingPath "*") -DestinationPath $outputPath -Force

Write-Host "Created Roku package: $outputPath"
Write-Host "Upload this zip to your Roku Developer Web UI (http://<roku-ip>)."

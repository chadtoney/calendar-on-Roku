param(
    [string]$EnvFile = ".env",
    [string]$Scope = "https://www.googleapis.com/auth/calendar.readonly",
    [string]$CalendarId = "primary",
    [int]$MaxResults = 5,
    [switch]$ListCalendarsOnly
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
    param([string]$RepoRoot, [string]$EnvFile)

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

$clientId = Get-VarFromEnvFile -Path $envPath -Name "CLIENT_ID"
$clientSecret = Get-VarFromEnvFile -Path $envPath -Name "CLIENT_SECRET"

if (-not $clientId) {
    throw "CLIENT_ID not found in '$envPath'. Add CLIENT_ID and rerun."
}

if (-not $clientSecret) {
    throw "CLIENT_SECRET not found in '$envPath'. Add CLIENT_SECRET and rerun."
}

Write-Host "Requesting device code..."
$deviceResponse = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/device/code" -ContentType "application/x-www-form-urlencoded" -Body @{
    client_id = $clientId
    scope     = $Scope
}

if (-not $deviceResponse.device_code) {
    throw "No device_code returned. Verify OAuth client type is 'TV and Limited Input devices'."
}

Write-Host "Open: $($deviceResponse.verification_url)"
Write-Host "Enter code: $($deviceResponse.user_code)"
Write-Host "Waiting for approval..."

$interval = [Math]::Max([int]$deviceResponse.interval, 5)
$maxWaitSeconds = [Math]::Max([int]$deviceResponse.expires_in, 300)
$elapsed = 0
$accessToken = $null

while ($elapsed -lt $maxWaitSeconds) {
    Start-Sleep -Seconds $interval
    $elapsed += $interval

    $tokenHttp = Invoke-WebRequest -Method Post -Uri "https://oauth2.googleapis.com/token" -ContentType "application/x-www-form-urlencoded" -Body @{
        client_id     = $clientId
        client_secret = $clientSecret
        device_code   = $deviceResponse.device_code
        grant_type    = "urn:ietf:params:oauth:grant-type:device_code"
    } -SkipHttpErrorCheck

    $token = $null
    if ($tokenHttp.Content) {
        $token = $tokenHttp.Content | ConvertFrom-Json
    }

    if ($tokenHttp.StatusCode -eq 200 -and $token.access_token) {
        $accessToken = $token.access_token
        break
    }

    if ($token.error -eq "authorization_pending") {
        continue
    }

    if ($token.error -eq "slow_down") {
        $interval += 5
        continue
    }

    if ($token.error) {
        throw "Token error: $($token.error)"
    }

    throw "Unexpected token response: HTTP $($tokenHttp.StatusCode)"
}

if (-not $accessToken) {
    throw "Timed out waiting for approval."
}

$headers = @{ Authorization = "Bearer $accessToken" }

Write-Host "Fetching calendar list for signed-in account..."
$calendarList = Invoke-RestMethod -Method Get -Uri "https://www.googleapis.com/calendar/v3/users/me/calendarList" -Headers $headers

if (-not $calendarList.items -or $calendarList.items.Count -eq 0) {
    Write-Host "No calendars returned for this account."
} else {
    Write-Host "Calendars available:"
    foreach ($calendar in $calendarList.items) {
        $isPrimary = if ($calendar.primary) { "(primary)" } else { "" }
        Write-Host ("- {0}  id={1} {2}" -f $calendar.summary, $calendar.id, $isPrimary)
    }
}

if ($ListCalendarsOnly) {
    return
}

$encodedCalendarId = [System.Uri]::EscapeDataString($CalendarId)
$timeMin = (Get-Date).ToUniversalTime().ToString("o")
$eventsUri = "https://www.googleapis.com/calendar/v3/calendars/$encodedCalendarId/events?singleEvents=true&orderBy=startTime&timeMin=$([System.Uri]::EscapeDataString($timeMin))&maxResults=$MaxResults"

Write-Host "Fetching upcoming events from calendar '$CalendarId'..."
$events = Invoke-RestMethod -Method Get -Uri $eventsUri -Headers $headers

if (-not $events.items -or $events.items.Count -eq 0) {
    Write-Host "No upcoming events found."
    return
}

Write-Host "Upcoming events:"
foreach ($event in $events.items) {
    $start = if ($event.start.dateTime) { $event.start.dateTime } else { $event.start.date }
    Write-Host ("- {0} | {1}" -f $start, $event.summary)
}

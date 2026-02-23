' -------------------------------------------------------
' CalendarTask.brs – Google OAuth device flow + Calendar API
'
' Configure your Google Cloud OAuth 2.0 credentials below.
' Create credentials at https://console.cloud.google.com/
'   Application type: "TV and Limited Input devices"
' -------------------------------------------------------

' ===== USER CONFIGURATION =====
const GOOGLE_CLIENT_ID     = "YOUR_CLIENT_ID_HERE"
const GOOGLE_CLIENT_SECRET = "YOUR_CLIENT_SECRET_HERE"
' ==============================

const GOOGLE_SCOPE         = "https://www.googleapis.com/auth/calendar.readonly"
const DEVICE_CODE_URL      = "https://oauth2.googleapis.com/device/code"
const TOKEN_URL            = "https://oauth2.googleapis.com/token"
const CALENDAR_EVENTS_URL  = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

' Entry point called by the Task infrastructure
sub init()
    m.port = CreateObject("roMessagePort")
end sub

' Called when the "command" field changes
sub onCommand()
    cmd = m.top.command
    if cmd = "startAuth"
        startDeviceAuth()
    else if cmd = "fetchEvents"
        fetchCalendarEvents()
    end if
end sub

' -------------------------------------------------------
' Step 1 – Request a device / user code from Google
' -------------------------------------------------------
sub startDeviceAuth()
    url = CreateObject("roUrlTransfer")
    url.setUrl(DEVICE_CODE_URL)
    url.setCertificatesFile("common:/certs/ca-bundle.crt")
    url.addHeader("Content-Type", "application/x-www-form-urlencoded")

    body = "client_id=" + GOOGLE_CLIENT_ID + "&scope=" + GOOGLE_SCOPE
    response = url.postFromString(body)

    if response = invalid or response = ""
        m.top.errorMsg = "Network error requesting device code"
        m.top.state    = "error"
        return
    end if

    parsed = ParseJson(response)
    if parsed = invalid or parsed.device_code = invalid
        m.top.errorMsg = "Unexpected response from auth server: " + response
        m.top.state    = "error"
        return
    end if

    m.deviceCode     = parsed.device_code
    m.interval       = parsed.interval
    m.expiresIn      = parsed.expires_in

    m.top.userCode        = parsed.user_code
    m.top.verificationUrl = parsed.verification_url
    m.top.state           = "waitingForUser"

    ' Begin polling for the token
    pollForToken()
end sub

' -------------------------------------------------------
' Step 2 – Poll the token endpoint until the user approves
' -------------------------------------------------------
sub pollForToken()
    interval = m.interval
    if interval = invalid or interval < 5 then interval = 5

    elapsed = 0
    maxWait = m.expiresIn
    if maxWait = invalid or maxWait < 60 then maxWait = 300

    while elapsed < maxWait
        sleep(interval * 1000)
        elapsed = elapsed + interval

        url = CreateObject("roUrlTransfer")
        url.setUrl(TOKEN_URL)
        url.setCertificatesFile("common:/certs/ca-bundle.crt")
        url.addHeader("Content-Type", "application/x-www-form-urlencoded")

        body = "client_id="     + GOOGLE_CLIENT_ID + _
               "&client_secret=" + GOOGLE_CLIENT_SECRET + _
               "&device_code="   + m.deviceCode + _
               "&grant_type=urn:ietf:params:oauth:grant-type:device_code"

        response = url.postFromString(body)
        parsed   = ParseJson(response)

        if parsed = invalid
            ' transient error – keep trying
        else if parsed.access_token <> invalid
            m.top.accessToken = parsed.access_token
            m.top.state       = "authenticated"
            return
        else if parsed.error = "authorization_pending"
            ' user has not yet approved – keep polling
        else if parsed.error = "slow_down"
            interval = interval + 5
        else
            m.top.errorMsg = "Auth error: " + parsed.error
            m.top.state    = "error"
            return
        end if
    end while

    m.top.errorMsg = "Authorization timed out. Please restart the app and try again."
    m.top.state    = "error"
end sub

' -------------------------------------------------------
' Step 3 – Fetch upcoming events from the Calendar API
' -------------------------------------------------------
sub fetchCalendarEvents()
    token = m.top.accessToken
    if token = "" or token = invalid
        m.top.errorMsg = "No access token – please authorize first"
        m.top.state    = "error"
        return
    end if

    ' Build query: next 10 single-instance events starting from now
    now     = CreateObject("roDateTime")
    timeMin = now.toISOString()
    queryArgs = "?maxResults=10&orderBy=startTime&singleEvents=true&timeMin=" + EncodeUriComponent(timeMin)

    url = CreateObject("roUrlTransfer")
    url.setUrl(CALENDAR_EVENTS_URL + queryArgs)
    url.setCertificatesFile("common:/certs/ca-bundle.crt")
    url.addHeader("Authorization", "Bearer " + token)

    response = url.getToString()
    parsed   = ParseJson(response)

    if parsed = invalid or parsed.items = invalid
        m.top.errorMsg = "Could not retrieve calendar events"
        m.top.state    = "error"
        return
    end if

    ' Build a simplified array of event objects for the UI
    events = []
    for each item in parsed.items
        event = {}
        event.title = item.summary
        if event.title = invalid then event.title = "(No title)"

        ' Prefer dateTime over date (all-day events use date only)
        if item.start.dateTime <> invalid
            event.start = item.start.dateTime
        else
            event.start = item.start.date
        end if

        if item.end.dateTime <> invalid
            event.end = item.end.dateTime
        else
            event.end = item.end.date
        end if

        event.location    = item.location
        event.description = item.description
        events.push(event)
    end for

    m.top.events = FormatJson(events)
    m.top.state  = "eventsReady"
end sub

' -------------------------------------------------------
' Helper – percent-encode a string for URL query params
' -------------------------------------------------------
function EncodeUriComponent(s as string) as string
    encoded = ""
    allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    for i = 0 to len(s) - 1
        c = mid(s, i + 1, 1)
        if instr(1, allowed, c) > 0
            encoded = encoded + c
        else
            encoded = encoded + "%" + right("0" + decToHex(asc(c)), 2)
        end if
    end for
    return encoded
end function

function decToHex(n as integer) as string
    hex = "0123456789ABCDEF"
    if n = 0 then return "00"
    result = ""
    while n > 0
        result = mid(hex, (n mod 16) + 1, 1) + result
        n = n \ 16
    end while
    if len(result) = 1 then result = "0" + result
    return result
end function

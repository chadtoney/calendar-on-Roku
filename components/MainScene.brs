' -------------------------------------------------------
' MainScene.brs – UI logic for the Google Calendar Roku app
' -------------------------------------------------------

sub init()
    m.task = CreateObject("roSGNode", "CalendarTask")
    m.task.observeField("state", "onTaskStateChange")

    ' Start the OAuth device-auth flow immediately on launch
    m.task.control = "RUN"
    m.task.command  = "startAuth"

    ' Listen for remote-control key presses
    m.top.setFocus(true)
end sub

' -------------------------------------------------------
' React to state changes reported by CalendarTask
' -------------------------------------------------------
sub onTaskStateChange()
    state = m.task.state

    hideAllPanels()

    if state = "waitingForUser"
        showAuthPanel()
    else if state = "authenticated"
        showLoadingPanel("Signed in!  Loading your calendar…")
        ' Kick off event fetch in the same task
        m.task.command = "fetchEvents"
    else if state = "eventsReady"
        showEventsPanel()
    else if state = "error"
        showErrorPanel(m.task.errorMsg)
    end if
end sub

' -------------------------------------------------------
' Panel helpers
' -------------------------------------------------------
sub hideAllPanels()
    m.top.findNode("authPanel").visible    = false
    m.top.findNode("loadingPanel").visible = false
    m.top.findNode("eventsPanel").visible  = false
    m.top.findNode("errorPanel").visible   = false
end sub

sub showAuthPanel()
    panel = m.top.findNode("authPanel")
    m.top.findNode("authUrl").text  = m.task.verificationUrl
    m.top.findNode("authCode").text = m.task.userCode
    panel.visible = true
end sub

sub showLoadingPanel(msg as string)
    m.top.findNode("loadingMsg").text    = msg
    m.top.findNode("loadingPanel").visible = true
end sub

sub showEventsPanel()
    eventsJson = m.task.events
    events     = ParseJson(eventsJson)

    rowGroup = m.top.findNode("eventRows")

    ' Remove any previously rendered rows
    while rowGroup.getChildCount() > 0
        rowGroup.removeChildIndex(0)
    end while

    if events = invalid or events.count() = 0
        noEvents = CreateObject("roSGNode", "Label")
        noEvents.text  = "No upcoming events found."
        noEvents.color = "#aaaaaa"
        noEvents.font  = "font:SmallSystemFont"
        rowGroup.appendChild(noEvents)
    else
        rowY = 0
        for each event in events
            ' Event row background
            bg = CreateObject("roSGNode", "Rectangle")
            bg.color       = "#16213e"
            bg.width       = 1200
            bg.height      = 90
            bg.translation = [0, rowY]

            ' Title
            titleLabel = CreateObject("roSGNode", "Label")
            titleLabel.text        = event.title
            titleLabel.font        = "font:SmallBoldSystemFont"
            titleLabel.color       = "#e2e2e2"
            titleLabel.translation = [16, 10]
            bg.appendChild(titleLabel)

            ' Date / time
            timeLabel = CreateObject("roSGNode", "Label")
            timeLabel.text        = formatEventTime(event.start, event.end)
            timeLabel.font        = "font:SmallSystemFont"
            timeLabel.color       = "#4fc3f7"
            timeLabel.translation = [16, 42]
            bg.appendChild(timeLabel)

            ' Location (if present)
            if event.location <> invalid and event.location <> ""
                locLabel = CreateObject("roSGNode", "Label")
                locLabel.text        = "📍 " + event.location
                locLabel.font        = "font:SmallSystemFont"
                locLabel.color       = "#aaaaaa"
                locLabel.translation = [16, 66]
                bg.appendChild(locLabel)
            end if

            rowGroup.appendChild(bg)
            rowY = rowY + 100
        end for
    end if

    m.top.findNode("eventsPanel").visible = true
end sub

sub showErrorPanel(msg as string)
    if msg = invalid then msg = "An unknown error occurred."
    m.top.findNode("errorDetail").text  = msg
    m.top.findNode("errorPanel").visible = true
end sub

' -------------------------------------------------------
' Format a start/end time string for display
' -------------------------------------------------------
function formatEventTime(startStr as string, endStr as string) as string
    if startStr = invalid then return ""

    ' All-day events have a date-only string (YYYY-MM-DD, length 10)
    if len(startStr) = 10
        if endStr <> invalid and endStr <> startStr
            return startStr + "  –  " + endStr + "  (all day)"
        end if
        return startStr + "  (all day)"
    end if

    ' DateTime string: 2024-06-15T09:00:00-07:00
    ' Extract date and time portions for a friendlier display
    datePart  = left(startStr, 10)
    timePart  = mid(startStr, 12, 5)

    if endStr <> invalid and len(endStr) >= 16
        endTimePart = mid(endStr, 12, 5)
        return datePart + "  " + timePart + " – " + endTimePart
    end if

    return datePart + "  " + timePart
end function

' -------------------------------------------------------
' Handle remote-control key presses
' -------------------------------------------------------
function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "OK"
        state = m.task.state
        if state = "error"
            ' Retry the whole flow
            hideAllPanels()
            showLoadingPanel("Retrying…")
            m.task.command = "startAuth"
        else if state = "eventsReady"
            ' Refresh events
            hideAllPanels()
            showLoadingPanel("Refreshing…")
            m.task.command = "fetchEvents"
        end if
        return true
    end if
    return false
end function

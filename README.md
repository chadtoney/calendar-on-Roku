# calendar-on-Roku

A Roku channel that displays your upcoming Google Calendar events on your TV
using the Google Calendar API and OAuth 2.0 Device Flow.

---

## Features

* Signs in via the **Google OAuth 2.0 Device Flow** – no keyboard required.  
  You authorize once on a phone / computer; the Roku remembers your session.
* Shows the next **10 upcoming events** from your primary Google Calendar.
* Displays event title, date/time, and location.
* Press **OK** on the remote to refresh events or retry after an error.

---

## Repository layout

```
manifest                  Roku channel manifest
source/
  main.brs                App entry point
components/
  MainScene.xml           Root SceneGraph scene (UI)
  MainScene.brs           UI logic
  CalendarTask.xml        Background Task node (network I/O)
  CalendarTask.brs        OAuth device flow + Calendar API calls
images/
  icon_focus_hd.png       Channel icon (focused, 540×405)
  icon_side_hd.png        Channel icon (side panel, 246×140)
  splash_hd.png           Splash screen (1280×720)
```

---

## Setup

### 1 – Google Cloud credentials

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (or select an existing one).
3. Enable the **Google Calendar API** for the project.
4. Under *APIs & Services → Credentials*, click **Create credentials → OAuth 2.0 Client ID**.
5. Select **Application type: TV and Limited Input devices**.
6. Note the **Client ID** and **Client Secret**.

### 2 – Configure the app (keep secrets out of git)

This repo keeps placeholder values in `components/CalendarTask.brs` on purpose.
Do **not** commit real credentials.

Recommended workflow:

1. Keep local credentials in an untracked `env` (or `.env`) file.
2. Leave committed source files with placeholders.
3. Before sideloading, inject or copy local values into your local working copy only.
4. Never push real `CLIENT_SECRET` values to GitHub.

An `.env.example` template is included for the variable names.

### 3 – Set up your Roku for development

1. Enable **Developer Mode** on your Roku:  
   Home × 3, Up × 2, Right, Left, Right, Left, Right
2. Note the IP address shown on screen and set a password.
3. The Roku Developer Web UI is at `http://<roku-ip>`.

### 4 – Package and sideload the channel

**Recommended (Windows PowerShell script):**

```powershell
pwsh ./scripts/package-roku.ps1
```

This reads `env` (or `.env`) locally, injects credentials into a temporary build folder,
and creates `dist/GoogleCalendar.zip` without changing tracked source files.

If you intentionally want a package with placeholders only:

```powershell
pwsh ./scripts/package-roku.ps1 -AllowPlaceholders
```

**Option A – zip manually:**

```bash
cd /path/to/calendar-on-Roku
zip -r GoogleCalendar.zip manifest source components images
```

Then go to `http://<roku-ip>`, click **Upload channel zip**, and select the zip file.

**Option B – Roku CLI (rokuDeploy / brs):**

```bash
npm install -g @rokucommunity/roku-deploy
npx roku-deploy --host <roku-ip> --password <dev-password>
```

### 5 – Authorize Google Calendar

1. Launch the **Google Calendar** channel on your Roku.
2. On a phone or computer, open the URL shown on screen  
   (`https://www.google.com/device`).
3. Enter the code displayed on the TV.
4. Approve the *Google Calendar (read-only)* permission.
5. The TV automatically loads your upcoming events.

---

## Development notes

* Network calls happen in a `Task` node (`CalendarTask`) so the UI thread
  is never blocked.
* The OAuth **access token** is stored only in memory; it is not persisted
  across channel restarts.  Re-authorization is required each time the
  channel is launched.
* To support token refresh across restarts, store the **refresh token**
  (returned alongside `access_token`) in the Roku registry
  (`roRegistrySection`) and exchange it for a new access token on startup.

---

## References

* [Roku Developer Documentation](https://developer.roku.com/docs/developer-program/getting-started/hello-world.md)
* [Google Calendar API](https://developers.google.com/workspace/calendar)
* [OAuth 2.0 for TV and Limited-Input Device Applications](https://developers.google.com/identity/protocols/oauth2/limited-input-device)

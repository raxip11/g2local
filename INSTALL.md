# G2 Local — install & build guide

Native iOS app: loopback ASR server (`127.0.0.1:8321`) + WhisperKit, for the
G2 Voice webview. Audio never leaves the phone.

## One-time setup

1. Create a **private** GitHub repo named `g2local` (no README).
2. On your PC (Git Bash or PowerShell):

   ```bash
   cd <this folder>
   git init
   git add .
   git commit -m "G2 Local v0.1"
   git remote add origin https://github.com/<you>/g2local.git
   git push -u origin main
   ```

3. First CI run (~15–25 min) builds the unsigned `.ipa`.
   Watch it at: `https://github.com/<you>/g2local/actions`

## Optional: auto-deploy to oaksthepomchi

Add **repo secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `G2LOCAL_DEPLOY_SSH_PRIVATE_KEY` | contents of a **new** deploy-only SSH private key |
| `G2LOCAL_DEPLOY_USER` | `debian` |
| `G2LOCAL_DEPLOY_HOST` | `192.99.144.204` |

To make the deploy key: on the server add a public key to
`/home/debian/.ssh/authorized_keys` (restrict with command=scp if desired).
Then every build also lands at:

- https://oaksthepomchi.com/voice/g2local/G2Local.ipa  (always the latest)
- https://oaksthepomchi.com/voice/g2local/  (download page + install steps)

Without the secrets, download the `.ipa` from the Actions page artifact
(`G2Local-ipa`).

## Install on iPhone (Sideloadly, Windows)

1. Download `G2Local.ipa`.
2. Sideloadly: drag in the ipa → sign in with your Apple ID (2FA code).
3. iPhone connected via USB → **Start**.
4. iPhone: Settings → General → VPN & Device Management → trust.
5. Open **G2 Local** — first launch downloads the Whisper `small` model
   (~500 MB, one time, needs internet that once).
6. Green dot + "ready" → the local server is live on `127.0.0.1:8321`.

## Use it

Open the G2 Voice page in Even Hub with the local switch:

```
https://oaksthepomchi.com/voice/v4.html?asr_base=http://127.0.0.1:8321
```

- Local app running → transcription happens **on the phone, zero internet**
- Local app off → automatic fallback to the cloud endpoint (never breaks)

Toggle **"Keep alive in background"** in the app to survive screen-off
(cost: "G2 Local" shows in the Now Playing indicator).

## 7-day expiry (free Apple ID)

The install expires after 7 days. Fixes:
- A fresh `.ipa` is rebuilt every Monday automatically (CI schedule).
- Re-run the Sideloadly 30-second ritual with the fresh build.
- $99/yr Apple Developer account = 1-year expiry instead (same pipeline).

## Troubleshooting

- **CI fails on SPM resolve** — WhisperKit is pinned to tag `1.1.0`
  (`project.yml`); bump the version there for updates.
- **App stuck on "loading model"** — first run needs internet for the
  ~500 MB model download; check the status text for the real error.
- **Page can't reach localhost** — Even Hub webview must allow mixed
  content to `http://127.0.0.1` (loopback is usually exempt); the page
  auto-falls back to cloud, check the lens for "Error:" if not.

<!-- retrigger 2026-09-08 -->

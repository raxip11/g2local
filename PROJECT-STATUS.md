# G2 Local — iOS offline ASR companion for the G2 Voice webview

> **STATUS (as of 2026-09-09): BUILD IS GREEN. The `.ipa` is compiled and available
> as a GitHub Actions artifact. Only the SIDELOAD step remains — blocked on
> Canadian App Store region (no sideloading apps available in CA).**
>
> This doc is the full resume point. Read top to bottom to pick the project back up.

---

## 1. What this project is

**G2 Local** is a native iOS app (SwiftUI) that runs **WhisperKit** (Apple CoreML
Whisper) fully offline on the phone, exposing a **localhost HTTP server**
(`127.0.0.1:8321`) that speaks the **exact same protocol** as the cloud ASR
service. The existing **G2 Voice** webview (Even Realities / Even Hub) is pointed
at the phone with `?asr_base=http://127.0.0.1:8321` and everything stays
on-device — no cloud, no latency.

- The app owns **NO microphone**. The G2 mic streams through the Even Hub webview;
  the app just receives 16 kHz f32 mono PCM over loopback and transcribes it.
- Cloud path (webview + server-side faster-whisper) is already live and is the
  fallback. This offline iOS app is the remaining piece.

### Why offline
- Zero cloud latency for the G2 real-time voice use case.
- Works with no network once the model is downloaded once.
- Model runs on-device via Apple CoreML (WhisperKit).

---

## 2. Current state (the important part)

| Item | State |
|---|---|
| App source code | ✅ Complete, committed |
| CI build (GitHub Actions, macos-15) | ✅ **GREEN** — produces a valid `.ipa` |
| `.ipa` artifact | ✅ Built — `G2Local-v20260908-ca915f8.ipa` (~690 KB) |
| WhisperKit | ✅ v1.1.0, resolved + compiled |
| Model | `openai_whisper-small` (downloads ~500 MB on first launch, one time) |
| **Sideloading to iPhone** | ❌ **BLOCKED — Canadian App Store has no sideloading apps** |

**The single remaining task:** get the built `.ipa` onto the user's
**iPhone 16 Pro (latest iOS)** and sign it.

### Why sideloading is blocked
- User's App Store region = **Canada**.
- **AltStore / AltStore Classic** → US App Store only.
- **GetSideloader / Sidecar** (Apple's new official sideload apps) → **EU only**.
- **SideStore** → US/EU only (and needs a one-time PC pairing anyway).
- Verified directly via Apple's iTunes search API (`country=ca`): **zero**
  sideloading apps in the Canadian store.
- iPhone 16 Pro on latest iOS → **TrollStore unavailable** (needs ≤ iOS 16.6.1).

### Two remaining options (pick one to finish)

**Option A — Throwaway US Apple ID → AltStore (recommended, free, all on-phone)**
- Create a free US Apple ID, switch the App Store to it, install AltStore,
  switch the *main* Canadian ID back in. AltStore auto-refreshes the 7-day
  signature weekly, on-phone, no PC.
- Full steps below (section 6).

**Option B — Web-based ad-hoc signer (ksign.app / esign.pro)**
- On the phone's Safari: download the `.ipa` from the GitHub green run,
  upload to a web signer, get a Safari install link, tap install, enable
  Developer Mode.
- Cost: ~$5–15 per 7-day sign (repeat, or pay for their auto-renew).
- No US account fiddling, but you pay per refresh.

**Option C — (not recommended) PC-based signer (Sideloadly / iSign / ESign)**
- User explicitly does NOT want signing software on this PC. Listed for completeness.

---

## 3. Repository & location

- **GitHub:** `github.com/raxip11/g2local` (**PUBLIC** — required for free-plan Actions)
  - GitHub account: `raxip11` (created 2026-09-08, very new account)
- **Local project folder:**
  `C:\Users\olamaman\.openclaw\workspace\projects\g2-voice\g2local\`
- **Git identity used for commits:** `oaksthepomchi` / `dev@oaksthepomchi.com`
- **Latest green commit:** `ca915f8` (HEAD)

### Repo layout
```
g2local/
  .github/workflows/build.yml   # CI: xcodegen + xcodebuild archive (macos-15)
  .gitattributes                # * -text eol=lf  (CRITICAL — prevents CRLF breakage)
  .gitignore
  project.yml                   # XcodeGen spec
  PUSH-G2LOCAL.bat              # Windows: git add/commit/push in one double-click
  INSTALL.md
  G2Local/
    G2LocalApp.swift            # App entry, AppModel, ContentView (UI)
    LocalASRServer.swift        # Loopback HTTP server (127.0.0.1:8321)
    WhisperEngine.swift         # WhisperKit wrapper (model load + transcribe)
    BackgroundAudioPlayer.swift # Silent audio heartbeat (keeps app alive)
    Assets.xcassets/
      AppIcon.appiconset/       # 1024x1024 icon + Contents.json
      Contents.json
    Info.plist
```

### Commit history (newest first)
```
ca915f8 fix(swift): UTF8.self codec, unterminated raw string, missing await
95a4b7d fix: add AppIcon asset set (1024x1024) - fixes ARCHIVE FAILED
70c1724 fix(ci): use ::error:: annotations (correct workflow annotation syntax)
1f709d0 fix: load model in WhisperKit init; CI self-reports compile errors
b83cd14 fix(project.yml): declare WhisperKit at project level (XcodeGen requirement)
9fb4211 fix(ci): clean workflow (was invalid: bad line ending broke secrets ref)
f64c3f3 chore: trigger first real build (repo now public)
f7159c2 diag: smoke test workflow
2dfb07e fix(ci): remove schedule+workflow_dispatch (not allowed on free private repo)
dbe509e chore: retrigger CI
9a0ddd8 G2 Local v0.1
```

---

## 4. How the app works (architecture)

### Loopback protocol (identical to cloud ASR)
- **`GET /asr/health`** → `{"ok":true,"model":"...","state":"..."}` (public)
- **`POST /asr`** → body `{"task","language","pcm_b64"}`, header `x-asr-token`
  → response `{"text","language","duration","seconds"}`
- **`OPTIONS *`** → 204 + CORS headers (lets the cloud-hosted page reach localhost)
- Binds **127.0.0.1 only** (nothing off-device can reach it); the token is
  defense-in-depth and is intentionally the same value baked into the live
  webview bundle.

### Token (public, shared with the webview)
```
CZHLxT-CW6ZnLFasS6LWiV07QqTMK0TNuE8aNUUm4UE
```
(Also accepts a local-only dev token `g2local-local`.)

### Key design decisions
- **`NSAllowsLocalNetworking: true`** in Info.plist — iOS ATS exemption so the
  webview page can talk to `http://127.0.0.1:8321`.
- **`UIBackgroundModes: [audio]`** + a **silent AVAudioEngine heartbeat** —
  iOS suspends backgrounded apps; without a background mode the loopback server
  dies when the screen locks. Cost: "G2 Local" shows in the Now Playing bar
  while the heartbeat runs (toggle in-app).
- **Unsigned archive** in CI: `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGN_IDENTITY="-"`.
  The sideloader re-signs locally with the user's Apple ID.
- **WhisperKit `load: true`** is REQUIRED — with a model *name* (no folder),
  WhisperKit defaults `load` to false, which would download but never load the
  model and every transcribe call would fail. (Bug fixed in `1f709d0`.)
- **No `-exportArchive`** — with signing disabled, export needs provisioning
  tricks. CI zips the `.app` into an ipa manually instead.

### WhisperKit v1.1.0 API (verified against the exact tag)
- `WhisperKit(model: String? = nil, ..., load: Bool? = nil, ...) async throws`
- `transcribe(audioArray: [Float], decodeOptions: DecodingOptions? = nil, ...) async throws -> [TranscriptionResult]`
- `DecodingOptions(task: DecodingTask, language: String?, ...)` — `.transcribe` / `.translate`
- SPM: `https://github.comargmaxinc/WhisperKit`, product `WhisperKit`, **pinned 1.1.0**
- Model name: `openai_whisper-small` (confirmed in v1.1.0 `Models.swift`)
- Platforms: iOS 16+ → spec uses `deploymentTarget: iOS: "16.0"`

---

## 5. CI (GitHub Actions)

- **File:** `g2local/.github/workflows/build.yml`, runner **macos-15**, timeout 45 min
- **Triggers:** `push` to main + `workflow_dispatch` + `schedule` (Mondays 06:30 UTC —
  fresh weekly build so the 7-day sideload expiry is never a blocker)
- **Steps:** checkout → show toolchain → `brew install xcodegen` → `xcodegen generate`
  → `xcodebuild -resolvePackageDependencies` → `xcodebuild archive` (unsigned)
  → package ipa → `upload-artifact` (name `G2Local-ipa`, retention 30 days)
- **Artifact:** `G2Local-v$(date +%Y%m%d)-$(git sha).ipa`
- **Self-reporting:** the archive step captures the log to a file and, on failure,
  emits every compiler `error:` as a GitHub `::error::` annotation (readable
  without auth). This is how the real errors were finally found.

### ⚠️ THE #1 GOTCHA (cost hours — do NOT repeat)
**Windows CRLF line endings corrupted the YAML.** A single CRLF on the
`if: ${{ secrets... }}` line made the *entire workflow invalid* → GitHub showed
"Invalid workflow file: Unrecognized named-value" → every run instantly red with
**0 jobs, no log, no annotations**. This looked like "Actions disabled" but was
never that.

**Fixes in place:**
1. `git config core.autocrlf false` (local)
2. `.gitattributes` with `* -text eol=lf` (repo-wide LF enforcement)
3. **Verify 0 CRLF before pushing any workflow file:**
   ```powershell
   $b=[IO.File]::ReadAllBytes("build.yml"); $c=0
   for($i=1;$i -lt $b.Length;$i++){ if($b[$i]-eq 10 -and $b[$i-1]-eq 13){$c++} }
   "CRLF=$c"   # must be 0
   ```

### CI log access (restricted)
- The cached GitHub token on this PC is a **fine-grained token** — it can `git
  push`/`ls-remote` but returns **401/404** on `api.github.com` (artifacts,
  secrets, /user). So: **cannot** download artifacts or set repo secrets with it.
- Unauthenticated API works for: run list, jobs, check-runs, annotations.
- Unauthenticated does NOT work for: artifact download, logs, secrets.
- **Annotations ARE readable unauthenticated** → that's why the workflow was made
  to self-report errors as `::error::` annotations.

---

## 6. HOW TO FINISH: sideload the `.ipa` (pick one)

### Option A — Throwaway US Apple ID → AltStore (recommended)
All on-phone, ~15 min. Main Canadian Apple ID stays untouched.

1. **Sign out of App Store only** (NOT iCloud): Settings → your name →
   Media & Purchases → Sign Out.
2. **Create burner US Apple ID:** Settings → Media & Purchases → Sign In →
   "Don't have or forget Apple ID?" → Create Your Apple ID → country
   **United States**. Canadian phone number works for the verification text.
   When asked for payment, pick **None** (if not offered at creation, it
   usually appears on first App Store sign-in under "verify payment").
3. **Install AltStore:** sign into App Store with the new US ID → search
   **AltStore** → install. Then sign back into the main Canadian ID.
4. **Get the `.ipa` on the phone:** Safari → `github.com/raxip11/g2local/actions`
   → newest **green** run → scroll to **Artifacts** → tap **`G2Local-ipa`** →
   in Files, tap the zip → **Extract** → long-press `G2Local-*.ipa` → Share →
   **Move to iCloud Drive**.
5. **Install G2 Local:** open AltStore → sign in with the **main Apple ID** →
   it finds the ipa in iCloud Drive → **Install**.
6. **First launch:** shows "loading model (first time downloads it)…" →
   downloads ~500 MB once → **"ready"** (green dot). After that it's fully
   offline. AltStore auto-refreshes the 7-day signature weekly, on-phone.

> **If re-picking up later and the artifact expired (30-day retention):**
> just push a trivial commit (or hit "Re-run" / "workflow_dispatch") to get a
> fresh green build + new artifact.

### Option B — Web ad-hoc signer (ksign.app / esign.pro)
Phone Safari only, no US account, but you pay per sign.
1. Download the `.ipa` from the green run's artifact (as in A.4, but keep it in
   Files, don't need iCloud Drive).
2. Safari → `ksign.app` (or `esign.pro`) → log in → upload the `.ipa`.
3. It returns a Safari install link → tap it → iOS prompts to install.
4. **Enable Developer Mode** (first launch): Settings → Privacy & Security →
   Developer Mode → ON → restart → Trust the developer.
5. Repeat upload every 7 days (or pay for their auto-renew).

### After install — wire up the G2
- Open the G2 Voice webview in Even Hub with:
  `https://oaksthepomchi.com/voice/v4.html?asr_base=http://127.0.0.1:8321`
- Audio now goes to the phone's local WhisperKit instead of the cloud.
- Keep the G2 Local app open (or its heartbeat on) so 127.0.0.1:8321 stays up.

---

## 7. Related: the cloud G2 Voice stack (already live, for reference)

- **Webview:** `https://oaksthepomchi.com/voice/v4.html` (FR↔EN, TALK button)
- **Cloud ASR:** faster-whisper behind pm2 app **`g2-asr`**, port 8765
  - endpoint `https://oaksthepomchi.com/voice/asr`, health `/voice/asr/health`
  - token file `/home/debian/g2-asr/.token`, script `/home/debian/g2-asr/asr_server.py`
- **Web root:** `/home/debian/g2-voice-webroot/voice/`
- **Server:** `debian@192.99.144.204` (SSH key `C:\Users\olamaman\.ssh\openclaw-server`)
- If a server-side deploy of the ipa is ever wanted, the dir would be
  `/home/debian/g2-voice-webroot/voice/g2local/` (under the SPA root; nginx
  `try_files` means a 200 does not prove the file exists — verify with a
  ranged/`stat` check).

---

## 8. Quick resume checklist

- [ ] Decide Option A (US burner ID → AltStore) vs B (web signer)
- [ ] Get `G2Local-v20260908-ca915f8.ipa` from the green run's artifact onto the iPhone
- [ ] Sign + install with the chosen method
- [ ] First launch: let the ~500 MB model download, confirm **"ready"**
- [ ] Point the G2 webview at `?asr_base=http://127.0.0.1:8321`
- [ ] Test end-to-end offline transcription (FR + EN)
- [ ] (Optional) Add a CI auto-deploy of the ipa to the server once CI secrets
      can be set (currently blocked by the restricted fine-grained token)
- [ ] (Optional) Clean up `smoke.yml` (was a diagnostic)

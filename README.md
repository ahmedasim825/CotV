# Milo

A prayer and productivity app with an assistant built into it: computed
prayer times, a timeline that blocks out each prayer window, tasks, habits,
a journal, study sessions against a timer, and **Milo** — which answers by
voice or text, routes between two models, remembers what you have told it,
and can drive a Windows PC.

Two targets from one codebase:

- **iOS** (iPhone 14 Pro, iPadOS), sideloaded with SideStore/AltStore
- **Windows** desktop, installed from an MSIX package

Both are built by the same workflow (`.github/workflows/build.yml`), gated on
one `flutter analyze` + `flutter test` job, so a change cannot land green on
one platform while breaking the other.

## Milo

Milo takes a request — typed, or spoken into the microphone — strips the
wake word ("Milo", "Hey Milo"), and routes it:

| Route | Model | When |
|---|---|---|
| Instant | Groq `qwen/qwen3.8-27b` | short commands and lookups |
| Deep | Gemini `gemini-2.5-flash` | medical questions, research, planning, anything long |
| PC | the Windows agent | anything aimed at the laptop |

Clinical terms are checked first and are not overridable by length — "is
40mg amlodipine safe" is five words and is not a question to answer from
the model picked for speed. Everything else goes to Groq unless a synthesis
verb, a research phrase, or more than 22 words says otherwise.

Speech is an input path, not a second assistant. The transcript enters the
same pipeline a typed message does — so a spoken "open Spotify on my PC" and
a typed one cannot drift apart in behaviour, and the wake word is stripped
the same way for both.

Two transcribers, and the choice between them is not a preference:

- **Faster-Whisper** (`base.en`, CTranslate2, int8) inside the PC agent,
  whenever it is running. The recording stays on a machine you own.
- **Groq** `whisper-large-v3-turbo` otherwise — and always on iOS, which has
  no agent. Without it there would be no voice input on the phone at all.

The agent is tried rather than probed: a reachability check before every
recording would add a round trip to the path the user is waiting on, and
would still be a guess by the time the real request went out.

Replies are read aloud by **Kokoro 82M** (`af_heart`, ONNX) in the same
agent on Windows, and by `AVSpeechSynthesizer` on iOS, which is what puts
Apple's neural voices (Ava, Zoe) within reach — nothing in that API
distinguishes a neural voice from a compact one except its name. Kokoro
synthesises and plays on the PC rather than streaming audio back: on
Windows the app and the agent are the same machine. When Kokoro is not
installed the Windows OS voice reads the line instead, which sounds nothing
like `af_heart` — that difference is the usual reason to think TTS is
"broken" when it is merely unconfigured.

### Waking Milo

Two triggers, both matched on device, both opening the same capture:

- **The wake word**, spotted by a sherpa-onnx zipformer keyword model.
- **A clap**, recognised by shape rather than by a model — a step of 8x
  over the idle room inside one 20ms frame, above an absolute floor, that
  then decays to a third of its peak within three frames. All three tests
  are needed: the rise alone fires on a shout, the level alone fires on
  music, and the decay is what actually separates a clap from a door. See
  `ClapDetector` in `lib/src/services/milo/wake_word_listener.dart`.

Nothing leaves the machine until one of them fires.

The composer has one button rather than three. An empty box can only offer
the microphone, a filled one can only offer send, and while either is in
flight the only thing left to do is stop it. While recording, a ring around
it tracks input level — that is the only thing distinguishing "listening and
hearing you" from a dead microphone, and without it the difference surfaces
only after the request has already failed.

Nothing spoken is kept: the recording lives in a temp file between the two
taps and is deleted as soon as its bytes have been uploaded.

The routing rail on each answer shows which engine ran **and the rule that
chose it**, so a bad route is distinguishable from a bad answer.

Model ids go stale. Both of the originally specified ones,
`llama-3.1-8b-instant` and `gemini-2.0-flash`, are retired. To see what a key
can actually reach today, ask each provider:

```bash
curl -H "Authorization: Bearer $GROQ_KEY" https://api.groq.com/openai/v1/models
```

```bash
curl -H "x-goog-api-key: $GEMINI_KEY" https://generativelanguage.googleapis.com/v1beta/models
```

`dart run tool/live_check.dart` drives both engines against the live APIs
and reports which model each actually reached.

### Keys

Milo needs a [Groq key](https://console.groq.com/keys) and/or a
[Gemini key](https://aistudio.google.com/apikey).

The Gemini one must be an **AI Studio** key, which starts `AIza`. A Vertex
or gcloud OAuth token will not work: the REST endpoint takes an API key in
`x-goog-api-key`, not a bearer token, and refuses one with a 404 that reads
like a missing model rather than a rejected credential.

Two ways in, and stored values always win:

1. **On device** — Milo → gear → Milo settings. Held in the iOS Keychain, or
   Windows Credential Manager. This is the normal path.
2. **At build time** — a gitignored `milo_keys.json` in the repo root:

   ```json
   {
     "MILO_GROQ_API_KEY": "gsk_...",
     "MILO_GEMINI_API_KEY": "AIza...",
     "MILO_PC_HOST": "127.0.0.1:8765",
     "MILO_PC_TOKEN": "..."
   }
   ```

   ```bash
   flutter build windows --release --dart-define-from-file=milo_keys.json
   ```

   Convenient for a personal build, but a `--dart-define` is recoverable from
   the binary with `strings`. CI never injects keys for that reason: a build
   artifact from a public repository is downloadable by anyone.

### The PC bridge

`tools/milo_pc_agent/` is a small FastAPI server that opens applications,
files, folders and URLs on the Windows machine and presses media keys. See
its [README](tools/milo_pc_agent/README.md) — in particular the difference
between restricted and open mode, and what open mode means for the token.

The Windows build talks to it on `127.0.0.1`; the phone talks to it on the
LAN address. Same agent, same token.

## Study

Subjects, a timer, and a log of what was actually studied.

The timer is derived from the clock, never decremented. A session stores the
instant it reaches zero, so backgrounding the app for ten minutes costs ten
minutes — a tick counter would drift, and would stop advancing entirely
while the app is in the background, which is exactly when a 25-minute timer
matters.

It is also persisted rather than held in memory, which covers the case that
is easy to miss: the app is killed mid-session. The OS notification still
fires, because it was handed to the system when the session started, so the
user is told their session ended. On the next launch the stored session is
reconciled — one already past its end is logged and cleared. The log's id is
derived from the session rather than generated, so reconciling the same
record twice overwrites one entry instead of appending a second.

A session logs the minutes **actually** studied, not the length the timer
was set to. Ending a 45-minute block after 30 records 30.

### Milo and study

Milo can start and stop a timer:

> set a study timer for physiology for 45 mins

Study is the only thing Milo gets *tools* for. PC control stays on the
deterministic parser — it works, it is tested, and it needs no model round
trip. Study actions need a subject and a duration pulled out of prose, which
is the one job a parser would have to guess at.

The receipt under an answer says what the app did, in the app's own words.
The model is asked to describe an action it did not carry out and cannot
verify; if the two ever disagree, the receipt is the true record.

"start" is both an app-launch verb and the verb for a study block, so the PC
parser refuses phrases carrying this app's own nouns — timer, session,
study, revision, pomodoro. "start a physiology timer" is study; "start
Obsidian" is still the PC. "start anatomy" is genuinely ambiguous with
launching an app called Anatomy and goes to the PC; say "start studying
anatomy".

## Memory

Milo's panel still opens clean on every launch — a three-day-old exchange
scrolled above today's is noise. Underneath, every completed turn is written
to a durable transcript, and two things read it:

- the **recall window**, the last dozen turns, put into the system prompt so
  a new session is not starting from nothing. Turns already being sent as
  live history are excluded, so nothing is said twice.
- the **summary**, distilled by Gemini in the background once the transcript
  passes twenty turns, and rewritten only when it has grown since the last
  run. It never blocks a turn, and a failure leaves the previous summary
  intact — Gemini returns 503s often enough that a blank memory would
  otherwise be a routine outcome.

Clearing the panel does not erase either. That is "start a fresh
conversation", not "forget me".

## Building

```bash
flutter pub get
flutter analyze
flutter test
```

### Windows

Needs Visual Studio's C++ toolchain — **not** VS Code, which is a different
product. Install the compiler without the IDE:

```bash
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

Then:

```bash
flutter build windows --release --dart-define-from-file=milo_keys.json
dart run msix:create --build-windows false --install-certificate false   --certificate-path certs/prayer_lockout.pfx   --certificate-password "$(cat certs/password.txt)"
```

That writes `Milo.msix` to `build/windows/x64/runner/Release/`.

### Signing

Windows will not install an MSIX whose signing certificate it does not
trust, and it takes the package's `Publisher` from the certificate's subject
rather than from `pubspec.yaml` — so the certificate decides the app's
identity, not the config.

Do **not** sign with the certificate bundled in the `msix` package. Its
private key ships publicly inside that package, so trusting it would let any
package anyone signed with the same key install on this machine.

Generate your own once (no admin needed), into the gitignored `certs/`:

```powershell
$pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 24 | % {[char]$_})
[IO.File]::WriteAllText("certs\password.txt", $pw, (New-Object Text.UTF8Encoding $false))
$cert = New-SelfSignedCertificate -Type Custom -Subject "CN=Ahmed Asim" `
  -KeyUsage DigitalSignature -CertStoreLocation "Cert:\CurrentUser\My" `
  -NotAfter (Get-Date).AddYears(5) `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3","2.5.29.19={text}Subject Type:End Entity")
Export-PfxCertificate -Cert $cert -FilePath "certs\prayer_lockout.pfx" `
  -Password (ConvertTo-SecureString $pw -Force -AsPlainText)
Export-Certificate -Cert $cert -FilePath "certs\prayer_lockout.cer" -Type CERT
```

Write the password with `UTF8Encoding $false`, not `Set-Content -Encoding
utf8`: PowerShell 5.1 prepends a BOM, and signtool then rejects the password.

Trust it once, elevated:

```powershell
Import-Certificate -FilePath "certs\prayer_lockout.cer" -CertStoreLocation Cert:\LocalMachine\TrustedPeople
```

After that every rebuild installs with no elevation:

```powershell
Add-AppxPackage -Path build/windows/x64/runner/Release/Milo.msix
```

`identity_name` in `pubspec.yaml` and the certificate subject are what Windows
uses to tell one installed app from another. Change either and the next build
installs as a separate app instead of upgrading this one.

### iOS

```bash
flutter build ios --no-codesign --release
```

CI packages the result as an unsigned `.ipa` for SideStore. Grab it from the
run's artifacts.

**Minimum iOS is 16.0**, raised from 15.0 because App Intents are a 16+
API and `flutter_app_intents` refuses to resolve below it — CocoaPods fails
the build outright rather than degrading. The target device (iPhone 14 Pro)
shipped with iOS 16, so this costs nothing here, but it does drop iOS 15
devices.

**The App Intents are unverified.** `ios/Runner/AppDelegate.swift` declares
`StartStudyIntent` and `StopStudyIntent` — iOS discovers intents by scanning
the compiled binary, so they have to exist as static Swift, and
`flutter_app_intents` generates none of it. That file was written on
Windows, where no Apple toolchain exists. CI proves it compiles. Nobody has
run it on an iPhone, and "it compiles" is not "Siri starts a timer". The
Shortcuts row in Settings and the `shortcuts://` link are equally untested
on device.

Three identifiers have to stay in step by hand, because Swift cannot read a
Dart constant: the strings in `AppDelegate.swift`, `StudyAppIntents` in
`lib/src/services/study_app_intents.dart`, and the tool names in
`MiloTools`. They are all `start_study_timer` / `stop_study_timer`. The
default duration is duplicated too — `MiloTools.defaultMinutes` and the
`?? 25` in the Swift.

## Platform differences

| Feature | iOS | Windows |
|---|---|---|
| Prayer times, timeline, tasks, habits, journal | yes | yes |
| Milo, both engines | yes | yes |
| Milo PC control | over the LAN | over loopback |
| Voice commands | yes | yes |
| App lock | Face ID / Touch ID | Windows Hello |
| Notifications | yes | yes |
| Calendar sync | yes | no — `device_calendar` is iOS/Android only, so the section is hidden |
| Study, timer, logs | yes | yes |
| Study timer notification | yes | yes — needs the full AUMID, see below |
| Siri / Shortcuts for study | written, unverified on device | no — the settings row is hidden |

The calendar exists for iOS Shortcuts to key off, so it has nothing to do on
desktop. The timeline still draws lockout blocks there: those come from
`CalendarSyncService.buildWindows`, which is pure computation.

Windows addresses a toast to an app *identity*, not to a running process, so
`NotificationService.windowsSettings` has to declare the full AUMID —
`<identity_name>_<publisher hash>!<application id>`. The application id comes
from `name:` in `pubspec.yaml` (`cotv`), not from the renamed executable, so
the value is `AhmedAsim.Milo_13g40ee8f0jhw!cotv`. `AhmedAsim.Milo` alone
addresses nothing and the toast is dropped silently. Read it back from the
installed package rather than deriving it:

```powershell
Get-StartApps | Where-Object { $_.Name -eq "Milo" }
```

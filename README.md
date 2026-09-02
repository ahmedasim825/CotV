# Prayer Lockout

A prayer and productivity app: computed prayer times, a timeline that blocks
out each prayer window, tasks, habits, a journal, and **Milo** — an assistant
that routes between two models and can drive a Windows PC.

Two targets from one codebase:

- **iOS** (iPhone 14 Pro, iPadOS), sideloaded with SideStore/AltStore
- **Windows** desktop, installed from an MSIX package

Both are built by the same workflow (`.github/workflows/build.yml`), gated on
one `flutter analyze` + `flutter test` job, so a change cannot land green on
one platform while breaking the other.

## Milo

Milo takes a request, strips the wake word ("Milo", "Hey Milo"), and routes it:

| Route | Model | When |
|---|---|---|
| Instant | Groq `qwen/qwen3.8-27b` | short commands and lookups |
| Deep | Gemini `gemini-3.6-flash` | planning, summaries, anything with constraints |
| PC | the Windows agent | anything aimed at the laptop |

The routing rail on each answer shows which engine ran **and the rule that
chose it**, so a bad route is distinguishable from a bad answer.

Model ids go stale. Both of the originally specified ones,
`llama-3.1-8b-instant` and `gemini-2.0-flash`, are retired. To see what a key
can actually reach today, ask each provider:

```bash
curl -H "Authorization: Bearer $GROQ_KEY" https://api.groq.com/openai/v1/models
curl -H "x-goog-api-key: $GEMINI_KEY" https://generativelanguage.googleapis.com/v1beta/models
```

### Keys

Milo needs a [Groq key](https://console.groq.com/keys) and/or a
[Gemini key](https://aistudio.google.com/apikey). Two ways in, and stored
values always win:

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
dart run msix:create --build-windows false
```

That writes `PrayerLockout.msix` to `build/windows/x64/runner/Release/`.
It is signed with a generated test certificate, so the certificate has to be
trusted once before Windows will install the package — `msix:create` offers
to do that, or install the `.cer` beside it into **Local Machine → Trusted
People** by hand.

`identity_name` and `publisher` in `pubspec.yaml` are what Windows uses to
tell one installed app from another. Changing either makes the next build
install as a separate app instead of upgrading this one.

### iOS

```bash
flutter build ios --no-codesign --release
```

CI packages the result as an unsigned `.ipa` for SideStore. Grab it from the
run's artifacts.

## Platform differences

| Feature | iOS | Windows |
|---|---|---|
| Prayer times, timeline, tasks, habits, journal | yes | yes |
| Milo, both engines | yes | yes |
| Milo PC control | over the LAN | over loopback |
| App lock | Face ID / Touch ID | Windows Hello |
| Notifications | yes | yes |
| Calendar sync | yes | no — `device_calendar` is iOS/Android only, so the section is hidden |

The calendar exists for iOS Shortcuts to key off, so it has nothing to do on
desktop. The timeline still draws lockout blocks there: those come from
`CalendarSyncService.buildWindows`, which is pure computation.

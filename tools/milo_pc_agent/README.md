# Milo PC agent

A small HTTP server that lets Milo, in the Prayer Lockout app, drive this
Windows machine over the local network: open applications, files, folders and
URLs, and press media and volume keys.

## Setup

```powershell
cd tools\milo_pc_agent
py -m pip install -r requirements.txt
copy milo_agent.example.toml milo_agent.toml
```

Generate a token and paste it into `milo_agent.toml`:

```powershell
py -c "import secrets; print(secrets.token_urlsafe(32))"
```

Decide which mode you want (see **Modes** below), then run it:

```powershell
py milo_pc_agent.py
```

Find this machine's LAN address with `ipconfig` (the IPv4 address on your
Wi-Fi adapter), then in the app open **Milo → gear → Milo settings** and
enter:

- **Agent address** — `192.168.1.20:8765`, using your own address
- **Agent token** — the token from `milo_agent.toml`

Check it is reachable from the phone's browser first: `http://<address>/health`
should return `{"ok": true, ...}`.

To start it with Windows, put a shortcut to `pythonw milo_pc_agent.py` in the
folder that opens from `Win+R` → `shell:startup`.

## Modes

Set under `[security]` in `milo_agent.toml`.

**Restricted** (`allow_any_app = false`, `allow_any_path = false`) — the
shipped default. Only what `[apps]` and `[paths]` name can be opened, and
literal paths must resolve inside `allowed_roots`. A request cannot make the
agent run something you did not list.

**Open** (`true`, `true`) — the agent will open anything on the machine: any
executable by name or path, any file or folder on any drive, any URL. An app
name resolves the way `Win+R` resolves it, so nothing needs to be listed
first.

In open mode the `[apps]` table stops being a whitelist and becomes a set of
pins, for names Windows would not resolve on its own ("VS Code" is two words;
"terminal" is really `wt.exe`). **Do not pin an app you have not installed** —
the pin wins over resolution, so it would keep failing after you install it.

### How a name is resolved in open mode

In order, first hit wins:

1. an `[apps]` pin
2. a literal path that exists
3. `PATH` (`notepad`, `explorer`, `code`)
4. the registry's `App Paths` key — the same one `Win+R` uses, which is how
   `spotify` finds Spotify without a full path
5. the shell's `start`, which covers Store apps, protocol handlers and URLs

## What Milo can send

| Phrase | Endpoint | What travels |
|---|---|---|
| "Open Spotify on my PC" | `/open-app` | `{"app": "Spotify"}` |
| "Launch VS Code on the laptop" | `/open-app` | `{"app": "VS Code"}` |
| "Open the study folder" | `/open-file` | `{"path": "study"}` |
| "Open C:\Users\me\notes on my pc" | `/open-file` | `{"path": "C:\\Users\\me\\notes"}` |
| "Open https://groq.com" | `/open-file` | `{"path": "https://groq.com"}` |
| "Play media on laptop" | `/system-control` | `{"control": "play_pause"}` |
| "Turn it up on my laptop" | `/system-control` | `{"control": "volume_up"}` |
| "Lock the computer" | `/system-control` | `{"control": "lock_workstation"}` |

Names travel as spoken; the agent does the normalising, so the phone and the
PC never have to agree on a table.

App and media phrases must name the machine ("on my PC", "on the laptop") —
otherwise "open settings" would leave the app and "pause" in ordinary
conversation would stop the music. Folders, literal paths and explicit URLs
do not need it, since the phone has no `D:` drive to confuse them with.

## Security

The agent is only as safe as the network it sits on. Run it on a home Wi-Fi
you control, not a café or campus network.

- **Bearer token on every endpoint** except `/health`, compared in constant
  time. `/health` returns nothing but "I am up", so it cannot be used to
  enumerate what is installed.
- **No shell for the ordinary paths.** Applications start via
  `subprocess.Popen` with an argument list and `shell=False`; files and
  folders open via `os.startfile`. The one exception is the final fallback
  in open mode, which uses `cmd /c start` because that is the only way to
  reach Store apps and protocol handlers; the target is passed as its own
  argv entry rather than concatenated into a command string.
- **`milo_agent.toml` is gitignored** because it holds the shared secret.
  Keep it that way.

**In open mode, the token is the only control.** Anyone who can reach the
port and holds the token can start arbitrary programs on this PC. That is the
point of the mode and it is a reasonable trade for a personal tool on your own
network — but it means the token should be one you generated, never
committed, and the machine should not be on a network you do not control. Turn
open mode off before taking the laptop somewhere public, or stop the agent.

Plain HTTP is deliberate: the agent has no certificate a phone would trust,
and a self-signed one trains you to click through warnings. The token is what
authenticates; the LAN is the trust boundary.

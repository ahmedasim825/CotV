# Milo PC agent

A small HTTP server that lets Milo, in the Prayer Lockout app, open an
application, reveal a folder, or press a media key on this Windows machine
over the home Wi-Fi.

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

Then edit the `[apps]` and `[paths]` tables to match this PC, and run it:

```powershell
py milo_pc_agent.py
```

It prints the port it is listening on. Find this machine's LAN address with
`ipconfig` (the IPv4 address on your Wi-Fi adapter), then in the app open
**Milo → gear → Milo settings** and enter:

- **Agent address** — `192.168.1.20:8765`, using your own address
- **Agent token** — the token from `milo_agent.toml`

Check it is reachable from the phone's browser first: `http://<address>/health`
should return `{"ok": true, ...}`.

To start it with Windows, put a shortcut to `pythonw milo_pc_agent.py` in the
folder that opens from `Win+R` → `shell:startup`.

## What Milo can send

| Phrase | Endpoint | What travels |
|---|---|---|
| "Open Spotify on my PC" | `/open-app` | `{"app": "spotify"}` |
| "Open the study folder" | `/open-file` | `{"path": "study"}` |
| "Open D:\Study\Anatomy on my pc" | `/open-file` | `{"path": "D:\\Study\\Anatomy"}` |
| "Play media on laptop" | `/system-control` | `{"control": "play_pause"}` |
| "Turn it up on my laptop" | `/system-control` | `{"control": "volume_up"}` |
| "Lock the computer" | `/system-control` | `{"control": "lock_workstation"}` |

App and folder names arrive as slugs: "VS Code" becomes `vs_code`. Add a new
one by adding that key to `[apps]` or `[paths]` — nothing in the phone app
needs to change.

Media and app phrases must name the machine ("on my PC", "on the laptop").
Folders do not, since the phone has no `D:` drive to confuse them with.

## Security

The agent is only as safe as the network it sits on. Run it on a home Wi-Fi
you control, not a café or campus network.

- **Bearer token on every endpoint** except `/health`, compared in constant
  time. `/health` returns nothing but "I am up", so it cannot be used to
  enumerate what is installed.
- **The phone sends keys, not commands.** `/open-app` takes an allowlist key
  and looks the executable up in `milo_agent.toml`; `/system-control` takes a
  control name from a fixed table. Neither accepts a path or a command line,
  so a request cannot make this process run an arbitrary program — and
  neither can anyone else who reaches the port.
- **Literal paths are bounded.** `/open-file` accepts a real path, but
  resolves it first and refuses anything outside `allowed_roots`, so
  `D:/Study/../Windows` does not escape. Leave `allowed_roots` empty to
  refuse literal paths entirely and allow only the `[paths]` aliases.
- **No shell.** Applications start via `subprocess.Popen` with an argument
  list and `shell=False`; paths open via `os.startfile`, which uses the
  shell's file association rather than a command interpreter.
- **`milo_agent.toml` is gitignored** because it holds the shared secret.
  Keep it that way.

Plain HTTP is deliberate: the agent has no certificate a phone would trust,
and a self-signed one trains you to click through warnings. The token is what
authenticates; the LAN is the trust boundary.

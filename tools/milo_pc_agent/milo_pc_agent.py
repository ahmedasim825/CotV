"""Milo's Windows-side agent.

A small HTTP server the Prayer Lockout app calls over the local network to
open applications, files, folders and URLs on this PC, and to press media
and volume keys.

Two modes, chosen in `milo_agent.toml`:

  * **Open mode** (`allow_any_app` / `allow_any_path` = true). The agent will
    open anything on the machine: any executable by name or path, any file or
    folder on any drive, any URL. Names resolve the way the Start menu
    resolves them, so "open Spotify on my PC" works without the agent being
    told where Spotify lives.

  * **Restricted mode** (both false, the shipped default). Only the entries
    in `[apps]` and `[paths]` can be opened, and literal paths must resolve
    inside `allowed_roots`.

In open mode the bearer token is the only thing between this machine and
anyone who can reach the port. That is a deliberate trade for a personal
tool on a network you control — see the README. Run it on your own Wi-Fi.

Run it:

    py -m pip install -r requirements.txt
    copy milo_agent.example.toml milo_agent.toml   # then edit it
    py milo_pc_agent.py
"""

from __future__ import annotations

import ctypes
import hmac
import logging
import os
import re
import shutil
import subprocess
import sys
import tomllib
import winreg
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field
import uvicorn

from milo_speech import Speaker, SpeechUnavailable, Transcriber

LOG = logging.getLogger("milo_pc_agent")

CONFIG_PATH = Path(__file__).with_name("milo_agent.toml")

# Keeps a launched app from flashing a console window on the desktop.
_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------


class Config:
    """The parsed `milo_agent.toml`."""

    def __init__(self, raw: dict[str, Any]) -> None:
        server = raw.get("server", {})
        self.host: str = server.get("host", "0.0.0.0")
        self.port: int = int(server.get("port", 8765))
        self.token: str = server.get("token", "")

        security = raw.get("security", {})
        # Default to the restricted posture: someone who copies the example
        # config and forgets to read it should not end up serving arbitrary
        # process launch to their whole subnet.
        self.allow_any_app: bool = bool(security.get("allow_any_app", False))
        self.allow_any_path: bool = bool(security.get("allow_any_path", False))

        self.apps: dict[str, str] = {
            slug(key): value for key, value in raw.get("apps", {}).items()
        }

        paths = dict(raw.get("paths", {}))
        self.allowed_roots: list[Path] = [
            expand(root) for root in paths.pop("allowed_roots", [])
        ]
        self.paths: dict[Path, Any] = {
            slug(key): expand(value) for key, value in paths.items()
        }

        # Speech is entirely optional, so every value here has a default and
        # nothing validates the paths at load time — the endpoints report a
        # missing model when they are actually called, which is the only
        # moment the user can do anything about it.
        speech = raw.get("speech", {})
        self.whisper_model: str = speech.get("whisper_model", "base.en")
        self.whisper_compute: str = speech.get("whisper_compute_type", "int8")
        self.kokoro_model: Path = beside_agent(
            speech.get("kokoro_model", "models/kokoro-v1.0.onnx")
        )
        self.kokoro_voices: Path = beside_agent(
            speech.get("kokoro_voices", "models/voices-v1.0.bin")
        )
        self.kokoro_voice: str = speech.get("kokoro_voice", "af_heart")
        self.kokoro_speed: float = float(speech.get("kokoro_speed", 1.0))

    @classmethod
    def load(cls, path: Path) -> "Config":
        if not path.exists():
            raise SystemExit(
                f"No config at {path}.\n"
                "Copy milo_agent.example.toml to milo_agent.toml and edit it."
            )
        with path.open("rb") as handle:
            config = cls(tomllib.load(handle))

        if not config.token or config.token.startswith("replace-me"):
            raise SystemExit(
                f"Set a real token in {path}. Generate one with:\n"
                '  py -c "import secrets; print(secrets.token_urlsafe(32))"'
            )
        return config


def expand(value: str) -> Path:
    """`~/Documents` and `%USERPROFILE%\\Documents` both become real paths."""
    return Path(os.path.expandvars(str(value))).expanduser()


def beside_agent(value: str) -> Path:
    """[value], with a relative path taken as relative to this script.

    Model files are configured relative to the agent rather than to the
    working directory, because the agent is normally started from a
    shortcut or the Startup folder and the working directory is then
    whatever Windows felt like.
    """
    path = expand(value)
    return path if path.is_absolute() else (Path(__file__).parent / path)


def slug(name: str) -> str:
    """The alias-table key form: "VS Code", "vs-code" and "vs_code" all match."""
    return re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")


# --------------------------------------------------------------------------
# Request bodies
# --------------------------------------------------------------------------


class OpenAppRequest(BaseModel):
    app: str = Field(min_length=1, max_length=260)


class OpenFileRequest(BaseModel):
    path: str = Field(min_length=1, max_length=1024)


class SystemControlRequest(BaseModel):
    control: str = Field(min_length=1, max_length=32)


# --------------------------------------------------------------------------
# Media and system keys
# --------------------------------------------------------------------------

# Virtual-key codes from the Windows SDK's WinUser.h. `keybd_event` is
# deprecated in favour of `SendInput`, but it is still the shortest correct
# way to press a single media key and Windows still honours it.
VK_CODES = {
    "play_pause": 0xB3,  # VK_MEDIA_PLAY_PAUSE
    "next_track": 0xB0,  # VK_MEDIA_NEXT_TRACK
    "previous_track": 0xB1,  # VK_MEDIA_PREV_TRACK
    "volume_up": 0xAF,  # VK_VOLUME_UP
    "volume_down": 0xAE,  # VK_VOLUME_DOWN
    "mute": 0xAD,  # VK_VOLUME_MUTE
}

KEYEVENTF_KEYUP = 0x0002

# How many steps one "turn it up" moves. A single VK_VOLUME_UP is 2% on
# Windows, which is not audible as a change.
VOLUME_STEPS = 5

CONTROL_CONFIRMATIONS = {
    "play_pause": "Play/pause pressed.",
    "next_track": "Skipped to the next track.",
    "previous_track": "Went back a track.",
    "volume_up": "Volume up.",
    "volume_down": "Volume down.",
    "mute": "Mute toggled.",
    "lock_workstation": "Workstation locked.",
}


def press_key(code: int, repeat: int = 1) -> None:
    user32 = ctypes.windll.user32
    for _ in range(repeat):
        user32.keybd_event(code, 0, 0, 0)
        user32.keybd_event(code, 0, KEYEVENTF_KEYUP, 0)


# --------------------------------------------------------------------------
# Resolving what to open
# --------------------------------------------------------------------------


def looks_like_url(value: str) -> bool:
    return bool(re.match(r"^[a-z][a-z0-9+.-]*://", value, re.IGNORECASE))


def app_paths_lookup(name: str) -> str | None:
    """Ask the registry key the Start menu and Win+R use.

    `App Paths` is why typing "spotify" into Run finds Spotify without a
    full path. Consulting it here is what lets the phone say an app's name
    without this agent being told where it lives.
    """
    exe = name if name.lower().endswith(".exe") else f"{name}.exe"
    subkey = r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths" + "\\" + exe
    for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        try:
            with winreg.OpenKey(hive, subkey) as key:
                value, _ = winreg.QueryValueEx(key, "")
        except OSError:
            continue
        if value:
            return str(value).strip('"')
    return None


def launch(argv: list[str]) -> None:
    """Start a process without going through a shell."""
    subprocess.Popen(
        argv, shell=False, close_fds=True, creationflags=_NO_WINDOW
    )


def shell_open(target: str) -> None:
    """Hand `target` to the Windows shell, the way double-clicking would.

    Covers what a bare path cannot: Store apps, protocol handlers, URLs and
    registered application names. `start` is a cmd builtin, so this is the
    one place a command interpreter is involved; the target is passed as a
    separate argv entry rather than concatenated into a command string.
    """
    subprocess.Popen(
        ["cmd", "/c", "start", "", target],
        shell=False,
        close_fds=True,
        creationflags=_NO_WINDOW,
    )


# --------------------------------------------------------------------------
# App
# --------------------------------------------------------------------------

app = FastAPI(title="Milo PC Agent", docs_url=None, redoc_url=None)
CONFIG: Config

# Both hold a model once loaded, so they are built at start-up and load
# lazily. Neither reaches its library or its files until an endpoint is
# actually called, which is what lets the agent run with neither installed.
TRANSCRIBER: Transcriber
SPEAKER: Speaker


class SpeakRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4000)
    voice: str = Field("", max_length=64)


def require_token(request: Request) -> None:
    """Rejects anything without the shared secret.

    Compared with `hmac.compare_digest` so a wrong token takes the same
    time to reject whatever its prefix is.
    """
    header = request.headers.get("authorization", "")
    scheme, _, presented = header.partition(" ")
    if scheme.lower() != "bearer" or not hmac.compare_digest(
        presented, CONFIG.token
    ):
        LOG.warning("Refused %s from %s", request.url.path, request.client)
        raise HTTPException(status_code=401, detail="Bad or missing token.")


@app.get("/health")
def health() -> dict[str, Any]:
    """Unauthenticated, and says nothing but that the agent is up.

    Lets the phone tell "asleep" from "wrong token" without handing an
    unauthenticated caller the app list. The two speech flags are the
    exception, and are safe to expose: they say which optional models are
    installed, not what is on the machine.
    """
    return {
        "ok": True,
        "message": "Milo agent is running.",
        "stt": TRANSCRIBER.model_name,
        "tts": SPEAKER.installed,
    }


# --------------------------------------------------------------------------
# Speech
# --------------------------------------------------------------------------


@app.post("/transcribe", dependencies=[Depends(require_token)])
async def transcribe(request: Request, language: str = "en") -> dict[str, Any]:
    """Turns a recording into text with Faster-Whisper.

    The WAV arrives as the raw request body rather than as a multipart
    upload. That is not a micro-optimisation: a route declaring `UploadFile`
    makes FastAPI raise at *import* time unless `python-multipart` is
    installed, so adding one here would have stopped the agent starting at
    all — taking the PC commands down with it — on any machine that updated
    the agent without reinstalling its requirements.

    The checkpoint and the vocabulary hint are the agent's, not the app's.
    The machine that has to hold the model in memory is the one that should
    choose it, and the hint describes Milo's vocabulary, which is the same
    whichever device is asking. The reply names what actually ran so the app
    is never guessing.
    """
    audio = await request.body()
    if not audio:
        raise HTTPException(status_code=400, detail="No audio in the request.")

    try:
        text = await run_in_threadpool(
            lambda: TRANSCRIBER.transcribe(audio, language=language or "en")
        )
    except SpeechUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except Exception as error:  # noqa: BLE001 - reported, not handled
        LOG.exception("Transcription failed")
        raise HTTPException(status_code=500, detail=str(error)) from error

    LOG.info("Transcribed %d bytes to %d characters", len(audio), len(text))
    return {"ok": True, "text": text, "model": TRANSCRIBER.model_name}


@app.post("/speak", dependencies=[Depends(require_token)])
async def speak(body: SpeakRequest) -> dict[str, Any]:
    """Reads a line aloud through this machine's speakers, with Kokoro."""
    text = body.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Nothing to say.")

    try:
        await run_in_threadpool(
            lambda: SPEAKER.speak(text, voice=body.voice or None)
        )
    except SpeechUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except Exception as error:  # noqa: BLE001 - reported, not handled
        LOG.exception("Synthesis failed")
        raise HTTPException(status_code=500, detail=str(error)) from error

    return {"ok": True, "message": "Speaking."}


@app.post("/speak/stop", dependencies=[Depends(require_token)])
async def speak_stop() -> dict[str, Any]:
    """Silences whatever Kokoro is playing.

    Never fails: this is called when the user has already decided they do
    not want to hear the rest, and reporting that the silence could not be
    arranged would be worse than useless.
    """
    try:
        await run_in_threadpool(SPEAKER.stop)
    except Exception:  # noqa: BLE001 - nothing to recover
        pass
    return {"ok": True, "message": "Stopped."}


@app.post("/open-app", dependencies=[Depends(require_token)])
def open_app(body: OpenAppRequest) -> dict[str, Any]:
    """Starts an application.

    The name arrives as the user said it ("VS Code", "spotify"). An alias in
    `[apps]` always wins, so a specific build can be pinned; otherwise, in
    open mode, the name is resolved the way Windows itself would.
    """
    name = body.app.strip()
    alias = CONFIG.apps.get(slug(name))

    if alias is not None:
        try:
            launch([alias])
        except FileNotFoundError:
            raise HTTPException(
                status_code=502,
                detail=f'"{name}" is configured as {alias}, which is not there.',
            ) from None
        except OSError as error:
            raise HTTPException(
                status_code=502, detail=f"Windows refused to start it: {error}"
            ) from None
        LOG.info("Started %s via alias (%s)", name, alias)
        return {"ok": True, "message": f"{name} is starting on your PC."}

    if not CONFIG.allow_any_app:
        raise HTTPException(
            status_code=404,
            detail=(
                f'"{name}" is not in the agent\'s app list, and open mode is '
                f"off. Add it under [apps] in milo_agent.toml, or set "
                f"allow_any_app = true under [security]."
            ),
        )

    try:
        candidate = expand(name)
        if candidate.exists():
            os.startfile(candidate)
            LOG.info("Started %s by path", candidate)
            return {"ok": True, "message": f"Opened {candidate.name}."}

        on_path = shutil.which(name)
        if on_path:
            launch([on_path])
            LOG.info("Started %s from PATH (%s)", name, on_path)
            return {"ok": True, "message": f"{name} is starting on your PC."}

        registered = app_paths_lookup(name)
        if registered:
            launch([registered])
            LOG.info("Started %s from App Paths (%s)", name, registered)
            return {"ok": True, "message": f"{name} is starting on your PC."}

        # Store apps, protocol handlers and anything else the shell knows
        # how to open but that has no plain executable path.
        shell_open(name)
    except OSError as error:
        raise HTTPException(
            status_code=502, detail=f"Windows refused to start it: {error}"
        ) from None

    LOG.info("Handed %s to the shell", name)
    return {"ok": True, "message": f"Asked Windows to open {name}."}


@app.post("/open-file", dependencies=[Depends(require_token)])
def open_file(body: OpenFileRequest) -> dict[str, Any]:
    """Opens a file, folder or URL — by `[paths]` key, or literally."""
    raw = body.path.strip()

    alias = CONFIG.paths.get(slug(raw))
    if alias is not None:
        return open_resolved(alias)

    if looks_like_url(raw):
        if not CONFIG.allow_any_path:
            raise HTTPException(
                status_code=403,
                detail="This agent is not allowed to open URLs.",
            )
        try:
            os.startfile(raw)
        except OSError as error:
            raise HTTPException(
                status_code=502, detail=f"Windows refused to open it: {error}"
            ) from None
        LOG.info("Opened URL %s", raw)
        return {"ok": True, "message": f"Opened {raw} on your PC."}

    return open_resolved(resolve_literal_path(raw))


def open_resolved(target: Path) -> dict[str, Any]:
    if not target.exists():
        raise HTTPException(
            status_code=404, detail=f"Nothing at {target} on this PC."
        )
    try:
        # startfile hands the path to the shell's file association, which is
        # what opens a directory in Explorer and a document in its app.
        os.startfile(target)
    except OSError as error:
        raise HTTPException(
            status_code=502, detail=f"Windows refused to open it: {error}"
        ) from None

    LOG.info("Opened %s", target)
    return {"ok": True, "message": f"Opened {target.name} on your PC."}


def resolve_literal_path(raw: str) -> Path:
    """Resolves a literal path, applying `allowed_roots` in restricted mode.

    Resolution happens before the check so `D:/Study/../Windows` cannot walk
    out of a permitted root.
    """
    candidate = expand(raw)

    if CONFIG.allow_any_path:
        if not candidate.is_absolute():
            raise HTTPException(
                status_code=404,
                detail=(
                    f'"{raw}" is not a folder name this agent knows, '
                    f"and is not an absolute path."
                ),
            )
        return candidate.resolve()

    candidate = candidate.resolve()

    if not CONFIG.allowed_roots:
        raise HTTPException(
            status_code=404,
            detail=(
                f'"{raw}" is not a known folder, and this agent does not '
                f"accept literal paths. Add it under [paths] in "
                f"milo_agent.toml."
            ),
        )

    for root in CONFIG.allowed_roots:
        if candidate.is_relative_to(root.resolve()):
            return candidate

    raise HTTPException(
        status_code=403,
        detail=f"{candidate} is outside the folders this agent may open.",
    )


@app.post("/system-control", dependencies=[Depends(require_token)])
def system_control(body: SystemControlRequest) -> dict[str, Any]:
    """Presses a media key, steps the volume, or locks the workstation."""
    control = body.control.strip().lower()

    if control == "lock_workstation":
        if not ctypes.windll.user32.LockWorkStation():
            raise HTTPException(
                status_code=502, detail="Windows refused to lock the session."
            )
    elif control in VK_CODES:
        repeat = VOLUME_STEPS if control.startswith("volume_") else 1
        press_key(VK_CODES[control], repeat=repeat)
    else:
        raise HTTPException(
            status_code=404,
            detail=(
                f'"{control}" is not a control this agent knows. Known: '
                f"{', '.join(sorted([*VK_CODES, 'lock_workstation']))}."
            ),
        )

    LOG.info("Ran control %s", control)
    return {"ok": True, "message": CONTROL_CONFIRMATIONS[control]}


def main() -> None:
    global CONFIG, TRANSCRIBER, SPEAKER

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )

    if sys.platform != "win32":
        raise SystemExit(
            "This agent drives Windows APIs (startfile, keybd_event, "
            "LockWorkStation, App Paths) and only runs on Windows."
        )

    CONFIG = Config.load(CONFIG_PATH)
    TRANSCRIBER = Transcriber(
        model=CONFIG.whisper_model,
        compute_type=CONFIG.whisper_compute,
    )
    SPEAKER = Speaker(
        model_path=CONFIG.kokoro_model,
        voices_path=CONFIG.kokoro_voices,
        voice=CONFIG.kokoro_voice,
        speed=CONFIG.kokoro_speed,
    )

    if CONFIG.allow_any_app or CONFIG.allow_any_path:
        # Said loudly on every start: in this mode the token is the only
        # thing standing between the port and arbitrary process launch.
        LOG.warning(
            "OPEN MODE - any app%s can be opened by anyone holding the "
            "token. Keep this machine on a network you trust.",
            " and any file" if CONFIG.allow_any_path else "",
        )

    LOG.info(
        "%d app aliases, %d folder aliases, listening on %s:%d",
        len(CONFIG.apps),
        len(CONFIG.paths),
        CONFIG.host,
        CONFIG.port,
    )
    # Said at start-up rather than discovered on the first spoken turn: the
    # models are a separate download, and "voice does not work" is a much
    # worse way to learn one is missing than a line in the log.
    LOG.info(
        "Speech in: Faster-Whisper %s. Speech out: Kokoro %s.",
        CONFIG.whisper_model,
        "ready" if SPEAKER.installed else f"missing at {CONFIG.kokoro_model}",
    )
    LOG.info("Point Milo at http://<this-pc-lan-ip>:%d", CONFIG.port)

    uvicorn.run(app, host=CONFIG.host, port=CONFIG.port, log_level="warning")


if __name__ == "__main__":
    main()

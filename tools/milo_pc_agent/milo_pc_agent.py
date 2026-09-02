"""Milo's Windows-side agent.

A small HTTP server the Prayer Lockout app calls over the home Wi-Fi to
open an application, reveal a folder, or press a media key on this PC.

Security model, because it is the whole design:

  * Every request must carry `Authorization: Bearer <token>`, compared
    against the token in `milo_agent.toml` in constant time.
  * `/open-app` and `/system-control` take a *key*, never a path or a
    command line. The key is looked up in this machine's config; anything
    not in the table is refused. The phone therefore cannot ask this
    process to run an arbitrary program, and neither can anyone else who
    reaches the port.
  * `/open-file` accepts a literal path as well as a key, but resolves it
    and refuses anything outside `allowed_roots`.
  * Nothing is ever passed to a shell. Applications start through
    `subprocess.Popen` with an argument list, and paths open through
    `os.startfile`, which hands them to the shell's file association
    rather than to a command interpreter.

Run it:

    py -m pip install -r requirements.txt
    copy milo_agent.example.toml milo_agent.toml   # then edit it
    py milo_pc_agent.py

To have it start with Windows, put a shortcut to `pythonw milo_pc_agent.py`
in `shell:startup`.
"""

from __future__ import annotations

import ctypes
import hmac
import logging
import os
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel, Field
import uvicorn

LOG = logging.getLogger("milo_pc_agent")

CONFIG_PATH = Path(__file__).with_name("milo_agent.toml")


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

        self.apps: dict[str, str] = dict(raw.get("apps", {}))

        paths = dict(raw.get("paths", {}))
        self.allowed_roots: list[Path] = [
            expand(root) for root in paths.pop("allowed_roots", [])
        ]
        self.paths: dict[str, Path] = {
            key: expand(value) for key, value in paths.items()
        }

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


# --------------------------------------------------------------------------
# Request bodies
# --------------------------------------------------------------------------


class OpenAppRequest(BaseModel):
    app: str = Field(min_length=1, max_length=64)


class OpenFileRequest(BaseModel):
    path: str = Field(min_length=1, max_length=512)


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
# App
# --------------------------------------------------------------------------

app = FastAPI(title="Milo PC Agent", docs_url=None, redoc_url=None)
CONFIG: Config


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
    unauthenticated caller the app list.
    """
    return {"ok": True, "message": "Milo agent is running."}


@app.post("/open-app", dependencies=[Depends(require_token)])
def open_app(body: OpenAppRequest) -> dict[str, Any]:
    """Starts an application from the `[apps]` allowlist."""
    key = body.app.strip().lower()
    target = CONFIG.apps.get(key)
    if target is None:
        raise HTTPException(
            status_code=404,
            detail=(
                f'"{key}" is not in the agent\'s app list. '
                f"Add it under [apps] in milo_agent.toml."
            ),
        )

    try:
        # A list argument with shell=False: the target is never parsed as a
        # command line, so a config entry cannot smuggle in extra arguments.
        subprocess.Popen([target], shell=False, close_fds=True)
    except FileNotFoundError:
        raise HTTPException(
            status_code=502,
            detail=f'Could not find "{target}" on this PC.',
        ) from None
    except OSError as error:
        raise HTTPException(
            status_code=502, detail=f"Windows refused to start it: {error}"
        ) from None

    LOG.info("Started %s (%s)", key, target)
    return {"ok": True, "message": f"{key} is starting on your PC."}


@app.post("/open-file", dependencies=[Depends(require_token)])
def open_file(body: OpenFileRequest) -> dict[str, Any]:
    """Opens a directory or file, by `[paths]` key or by literal path."""
    raw = body.path.strip()
    target = CONFIG.paths.get(raw.lower())

    if target is None:
        target = resolve_literal_path(raw)

    if not target.exists():
        raise HTTPException(
            status_code=404, detail=f"Nothing at {target} on this PC."
        )

    try:
        # startfile hands the path to the shell's file association, which
        # is what opens a directory in Explorer and a document in its app.
        os.startfile(target)  # noqa: S606 - path is allowlist-checked above
    except OSError as error:
        raise HTTPException(
            status_code=502, detail=f"Windows refused to open it: {error}"
        ) from None

    LOG.info("Opened %s", target)
    return {"ok": True, "message": f"Opened {target.name} on your PC."}


def resolve_literal_path(raw: str) -> Path:
    """Resolves a literal path, refusing anything outside `allowed_roots`.

    Resolution happens before the check so `D:/Study/../Windows` cannot
    walk out of a permitted root.
    """
    if not CONFIG.allowed_roots:
        raise HTTPException(
            status_code=404,
            detail=(
                f'"{raw}" is not a known folder, and this agent does not '
                f"accept literal paths. Add it under [paths] in "
                f"milo_agent.toml."
            ),
        )

    candidate = expand(raw).resolve()
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
    global CONFIG

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )

    if sys.platform != "win32":
        raise SystemExit(
            "This agent drives Windows APIs (startfile, keybd_event, "
            "LockWorkStation) and only runs on Windows."
        )

    CONFIG = Config.load(CONFIG_PATH)
    LOG.info(
        "Serving %d apps and %d folders on %s:%d",
        len(CONFIG.apps),
        len(CONFIG.paths),
        CONFIG.host,
        CONFIG.port,
    )
    LOG.info("Point Milo at http://<this-pc-lan-ip>:%d", CONFIG.port)

    uvicorn.run(app, host=CONFIG.host, port=CONFIG.port, log_level="warning")


if __name__ == "__main__":
    main()

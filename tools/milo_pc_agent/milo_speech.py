"""Milo's local speech models, loaded on demand by the PC agent.

Two models, both running on this machine and neither reachable from
anywhere else:

  * **Faster-Whisper** turns a recording into text. CTranslate2 under the
    hood, int8 on CPU, which is fast enough for a spoken sentence on a
    laptop and needs no GPU.
  * **Kokoro 82M** turns a reply into speech, and plays it here rather than
    sending audio back. On Windows the app and this agent are the same
    machine, so returning a WAV over loopback only to play it through the
    same speakers would be a decode step for nothing.

Both are optional. The agent runs perfectly well without either — it just
answers 503 on the endpoint, and the app falls back: to the OS voice for
speech out, and to saying voice input needs the agent for speech in. That
matters because the model files are a separate download the user has to
make, and an agent that refused to start until they had would be an agent
that stopped working the day it was updated.
"""

from __future__ import annotations

import io
import logging
import tempfile
import threading
import wave
from pathlib import Path
from typing import Any

LOG = logging.getLogger("milo_pc_agent.speech")


class SpeechUnavailable(RuntimeError):
    """A model is not installed, or its files are not where config says.

    Carries a sentence written for the app's error surface rather than a
    stack trace, because that is where it ends up.
    """


# --------------------------------------------------------------------------
# Speech to text
# --------------------------------------------------------------------------


# Whisper decodes toward words it expects, and none of these are in its
# everyday English: "Milo" came back as "Maido" and "Asr" as "ASR". It is
# taken as a stylistic prior rather than a constraint, so it biases those
# spellings without preventing anything else being heard.
#
# Kept to names the decoder cannot guess. Padding it with ordinary words
# would dilute the bias on the ones that need it. It lives here rather than
# in the app because it describes Milo's vocabulary, which is the same
# whichever device is asking.
VOCABULARY_HINT = (
    "Milo. Fajr, Dhuhr, Asr, Maghrib, Isha, adhan, qibla. "
    "Spotify, Chrome, Discord, VS Code, Notepad, Explorer."
)


class Transcriber:
    """Faster-Whisper, loaded on the first recording.

    Lazy on purpose: loading the model costs a few seconds and a few
    hundred megabytes, and an agent started only to open Spotify should
    pay neither.
    """

    def __init__(self, model: str = "base.en", compute_type: str = "int8") -> None:
        self.model_name = model
        self.compute_type = compute_type
        self._model: Any = None
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def _ensure(self) -> Any:
        # Double-checked under the lock: uvicorn serves these handlers from
        # a thread pool, and two recordings arriving together would
        # otherwise each pay for a load.
        if self._model is not None:
            return self._model
        with self._lock:
            if self._model is not None:
                return self._model
            try:
                from faster_whisper import WhisperModel
            except ImportError as error:
                raise SpeechUnavailable(
                    "faster-whisper is not installed. Run "
                    "`py -m pip install -r requirements.txt` beside the agent."
                ) from error

            LOG.info("Loading Faster-Whisper %s (%s)", self.model_name, self.compute_type)
            try:
                self._model = WhisperModel(
                    self.model_name,
                    device="cpu",
                    compute_type=self.compute_type,
                )
            except Exception as error:  # noqa: BLE001 - reported, not handled
                raise SpeechUnavailable(
                    f'Faster-Whisper could not load "{self.model_name}": {error}'
                ) from error
            LOG.info("Faster-Whisper ready")
            return self._model

    def transcribe(
        self,
        audio: bytes,
        *,
        language: str = "en",
        prompt: str | None = None,
    ) -> str:
        """The text in [audio], or the empty string if it held no speech."""
        model = self._ensure()

        # faster-whisper reads a path or a file-like object; the recording
        # arrives as bytes and never needs to touch the disk.
        segments, _info = model.transcribe(
            io.BytesIO(audio),
            language=language,
            initial_prompt=prompt or VOCABULARY_HINT,
            # The recorder already trims trailing silence, so a second VAD
            # pass here mostly costs latency. What it does buy is dropping a
            # recording that is only room tone, which would otherwise decode
            # into a hallucinated sentence.
            vad_filter=True,
            beam_size=1,
        )
        return " ".join(segment.text.strip() for segment in segments).strip()


# --------------------------------------------------------------------------
# Text to speech
# --------------------------------------------------------------------------


class Speaker:
    """Kokoro 82M, synthesised here and played through this machine.

    Playback is `winsound`, which is in the standard library on Windows —
    one less dependency than an audio package, and it already has the two
    behaviours needed: play without blocking the request, and stop whatever
    is playing.
    """

    def __init__(
        self,
        model_path: Path,
        voices_path: Path,
        voice: str = "af_heart",
        speed: float = 1.0,
    ) -> None:
        self.model_path = model_path
        self.voices_path = voices_path
        self.voice = voice
        self.speed = speed
        self._kokoro: Any = None
        self._lock = threading.Lock()
        self._playing: Path | None = None

    @property
    def loaded(self) -> bool:
        return self._kokoro is not None

    @property
    def installed(self) -> bool:
        """Whether the model files are where config says, without loading."""
        return self.model_path.exists() and self.voices_path.exists()

    def _ensure(self) -> Any:
        if self._kokoro is not None:
            return self._kokoro
        with self._lock:
            if self._kokoro is not None:
                return self._kokoro
            try:
                from kokoro_onnx import Kokoro
            except ImportError as error:
                raise SpeechUnavailable(
                    "kokoro-onnx is not installed. Run "
                    "`py -m pip install -r requirements.txt` beside the agent."
                ) from error

            missing = [
                str(path)
                for path in (self.model_path, self.voices_path)
                if not path.exists()
            ]
            if missing:
                raise SpeechUnavailable(
                    "Kokoro's model files are missing: "
                    + ", ".join(missing)
                    + ". Download kokoro-v1.0.onnx and voices-v1.0.bin from "
                    "the kokoro-onnx releases and point [speech] at them."
                )

            LOG.info("Loading Kokoro from %s", self.model_path)
            try:
                self._kokoro = Kokoro(str(self.model_path), str(self.voices_path))
            except Exception as error:  # noqa: BLE001 - reported, not handled
                raise SpeechUnavailable(f"Kokoro could not load: {error}") from error
            LOG.info("Kokoro ready")
            return self._kokoro

    def speak(self, text: str, *, voice: str | None = None) -> None:
        """Synthesises [text] and starts playing it, without waiting for it."""
        import winsound

        kokoro = self._ensure()
        samples, sample_rate = kokoro.create(
            text,
            voice=voice or self.voice,
            speed=self.speed,
            lang="en-us",
        )

        path = self._write_wav(samples, sample_rate)
        self.stop()
        self._playing = path
        winsound.PlaySound(
            str(path),
            winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT,
        )

    def stop(self) -> None:
        """Silences whatever is playing and removes its file."""
        import winsound

        winsound.PlaySound(None, winsound.SND_PURGE)
        previous, self._playing = self._playing, None
        if previous is not None:
            previous.unlink(missing_ok=True)

    def _write_wav(self, samples: Any, sample_rate: int) -> Path:
        """Kokoro's float32 array as a 16-bit WAV winsound can play."""
        import numpy as np

        clipped = np.clip(np.asarray(samples, dtype="float32"), -1.0, 1.0)
        pcm = (clipped * 32767.0).astype("<i2")

        handle = tempfile.NamedTemporaryFile(
            prefix="milo-speak-", suffix=".wav", delete=False
        )
        with handle:
            with wave.open(handle, "wb") as out:
                out.setnchannels(1)
                out.setsampwidth(2)
                out.setframerate(int(sample_rate))
                out.writeframes(pcm.tobytes())
        return Path(handle.name)

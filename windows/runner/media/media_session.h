#ifndef RUNNER_MEDIA_MEDIA_SESSION_H_
#define RUNNER_MEDIA_MEDIA_SESSION_H_

// The Windows media-session bridge, as a C boundary.
//
// Everything behind this header is C++/WinRT, which throws. The runner is
// built with `_HAS_EXCEPTIONS=0` (windows/CMakeLists.txt's
// APPLY_STANDARD_SETTINGS), and the MSVC STL changes shape with that macro, so
// mixing the two across one binary is an ODR hazard. This library is therefore
// a separate CMake target compiled with exceptions on, and nothing from the
// standard library is allowed to cross this boundary — only POD, raw pointers
// and `char*`. That is the whole reason the API below looks like 1995.
//
// The snapshot travels as UTF-8 JSON plus a raw byte buffer for the artwork,
// rather than a struct, so adding a field later does not change the ABI.

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Called when the session, its metadata, its playback state or its timeline
// changes. Fires on a WinRT thread-pool thread, never the UI thread, so the
// implementation must do nothing but wake the caller — see the WM_APP handling
// in flutter_window.cpp.
typedef void (*MediaSessionChanged)(void* user);

// Begins watching the system's media sessions. Returns false when the session
// manager is unavailable, which is expected on a machine with no media
// endpoints and must not be treated as fatal.
bool MediaSessionStart(MediaSessionChanged callback, void* user);

// Stops watching and releases the manager. Safe to call when not started.
void MediaSessionStop(void);

// Copies the latest snapshot out under the library's own lock.
//
// `json` receives UTF-8 metadata; `artwork` receives the raw thumbnail bytes
// and `artwork_len` their length. Either buffer may be null to skip that half.
// Returns false when nothing is playing, when the buffers are too small, or
// when the bridge was never started.
bool MediaSessionSnapshot(char* json, size_t json_capacity, uint8_t* artwork,
                          size_t artwork_capacity, size_t* artwork_len);

// Drives the current session. `command` is one of "playPause", "play", "pause",
// "next", "previous" or "seek"; `argument` carries the target position in
// milliseconds for "seek" and is ignored otherwise. Returns false when there is
// no session or the session refused the command.
bool MediaSessionCommand(const char* command, int64_t argument);

// The system output volume, 0..1. Volume is not part of the media-session API
// at all — these go through Core Audio's IAudioEndpointVolume, which is why
// they are system-wide rather than per-app.
bool MediaSessionGetVolume(float* out_volume);
bool MediaSessionSetVolume(float volume);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RUNNER_MEDIA_MEDIA_SESSION_H_

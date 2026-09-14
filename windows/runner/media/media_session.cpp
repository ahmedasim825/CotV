#include "media_session.h"

// SDK headers first and quietly. This target drops /WX (see its CMakeLists)
// because the C++/WinRT projection does not survive /W4 as an error, but the
// warnings are still noise, so they are silenced around the includes rather
// than project-wide.
#pragma warning(push, 0)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>

#include <endpointvolume.h>
#include <mmdeviceapi.h>
#pragma warning(pop)

#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

namespace media = winrt::Windows::Media::Control;
namespace streams = winrt::Windows::Storage::Streams;

using media::GlobalSystemMediaTransportControlsSession;
using media::GlobalSystemMediaTransportControlsSessionManager;

// The snapshot the UI thread copies out. Rebuilt on the worker whenever
// Windows says anything changed.
struct Snapshot {
  std::string json;
  std::vector<uint8_t> artwork;
  bool playing = false;
};

std::mutex g_lock;
Snapshot g_snapshot;
bool g_has_snapshot = false;

MediaSessionChanged g_changed = nullptr;
void* g_user = nullptr;

std::thread g_worker;
std::atomic<bool> g_running{false};
// Signalled to wake the worker out of its wait so it can exit.
winrt::handle g_stop;

// Held so commands from the UI thread have something to talk to. WinRT media
// session objects are agile, so calling across apartments is allowed — what is
// *not* allowed is blocking an STA on an async, which is why every command
// below is fire-and-forget rather than `.get()`.
std::mutex g_session_lock;
GlobalSystemMediaTransportControlsSession g_session{nullptr};

std::string EscapeJson(std::wstring_view value) {
  // UTF-16 to UTF-8 first, then escape. Media titles routinely carry quotes,
  // backslashes and emoji, and a title that breaks the JSON takes the whole
  // card down rather than just looking wrong.
  std::string utf8;
  if (!value.empty()) {
    const int needed = ::WideCharToMultiByte(
        CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
        nullptr, nullptr);
    if (needed > 0) {
      utf8.resize(static_cast<size_t>(needed));
      ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                            static_cast<int>(value.size()), utf8.data(), needed,
                            nullptr, nullptr);
    }
  }

  std::string out;
  out.reserve(utf8.size() + 2);
  for (const char raw : utf8) {
    const unsigned char c = static_cast<unsigned char>(raw);
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[7];
          ::sprintf_s(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += raw;
        }
    }
  }
  return out;
}

std::vector<uint8_t> ReadThumbnail(
    const streams::IRandomAccessStreamReference& reference) {
  std::vector<uint8_t> bytes;
  if (reference == nullptr) return bytes;
  try {
    const streams::IRandomAccessStreamWithContentType stream =
        reference.OpenReadAsync().get();
    if (stream == nullptr) return bytes;
    const uint32_t size = static_cast<uint32_t>(stream.Size());
    // A thumbnail larger than this is not a thumbnail. Guard rather than
    // trust: the buffer crosses into a fixed-size copy on the other side.
    if (size == 0 || size > 4u * 1024u * 1024u) return bytes;

    streams::DataReader reader(stream.GetInputStreamAt(0));
    reader.LoadAsync(size).get();
    bytes.resize(size);
    reader.ReadBytes(winrt::array_view<uint8_t>(bytes));
  } catch (...) {
    bytes.clear();
  }
  return bytes;
}

// Builds the snapshot for a session. Runs on the worker; every call here can
// throw, and a throw means "nothing playing" rather than a crash.
void Rebuild(const GlobalSystemMediaTransportControlsSession& session) {
  Snapshot next;

  if (session != nullptr) {
    try {
      const auto props = session.TryGetMediaPropertiesAsync().get();
      const auto playback = session.GetPlaybackInfo();
      const auto timeline = session.GetTimelineProperties();

      const auto status = playback.PlaybackStatus();
      next.playing =
          status == media::GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;

      const auto controls = playback.Controls();

      // Timeline values are TimeSpan (100ns ticks). Position is a reading at
      // LastUpdatedTime, not a live value — Dart advances it from there rather
      // than polling, because Windows updates this sparsely.
      const int64_t position_ms = timeline.Position().count() / 10000;
      const int64_t end_ms = timeline.EndTime().count() / 10000;
      const int64_t start_ms = timeline.StartTime().count() / 10000;
      const int64_t updated_ms =
          winrt::clock::to_time_t(timeline.LastUpdatedTime()) * 1000LL;

      std::string json;
      json.reserve(512);
      json += "{\"title\":\"";
      json += EscapeJson(props.Title());
      json += "\",\"artist\":\"";
      json += EscapeJson(props.Artist());
      json += "\",\"album\":\"";
      json += EscapeJson(props.AlbumTitle());
      json += "\",\"sourceAppId\":\"";
      json += EscapeJson(session.SourceAppUserModelId());
      json += "\",\"isPlaying\":";
      json += next.playing ? "true" : "false";
      json += ",\"positionMs\":" + std::to_string(position_ms);
      json += ",\"startMs\":" + std::to_string(start_ms);
      json += ",\"endMs\":" + std::to_string(end_ms);
      json += ",\"updatedEpochMs\":" + std::to_string(updated_ms);
      json += ",\"canSeek\":";
      json += controls.IsPlaybackPositionEnabled() ? "true" : "false";
      json += ",\"canNext\":";
      json += controls.IsNextEnabled() ? "true" : "false";
      json += ",\"canPrevious\":";
      json += controls.IsPreviousEnabled() ? "true" : "false";
      json += "}";
      next.json = std::move(json);

      next.artwork = ReadThumbnail(props.Thumbnail());
    } catch (...) {
      next.json.clear();
      next.artwork.clear();
    }
  }

  {
    std::lock_guard<std::mutex> guard(g_lock);
    g_snapshot = std::move(next);
    g_has_snapshot = !g_snapshot.json.empty();
  }

  if (g_changed != nullptr) g_changed(g_user);
}

// Per-session event tokens, so they can be detached when the session changes.
// Leaving them attached keeps the old session alive and double-fires.
struct Subscriptions {
  winrt::event_token properties{};
  winrt::event_token playback{};
  winrt::event_token timeline{};
};

Subscriptions g_subs;

void Detach(const GlobalSystemMediaTransportControlsSession& session) {
  if (session == nullptr) return;
  try {
    if (g_subs.properties) session.MediaPropertiesChanged(g_subs.properties);
    if (g_subs.playback) session.PlaybackInfoChanged(g_subs.playback);
    if (g_subs.timeline) session.TimelinePropertiesChanged(g_subs.timeline);
  } catch (...) {
  }
  g_subs = {};
}

void Attach(const GlobalSystemMediaTransportControlsSession& session) {
  if (session == nullptr) return;
  g_subs.properties = session.MediaPropertiesChanged(
      [](auto&& sender, auto&&) { Rebuild(sender); });
  g_subs.playback = session.PlaybackInfoChanged(
      [](auto&& sender, auto&&) { Rebuild(sender); });
  g_subs.timeline = session.TimelinePropertiesChanged(
      [](auto&& sender, auto&&) { Rebuild(sender); });
}

void AdoptCurrent(const GlobalSystemMediaTransportControlsSessionManager& manager) {
  GlobalSystemMediaTransportControlsSession current{nullptr};
  try {
    current = manager.GetCurrentSession();
  } catch (...) {
  }

  GlobalSystemMediaTransportControlsSession previous{nullptr};
  {
    std::lock_guard<std::mutex> guard(g_session_lock);
    previous = g_session;
    g_session = current;
  }
  Detach(previous);
  Attach(current);
  Rebuild(current);
}

void WorkerMain() {
  // Multi-threaded on purpose. The UI thread is an STA (main.cpp calls
  // CoInitializeEx with COINIT_APARTMENTTHREADED), and blocking an STA on a
  // WinRT async throws rather than waits — so every `.get()` in this file has
  // to happen here, not there.
  winrt::init_apartment(winrt::apartment_type::multi_threaded);

  try {
    const auto manager =
        GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();

    const auto token = manager.CurrentSessionChanged(
        [](auto&& sender, auto&&) { AdoptCurrent(sender); });

    AdoptCurrent(manager);

    ::WaitForSingleObject(g_stop.get(), INFINITE);

    manager.CurrentSessionChanged(token);
    GlobalSystemMediaTransportControlsSession last{nullptr};
    {
      std::lock_guard<std::mutex> guard(g_session_lock);
      last = g_session;
      g_session = nullptr;
    }
    Detach(last);
  } catch (...) {
    // No session manager on this machine, or it went away. Not fatal: the card
    // simply shows nothing playing.
  }

  winrt::uninit_apartment();
}

}  // namespace

bool MediaSessionStart(MediaSessionChanged callback, void* user) {
  if (g_running.exchange(true)) return true;

  g_changed = callback;
  g_user = user;
  g_stop.attach(::CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (!g_stop) {
    g_running = false;
    return false;
  }
  g_worker = std::thread(WorkerMain);
  return true;
}

void MediaSessionStop(void) {
  if (!g_running.exchange(false)) return;
  if (g_stop) ::SetEvent(g_stop.get());
  if (g_worker.joinable()) g_worker.join();
  g_stop.close();
  g_changed = nullptr;
  g_user = nullptr;

  std::lock_guard<std::mutex> guard(g_lock);
  g_snapshot = {};
  g_has_snapshot = false;
}

bool MediaSessionSnapshot(char* json, size_t json_capacity, uint8_t* artwork,
                          size_t artwork_capacity, size_t* artwork_len) {
  std::lock_guard<std::mutex> guard(g_lock);
  if (!g_has_snapshot) return false;

  if (json != nullptr) {
    if (g_snapshot.json.size() + 1 > json_capacity) return false;
    std::memcpy(json, g_snapshot.json.c_str(), g_snapshot.json.size() + 1);
  }

  if (artwork_len != nullptr) *artwork_len = 0;
  if (artwork != nullptr && !g_snapshot.artwork.empty()) {
    if (g_snapshot.artwork.size() > artwork_capacity) {
      // Too big for the caller's buffer: report the metadata without the art
      // rather than failing the whole snapshot.
      return true;
    }
    std::memcpy(artwork, g_snapshot.artwork.data(), g_snapshot.artwork.size());
    if (artwork_len != nullptr) *artwork_len = g_snapshot.artwork.size();
  }
  return true;
}

bool MediaSessionCommand(const char* command, int64_t argument) {
  if (command == nullptr) return false;

  GlobalSystemMediaTransportControlsSession session{nullptr};
  {
    std::lock_guard<std::mutex> guard(g_session_lock);
    session = g_session;
  }
  if (session == nullptr) return false;

  // Fire and forget. This runs on the UI thread, which is an STA, so the
  // result is deliberately never awaited — see WorkerMain.
  try {
    const std::string name(command);
    if (name == "playPause") {
      session.TryTogglePlayPauseAsync();
    } else if (name == "play") {
      session.TryPlayAsync();
    } else if (name == "pause") {
      session.TryPauseAsync();
    } else if (name == "next") {
      session.TrySkipNextAsync();
    } else if (name == "previous") {
      session.TrySkipPreviousAsync();
    } else if (name == "seek") {
      // Ticks, not milliseconds.
      session.TryChangePlaybackPositionAsync(argument * 10000);
    } else {
      return false;
    }
  } catch (...) {
    return false;
  }
  return true;
}

namespace {

// Core Audio, not WinRT: the media-session API carries no volume at all, so
// this is the system output level rather than the playing app's.
bool WithEndpointVolume(bool (*body)(IAudioEndpointVolume*, void*), void* user) {
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioEndpointVolume* volume = nullptr;
  bool ok = false;

  if (SUCCEEDED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&enumerator))) &&
      SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia,
                                                    &device)) &&
      SUCCEEDED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                                 nullptr,
                                 reinterpret_cast<void**>(&volume)))) {
    ok = body(volume, user);
  }

  if (volume != nullptr) volume->Release();
  if (device != nullptr) device->Release();
  if (enumerator != nullptr) enumerator->Release();
  return ok;
}

}  // namespace

bool MediaSessionGetVolume(float* out_volume) {
  if (out_volume == nullptr) return false;
  return WithEndpointVolume(
      [](IAudioEndpointVolume* volume, void* user) {
        float level = 0.0f;
        if (FAILED(volume->GetMasterVolumeLevelScalar(&level))) return false;
        *static_cast<float*>(user) = level;
        return true;
      },
      out_volume);
}

bool MediaSessionSetVolume(float volume) {
  if (volume < 0.0f) volume = 0.0f;
  if (volume > 1.0f) volume = 1.0f;
  return WithEndpointVolume(
      [](IAudioEndpointVolume* endpoint, void* user) {
        return SUCCEEDED(endpoint->SetMasterVolumeLevelScalar(
            *static_cast<float*>(user), nullptr));
      },
      &volume);
}

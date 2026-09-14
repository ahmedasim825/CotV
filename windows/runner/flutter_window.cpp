#include "flutter_window.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "media/media_session.h"

namespace {

// Where Dart asks for the window operations the title bar used to provide.
//
// The caption is gone (see `WM_NCCALCSIZE` in win32_window.cpp), so moving,
// minimising, maximising and closing have no OS affordance left. Dart draws
// those controls itself and calls through here.
constexpr const char kWindowChannel[] = "cotv/window";

// Transport commands, and the now-playing stream they act on.
constexpr const char kMediaChannel[] = "cotv/media";
constexpr const char kMediaEventChannel[] = "cotv/media/events";

// Posted by the media bridge's worker thread when Windows reports a change.
//
// The bridge's callback runs on a WinRT thread pool, and a Flutter channel may
// only be touched from the UI thread — so the callback does nothing but post
// this, and the real work happens in MessageHandler where it is safe.
constexpr UINT kMediaChangedMessage = WM_APP + 1;

// The snapshot buffers. Metadata is small; the artwork cap matches the one the
// bridge itself enforces, so a thumbnail either fits both or neither.
constexpr size_t kMediaJsonCapacity = 8 * 1024;
constexpr size_t kMediaArtCapacity = 4 * 1024 * 1024;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  media_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaChannel,
          &flutter::StandardMethodCodec::GetInstance());
  media_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const std::string& method = call.method_name();

    if (method == "setVolume") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      double level = -1.0;
      if (args != nullptr) {
        auto it = args->find(flutter::EncodableValue("volume"));
        if (it != args->end()) {
          if (const auto* value = std::get_if<double>(&it->second)) {
            level = *value;
          }
        }
      }
      if (level < 0.0 || level > 1.0) {
        result->Error("bad_volume", "Volume must be between 0 and 1.");
        return;
      }
      result->Success(
          flutter::EncodableValue(MediaSessionSetVolume(
              static_cast<float>(level))));
      return;
    }

    if (method == "getVolume") {
      float level = 0.0f;
      if (!MediaSessionGetVolume(&level)) {
        result->Error("no_endpoint", "No audio output to read.");
        return;
      }
      result->Success(flutter::EncodableValue(static_cast<double>(level)));
      return;
    }

    // Everything else is a transport verb the bridge validates for us.
    int64_t argument = 0;
    if (method == "seek") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args != nullptr) {
        auto it = args->find(flutter::EncodableValue("positionMs"));
        if (it != args->end()) {
          if (const auto* value = std::get_if<int64_t>(&it->second)) {
            argument = *value;
          } else if (const auto* narrow = std::get_if<int32_t>(&it->second)) {
            argument = *narrow;
          }
        }
      }
    }

    if (method == "playPause" || method == "play" || method == "pause" ||
        method == "next" || method == "previous" || method == "seek") {
      result->Success(
          flutter::EncodableValue(MediaSessionCommand(method.c_str(), argument)));
      return;
    }

    result->NotImplemented();
  });

  media_events_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaEventChannel,
          &flutter::StandardMethodCodec::GetInstance());
  media_events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     events)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            media_sink_ = std::move(events);
            // The bridge only pushes on change, so a listener that arrives
            // mid-track would otherwise wait for the next one. Seed it.
            MediaSessionStart(
                [](void* user) {
                  auto* self = static_cast<FlutterWindow*>(user);
                  ::PostMessage(self->GetHandle(), kMediaChangedMessage, 0, 0);
                },
                this);
            EmitMediaSnapshot();
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            MediaSessionStop();
            media_sink_ = nullptr;
            return nullptr;
          }));

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const std::string& method = call.method_name();
        HWND hwnd = GetHandle();
        if (hwnd == nullptr) {
          result->Error("no_window", "The window is already gone.");
          return;
        }

        if (method == "startResize") {
          // Same handoff as startDrag, with the edge the cursor is on instead
          // of HTCAPTION. Dart has to ask, because the Flutter view is a child
          // window covering the whole client area: it takes every mouse
          // message itself, so the parent's own `WM_NCHITTEST` never sees the
          // cursor reach an edge.
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          int edge = 0;
          if (args != nullptr) {
            auto it = args->find(flutter::EncodableValue("edge"));
            if (it != args->end()) {
              if (const auto* value = std::get_if<int32_t>(&it->second)) {
                edge = *value;
              }
            }
          }
          // Only the eight resize hit-test codes, so a bad argument cannot be
          // turned into a caption drag or a system-menu click.
          if (edge < HTLEFT || edge > HTBOTTOMRIGHT) {
            result->Error("bad_edge", "Not a resize edge.");
            return;
          }
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, edge, 0);
          result->Success();
        } else if (method == "startDrag") {
          // The Flutter view is a child window holding the mouse capture, so
          // it has to let go before the parent can take over the drag. This
          // is the same handoff the caption did for free.
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (method == "minimize") {
          ShowWindow(hwnd, SW_MINIMIZE);
          result->Success();
        } else if (method == "toggleMaximize") {
          ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != 0));
        } else if (method == "close") {
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != 0));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::EmitMediaSnapshot() {
  if (!media_sink_) return;

  std::vector<char> json(kMediaJsonCapacity);
  std::vector<uint8_t> art(kMediaArtCapacity);
  size_t art_len = 0;

  if (!MediaSessionSnapshot(json.data(), json.size(), art.data(), art.size(),
                            &art_len)) {
    // Nothing playing is a value, not an error: Dart renders the idle card.
    media_sink_->Success(flutter::EncodableValue());
    return;
  }

  art.resize(art_len);
  media_sink_->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("json"),
       flutter::EncodableValue(std::string(json.data()))},
      {flutter::EncodableValue("artwork"), flutter::EncodableValue(art)},
  }));
}

void FlutterWindow::OnDestroy() {
  // The bridge owns a thread that posts to this window, so it stops first.
  MediaSessionStop();
  media_sink_ = nullptr;
  if (media_events_) {
    media_events_->SetStreamHandler(nullptr);
    media_events_ = nullptr;
  }
  if (media_channel_) {
    media_channel_->SetMethodCallHandler(nullptr);
    media_channel_ = nullptr;
  }

  // Torn down before the engine it posts to, not after.
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
    window_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kMediaChangedMessage:
      // Posted from the media bridge's worker thread; this is the first point
      // at which touching the engine is legal.
      EmitMediaSnapshot();
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

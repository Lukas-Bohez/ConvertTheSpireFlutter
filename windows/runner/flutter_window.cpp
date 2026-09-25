#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "open_requests.h"

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

  open_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "convert_the_spire/open",
          &flutter::StandardMethodCodec::GetInstance());
  open_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "takePending") {
          result->NotImplemented();
          return;
        }
        flutter::EncodableList targets;
        for (const auto& target : pending_open_requests_) {
          targets.push_back(flutter::EncodableValue(target));
        }
        pending_open_requests_.clear();
        result->Success(flutter::EncodableValue(targets));
      });
  // Only now can a second copy of the app hand requests to this window.
  open_requests::MarkMainWindow(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::QueueOpenRequests(const std::vector<std::string>& targets) {
  pending_open_requests_.insert(pending_open_requests_.end(), targets.begin(),
                                targets.end());
  // Also sent when there is nothing to open: a plain second start brings
  // the window forward. Dart asks for the list itself at startup, so a
  // nudge sent before it listens is not needed.
  if (open_channel_) {
    open_channel_->InvokeMethod("pending", nullptr);
  }
}

void FlutterWindow::OnDestroy() {
  open_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COPYDATA) {
    std::vector<std::string> targets;
    if (open_requests::DecodeForwarded(
            reinterpret_cast<const COPYDATASTRUCT*>(lparam), &targets)) {
      QueueOpenRequests(targets);
      return TRUE;
    }
  }

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Queues files and links to open (command-line arguments, or those a
  // second copy of the app forwarded) and tells Dart they are waiting.
  void QueueOpenRequests(const std::vector<std::string>& targets);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "convert_the_spire/open": Dart takes the queued requests with
  // takePending; "pending" tells it new ones arrived.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      open_channel_;
  std::vector<std::string> pending_open_requests_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

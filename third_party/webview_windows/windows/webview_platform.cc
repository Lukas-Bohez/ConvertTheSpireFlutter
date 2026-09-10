#include "webview_platform.h"

#include <DispatcherQueue.h>
#include <shlobj.h>
#include <windows.graphics.capture.h>

#include <filesystem>
#include <iostream>

#include "util/probe_log.h"

WebviewPlatform::WebviewPlatform()
    : rohelper_(std::make_unique<rx::RoHelper>(RO_INIT_SINGLETHREADED)) {
  CtsProbeLog(std::string("ctor: WinRtAvailable=") +
              (rohelper_->WinRtAvailable() ? "true" : "false"));
  if (rohelper_->WinRtAvailable()) {
    // The Flutter Windows engine (or a plugin loaded before us) may already
    // have initialized the platform thread's COM apartment as MTA. RoHelper
    // tolerates that (RPC_E_CHANGED_MODE -> "available"), but the
    // DispatcherQueue creation is picky about the thread's COM state: the
    // upstream DQTYPE_THREAD_CURRENT + DQTAT_COM_STA combo fails with
    // RPC_E_WRONG_THREAD (0x8001010E), so the ctor silently bails and every
    // browser session dies with "unsupported_platform".
    //
    // Try progressively more permissive variants until one succeeds; keep the
    // first that works and log which one so future breakage stays visible.
    struct Variant {
      const char* name;
      int thread;
      int apt;
    };
    const Variant variants[] = {
        {"current_none", DQTYPE_THREAD_CURRENT, DQTAT_COM_NONE},
        {"current_sta", DQTYPE_THREAD_CURRENT, DQTAT_COM_STA},
        {"dedicated_none", DQTYPE_THREAD_DEDICATED, DQTAT_COM_NONE},
        {"dedicated_sta", DQTYPE_THREAD_DEDICATED, DQTAT_COM_STA},
    };
    for (const auto& v : variants) {
      DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),
                                     static_cast<DISPATCHERQUEUE_THREAD_TYPE>(v.thread),
                                     static_cast<DISPATCHERQUEUE_THREAD_APARTMENTTYPE>(v.apt)};
      dispatcher_queue_controller_ = nullptr;
      HRESULT hr = rohelper_->CreateDispatcherQueueController(
          options, dispatcher_queue_controller_.put());
      if (SUCCEEDED(hr) && dispatcher_queue_controller_) {
        CtsProbeLog(std::string("ctor: DispatcherQueue ok (") + v.name + ")");
        break;
      }
      char buf[32];
      snprintf(buf, sizeof(buf), "0x%08lX", static_cast<unsigned long>(hr));
      CtsProbeLog(std::string("ctor: DispatcherQueue ") + v.name +
                  " failed hr=" + buf);
      dispatcher_queue_controller_ = nullptr;
    }

    if (!dispatcher_queue_controller_) {
      CtsProbeLog("ctor: ALL DispatcherQueue variants failed");
      return;
    }

    if (!IsGraphicsCaptureSessionSupported()) {
      CtsProbeLog("ctor: GraphicsCaptureSession NOT supported");
      std::cerr << "Windows::Graphics::Capture::GraphicsCaptureSession is not "
                   "supported."
                << std::endl;
      return;
    }
    CtsProbeLog("ctor: GraphicsCaptureSession supported");

    graphics_context_ = std::make_unique<GraphicsContext>(rohelper_.get());
    valid_ = graphics_context_->IsValid();
    CtsProbeLog(std::string("ctor: GraphicsContext valid=") +
                (valid_ ? "true" : "false"));
  }
  CtsProbeLog(std::string("ctor: final IsSupported=") +
              (IsSupported() ? "true" : "false"));
}

bool WebviewPlatform::IsGraphicsCaptureSessionSupported() {
  HSTRING className;
  HSTRING_HEADER classNameHeader;

  if (FAILED(rohelper_->GetStringReference(
          RuntimeClass_Windows_Graphics_Capture_GraphicsCaptureSession,
          &className, &classNameHeader))) {
    CtsProbeLog("capture: GetStringReference FAILED");
    return false;
  }

  ABI::Windows::Graphics::Capture::IGraphicsCaptureSessionStatics*
      capture_session_statics;
  if (FAILED(rohelper_->GetActivationFactory(
          className,
          __uuidof(
              ABI::Windows::Graphics::Capture::IGraphicsCaptureSessionStatics),
          (void**)&capture_session_statics))) {
    CtsProbeLog("capture: GetActivationFactory FAILED");
    return false;
  }

  boolean is_supported = false;
  if (FAILED(capture_session_statics->IsSupported(&is_supported))) {
    CtsProbeLog("capture: IsSupported() call FAILED");
    return false;
  }

  CtsProbeLog(std::string("capture: is_supported=") +
              (is_supported ? "true" : "false"));
  return !!is_supported;
}

std::optional<std::wstring> WebviewPlatform::GetDefaultDataDirectory() {
  PWSTR path_tmp;
  if (!SUCCEEDED(
          SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path_tmp))) {
    return std::nullopt;
  }
  auto path = std::filesystem::path(path_tmp);
  CoTaskMemFree(path_tmp);

  wchar_t filename[MAX_PATH];
  GetModuleFileName(nullptr, filename, MAX_PATH);
  path /= "flutter_webview_windows";
  path /= std::filesystem::path(filename).stem();

  return path.wstring();
}

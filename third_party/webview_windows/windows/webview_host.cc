#include "webview_host.h"

#include <wrl.h>

#include <future>
#include <iostream>

#include "util/rohelper.h"

using namespace Microsoft::WRL;

namespace {

// Creates the environment, blocking until WebView2 reports back.
HRESULT CreateEnvironment(std::optional<std::wstring> user_data_directory,
                          std::optional<std::wstring> browser_exe_path,
                          std::optional<std::string> arguments,
                          bool enable_browser_extensions,
                          wil::com_ptr<ICoreWebView2Environment>& env) {
  auto opts = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  if (arguments.has_value()) {
    std::wstring warguments(arguments.value().begin(), arguments.value().end());
    opts->put_AdditionalBrowserArguments(warguments.c_str());
  }
  if (enable_browser_extensions) {
    // Extensions can only be switched on here, before the environment
    // exists; once created, the environment's value is fixed (issue #10).
    wil::com_ptr<ICoreWebView2EnvironmentOptions6> opts6;
    if (SUCCEEDED(opts->QueryInterface(IID_PPV_ARGS(&opts6))) && opts6) {
      opts6->put_AreBrowserExtensionsEnabled(TRUE);
    }
  }

  std::promise<HRESULT> result_promise;
  auto result = CreateCoreWebView2EnvironmentWithOptions(
      browser_exe_path.has_value() ? browser_exe_path->c_str() : nullptr,
      user_data_directory.has_value() ? user_data_directory->c_str() : nullptr,
      opts.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [&promise = result_promise, &ptr = env](
              HRESULT r, ICoreWebView2Environment* created) -> HRESULT {
            promise.set_value(r);
            ptr.swap(created);
            return S_OK;
          })
          .Get());
  if (SUCCEEDED(result)) {
    result = result_promise.get_future().get();
  }
  return result;
}

}  // namespace

// static
std::unique_ptr<WebviewHost> WebviewHost::Create(
    WebviewPlatform* platform, std::optional<std::wstring> user_data_directory,
    std::optional<std::wstring> browser_exe_path,
    std::optional<std::string> arguments) {
  // Try with browser extensions first. If the runtime refuses - for example
  // because another process already opened this user data folder without
  // them - fall back to the old behaviour, so the browser itself never breaks
  // over an optional feature.
  for (const bool extensions : {true, false}) {
    wil::com_ptr<ICoreWebView2Environment> env;
    const HRESULT result = CreateEnvironment(
        user_data_directory, browser_exe_path, arguments, extensions, env);
    if ((SUCCEEDED(result) || result == RPC_E_CHANGED_MODE) && env) {
      auto webview_env3 = env.try_query<ICoreWebView2Environment3>();
      if (webview_env3) {
        auto host = std::unique_ptr<WebviewHost>(
            new WebviewHost(platform, std::move(webview_env3)));
        host->browser_extensions_enabled_ = extensions;
        return host;
      }
    }
  }

  return {};
}

WebviewHost::WebviewHost(WebviewPlatform* platform,
                         wil::com_ptr<ICoreWebView2Environment3> webview_env)
    : webview_env_(webview_env) {
  compositor_ = platform->graphics_context()->CreateCompositor();
}

void WebviewHost::CreateWebview(HWND hwnd, bool offscreen_only,
                                bool owns_window,
                                WebviewCreationCallback callback) {
  CreateWebViewCompositionController(
      hwnd, [=, self = this](
                wil::com_ptr<ICoreWebView2CompositionController> controller,
                std::unique_ptr<WebviewCreationError> error) {
        if (controller) {
          std::unique_ptr<Webview> webview(new Webview(
              std::move(controller), self, hwnd, owns_window, offscreen_only));
          callback(std::move(webview), nullptr);
        } else {
          callback(nullptr, std::move(error));
        }
      });
}

void WebviewHost::CreateWebViewPointerInfo(PointerInfoCreationCallback callback) {

  ICoreWebView2PointerInfo *pointer;
  auto hr = webview_env_->CreateCoreWebView2PointerInfo(&pointer);

  if (FAILED(hr)) {
    callback(nullptr, WebviewCreationError::create(hr, "CreateWebViewPointerInfo failed."));
  } else if (SUCCEEDED(hr)) {
    callback(std::move(wil::com_ptr<ICoreWebView2PointerInfo>(pointer)), nullptr);
  }
}

void WebviewHost::CreateWebViewCompositionController(
    HWND hwnd, CompositionControllerCreationCallback callback) {
  auto hr = webview_env_->CreateCoreWebView2CompositionController(
      hwnd,
      Callback<
          ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler>(
          [callback](HRESULT hr,
                     ICoreWebView2CompositionController* compositionController)
              -> HRESULT {
            if (SUCCEEDED(hr)) {
              callback(
                  std::move(wil::com_ptr<ICoreWebView2CompositionController>(
                      compositionController)),
                  nullptr);
            } else {
              callback(nullptr, WebviewCreationError::create(
                                    hr,
                                    "CreateCoreWebView2CompositionController "
                                    "completion handler failed."));
            }

            return S_OK;
          })
          .Get());

  if (FAILED(hr)) {
    callback(nullptr,
             WebviewCreationError::create(
                 hr, "CreateCoreWebView2CompositionController failed."));
  }
}

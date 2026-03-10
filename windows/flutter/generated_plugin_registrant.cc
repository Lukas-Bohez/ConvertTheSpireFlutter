//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_inappwebview_windows/flutter_inappwebview_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
    // Temporarily skip registering flutter_inappwebview_windows on Windows
    // to avoid a startup crash in certain environments caused by DirectComposition
    // / WebView2 initialization. This is a targeted workaround for release builds
    // while a proper fix is applied in the plugin. Remove this bypass once the
    // upstream plugin is fixed.
#if 0
    FlutterInappwebviewWindowsPluginCApiRegisterWithRegistrar(
            registry->GetRegistrarForPlugin("FlutterInappwebviewWindowsPluginCApi"));
#endif
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}

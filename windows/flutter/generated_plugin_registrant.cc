//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_inappwebview_windows/flutter_inappwebview_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
    // Temporarily skip registering flutter_inappwebview_windows on Windows to
    // avoid an immediate startup crash observed in Release builds (dcomp.dll).
    // This is a temporary measure; revert once the plugin or environment is fixed.
#if 0
    FlutterInappwebviewWindowsPluginCApiRegisterWithRegistrar(
            registry->GetRegistrarForPlugin("FlutterInappwebviewWindowsPluginCApi"));
#endif
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}

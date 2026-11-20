#include "my_application.h"

#include <webview_cef/webview_cef_plugin.h>

int main(int argc, char** argv) {
  // X11 first (XWayland on a Wayland desktop), Wayland when there is no X.
  // On Wayland libmpv sets up hardware decoding through libva-wayland when
  // it makes a video output, and that crashed the app (under WSL, and with
  // some drivers); window_manager can also only place and centre a window
  // on X11. Anyone who sets GDK_BACKEND keeps their choice.
  g_setenv("GDK_BACKEND", "x11,wayland", FALSE);

  // CEF (the browser's Chromium) starts its helper processes from this same
  // program; when this is one of them, run it and quit.
  int cef_exit_code = initCEFProcesses(argc, argv);
  if (cef_exit_code >= 0) {
    return cef_exit_code;
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

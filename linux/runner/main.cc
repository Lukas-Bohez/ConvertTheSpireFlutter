#include "my_application.h"

int main(int argc, char** argv) {
  // X11 first (XWayland on a Wayland desktop), Wayland when there is no X.
  // On Wayland libmpv sets up hardware decoding through libva-wayland when
  // it makes a video output, and that crashed the app (under WSL, and with
  // some drivers); window_manager can also only place and centre a window
  // on X11. Anyone who sets GDK_BACKEND keeps their choice.
  g_setenv("GDK_BACKEND", "x11,wayland", FALSE);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

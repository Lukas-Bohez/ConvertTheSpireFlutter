#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The app's window, once made.
  GtkWindow* window;
  // "convert_the_spire/open": hands Dart (OpenRequestService) the files and
  // links the app was asked to open, as the Windows runner does.
  FlMethodChannel* open_channel;
  // Those files and links, until Dart takes them.
  GPtrArray* pending;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// "takePending" on the open channel: the waiting files and links.
static void open_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "takePending") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (guint i = 0; i < self->pending->len; i++) {
      fl_value_append_take(
          list, fl_value_new_string(static_cast<const gchar*>(
                    g_ptr_array_index(self->pending, i))));
    }
    g_ptr_array_set_size(self->pending, 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    // The app was started again: Dart brings the window forward (also out
    // of the tray) and opens what came with the new start.
    if (self->open_channel != nullptr) {
      fl_method_channel_invoke_method(self->open_channel, "pending", nullptr,
                                      nullptr, nullptr, nullptr);
    }
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Convert the Spire Reborn");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Convert the Spire Reborn");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view),
                                                  "OpenRequests");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->open_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "convert_the_spire/open",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->open_channel, open_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::command_line: a start of the app, this one or a
// later one, which passed its command line here and quit. Files and links in
// it ("Open with", a magnet link from the browser) wait for Dart.
static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  gint argc = 0;
  g_auto(GStrv) argv =
      g_application_command_line_get_arguments(command_line, &argc);
  const gchar* cwd = g_application_command_line_get_cwd(command_line);
  for (gint i = 1; i < argc; i++) {
    const gchar* arg = argv[i];
    if (arg[0] == '\0' || arg[0] == '-') continue;
    // Links (magnet:, file://) and absolute paths as they are; a relative
    // path is relative to the folder the start came from.
    if (strchr(arg, ':') != nullptr || g_path_is_absolute(arg) ||
        cwd == nullptr) {
      g_ptr_array_add(self->pending, g_strdup(arg));
    } else {
      g_ptr_array_add(self->pending, g_build_filename(cwd, arg, nullptr));
    }
  }
  g_application_activate(application);
  return 0;
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // GApplication registers the app on the session bus and passes the
  // command line to command_line: here, or in the copy that already runs,
  // in which case this one quits. One copy at a time, as on Windows: two
  // used to run side by side and fight over the torrents and the database.
  return G_APPLICATION_CLASS(my_application_parent_class)
      ->local_command_line(application, arguments, exit_status);
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->open_channel);
  g_clear_pointer(&self->pending, g_ptr_array_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending = g_ptr_array_new_with_free_func(g_free);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

#ifdef NDEBUG
  GApplicationFlags flags = G_APPLICATION_HANDLES_COMMAND_LINE;
#else
  // A debug build (flutter run, the integration tests) runs on its own, also
  // while an installed copy runs: it would hand itself to that copy.
  GApplicationFlags flags = static_cast<GApplicationFlags>(
      G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_NON_UNIQUE);
#endif
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}

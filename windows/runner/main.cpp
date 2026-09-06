#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <dbghelp.h>
#include <windows.h>

#include <cwchar>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

LONG WINAPI WriteNativeCrashDump(EXCEPTION_POINTERS* exception_pointers) {
  static LONG dump_started = 0;
  if (InterlockedExchange(&dump_started, 1) != 0) {
    return EXCEPTION_EXECUTE_HANDLER;
  }

  wchar_t module_path[MAX_PATH] = {};
  const DWORD path_length = GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (path_length == 0 || path_length >= MAX_PATH) {
    return EXCEPTION_EXECUTE_HANDLER;
  }

  std::wstring crash_directory(module_path, path_length);
  const size_t separator = crash_directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return EXCEPTION_EXECUTE_HANDLER;
  }
  crash_directory.resize(separator + 1);
  crash_directory += L"crashes";
  CreateDirectoryW(crash_directory.c_str(), nullptr);

  SYSTEMTIME now;
  GetLocalTime(&now);
  wchar_t dump_path[MAX_PATH] = {};
  _snwprintf_s(
      dump_path, _countof(dump_path), _TRUNCATE,
      L"%s\\native_crash_%04u%02u%02u_%02u%02u%02u.dmp",
      crash_directory.c_str(), now.wYear, now.wMonth, now.wDay, now.wHour,
      now.wMinute, now.wSecond);

  const HANDLE dump_file = CreateFileW(
      dump_path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (dump_file != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION exception_information = {};
    exception_information.ThreadId = GetCurrentThreadId();
    exception_information.ExceptionPointers = exception_pointers;
    exception_information.ClientPointers = FALSE;
    MiniDumpWriteDump(
        GetCurrentProcess(), GetCurrentProcessId(), dump_file,
        static_cast<MINIDUMP_TYPE>(MiniDumpWithDataSegs |
                                    MiniDumpWithIndirectlyReferencedMemory),
        exception_pointers == nullptr ? nullptr : &exception_information,
        nullptr, nullptr);
    CloseHandle(dump_file);
  }

  return EXCEPTION_EXECUTE_HANDLER;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  ::SetUnhandledExceptionFilter(WriteNativeCrashDump);

  // All plugin DLLs remain in the root directory next to the executable so
  // the Windows loader can resolve them during process startup. We
  // deliberately do NOT move DLLs into a dlls/ subfolder or call
  // SetDllDirectoryW: that API only takes effect for LoadLibrary calls issued
  // after it returns, but the loader has already bound the executable's direct
  // import dependencies before wWinMain begins, so any DLL moved to a
  // subfolder at that point would be lost and the process would fail to start.

  // Certain GPU/driver combinations crash inside dcomp.dll when the engine tries
  // to initialize DirectComposition.  Force software rendering to avoid those
  // crashes and guarantee the application window appears.
  ::SetEnvironmentVariable(L"FLUTTER_ENABLE_SOFTWARE_RENDERING", L"1");
  // Some builds may also respect this variable to disable dcomp entirely.
  ::SetEnvironmentVariable(L"FLUTTER_DISABLE_DCOMP", L"1");

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Convert The Spire Reborn", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

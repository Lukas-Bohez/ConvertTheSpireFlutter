import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

Future<void> captureWindowsMiniDump(String reason, String logPath) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final filename =
        'webview_crash_${DateTime.now().toIso8601String().replaceAll(':', '-')}.dmp';
    final path = '${dir.path}${Platform.pathSeparator}$filename';
    final hFile = CreateFile(
      TEXT(path),
      GENERIC_WRITE,
      0,
      Pointer<SECURITY_ATTRIBUTES>.fromAddress(0),
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      NULL,
    );
    if (hFile == INVALID_HANDLE_VALUE) return;
    final dbghelp = DynamicLibrary.open('Dbghelp.dll');
    final miniDumpWriteDump = dbghelp
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Uint32,
            IntPtr,
            Uint32,
            IntPtr,
            IntPtr,
            IntPtr,
          ),
          int Function(int, int, int, int, int, int, int)
        >('MiniDumpWriteDump');
    miniDumpWriteDump(
      GetCurrentProcess(),
      GetCurrentProcessId(),
      hFile,
      0x00000001 | 0x00000004,
      0,
      0,
      0,
    );
    CloseHandle(hFile);
  } catch (_) {}
}

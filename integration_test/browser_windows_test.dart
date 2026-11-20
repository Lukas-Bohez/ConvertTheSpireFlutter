import 'dart:ffi';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_windows.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:win32/win32.dart';

/// The Windows browser (WebView2) against a local page: the mouse wheel,
/// through Flutter's pointer events and the plugin, scrolls the page and a
/// scrolling box under the mouse; with the page focused, the arrow keys go
/// to the app (the PC keyboard is the TV remote) unless a text field on the
/// page has the focus, and Enter is handed over too.
///
/// Keys are posted to this test's own focused window, never typed through
/// the system, so nothing else on the PC receives them.
///
///   flutter test -d windows integration_test/browser_windows_test.dart
void main() {
  if (!Platform.isWindows) return;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.headers.contentType = ContentType.html;
      req.response.write(req.uri.path == '/panel' ? _panelPage : _tallPage);
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  testWidgets('the mouse wheel scrolls the page and a box under the mouse',
      (tester) async {
    final adapter = BrowserWindowsWebViewAdapter();
    final loaded = <String>[];
    final sub = adapter.pageEvents.listen((e) {
      if (!e.isStart) loaded.add(e.url);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: adapter.buildWidget())),
    ));

    Future<void> settle(int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
    }

    Future<void> waitFor(bool Function() done, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (!done()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await settle(1);
      }
    }

    Future<Object?> js(String code) async {
      // ignore: avoid_print
      print('STEP js $code');
      return tester.runAsync<Object?>(() => adapter
          .evaluateJsExpression(code)
          .timeout(const Duration(seconds: 15)));
    }

    double number(Object? v) => double.parse('$v'.replaceAll('"', ''));

    final base = 'http://127.0.0.1:${server.port}';
    await tester.runAsync(() => adapter.loadUrl('$base/tall'));
    await waitFor(() => loaded.any((u) => u.contains('/tall')), 'the page');
    await settle(10);

    final center = tester.getCenter(find.byType(Scaffold));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await settle(2);
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await settle(3);
    }
    await settle(10);
    // ignore: avoid_print
    print('STEP wheel log: ${await js('JSON.stringify(window.__wheels||[])')}');
    // ignore: avoid_print
    print('STEP move log: ${await js('JSON.stringify(window.__moves||[])')}');
    final y = number(await js('window.scrollY'));
    // ignore: avoid_print
    print('STEP page scrollY after wheel: $y');
    expect(y, greaterThan(50), reason: 'the wheel scrolled the page');

    await tester.runAsync(() => adapter.loadUrl('$base/panel'));
    await waitFor(() => loaded.any((u) => u.contains('/panel')), 'the panel');
    await settle(10);
    await tester.sendEventToBinding(pointer.hover(center + const Offset(1, 1)));
    await settle(2);
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await settle(3);
    }
    await settle(10);
    final top = number(await js("document.getElementById('box').scrollTop"));
    // ignore: avoid_print
    print('STEP box scrollTop after wheel: $top');
    expect(top, greaterThan(50), reason: 'the wheel scrolled the box');

    // --- The arrow keys with the page focused. ---
    final remote = <String>[];
    final keySub = adapter.jsMessages.listen((m) {
      if (m.handler == 'remoteKey') remote.add(m.payload);
    });
    await tester.runAsync(() => adapter.loadUrl('$base/tall?keys'));
    await waitFor(() => loaded.any((u) => u.contains('/tall?keys')), 'keys');
    await settle(10);
    // A click gives the page the keyboard.
    final click = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(click.hover(center));
    await tester.sendEventToBinding(click.down(center));
    await settle(1);
    await tester.sendEventToBinding(click.up());
    await settle(5);
    final focus = _focusedWindowOfThisApp();
    // ignore: avoid_print
    print('STEP focused window: $focus');
    expect(focus, isNot(0), reason: 'the page took the keyboard');

    Future<void> arrowDown() async {
      _postKey(focus, VK_DOWN, down: true);
      await settle(3);
      _postKey(focus, VK_DOWN, down: false);
      await settle(5);
    }

    // A focused text field keeps the arrows (the page bridge says so).
    await js("__bbCall('InputFocusChannel', '{\"value\":\"\"}')");
    await settle(3);
    await arrowDown();
    final typed = number(await js('window.scrollY'));
    // ignore: avoid_print
    print('STEP scrollY, arrow with remote keys off: $typed');
    expect(typed, greaterThan(0),
        reason: 'the posted key reached the page (control)');

    await js("window.scrollTo(0, 0); __bbCall('InputFocusChannel', '__blur__')");
    await settle(3);
    remote.clear();
    await arrowDown();
    final remoteY = number(await js('window.scrollY'));
    // ignore: avoid_print
    print('STEP scrollY, arrow as remote: $remoteY, handed over: $remote');
    expect(remoteY, 0, reason: 'the arrow did not scroll the page');
    expect(remote, containsAllInOrder(['ArrowDown:down', 'ArrowDown:up']));

    remote.clear();
    await js("document.body.dispatchEvent(new KeyboardEvent('keydown', "
        "{key: 'Enter', bubbles: true, cancelable: true})); 1");
    await settle(3);
    expect(remote, ['Enter:down'], reason: 'Enter goes to the cursor');

    await keySub.cancel();
    await sub.cancel();
    await tester.runAsync(adapter.dispose);
  });
}

/// The window of this process that has the keyboard: the WebView's own
/// window once the page is clicked.
int _focusedWindowOfThisApp() {
  final pid = GetCurrentProcessId();
  final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final pidOut = calloc<Uint32>();
  final info = calloc<GUITHREADINFO>()..ref.cbSize = sizeOf<GUITHREADINFO>();
  try {
    var hwnd = 0;
    while (true) {
      hwnd = FindWindowEx(0, hwnd, cls, nullptr);
      if (hwnd == 0) return 0;
      final tid = GetWindowThreadProcessId(hwnd, pidOut);
      if (pidOut.value != pid) continue;
      if (GetGUIThreadInfo(tid, info) == 0) return 0;
      return info.ref.hwndFocus;
    }
  } finally {
    calloc.free(cls);
    calloc.free(pidOut);
    calloc.free(info);
  }
}

void _postKey(int hwnd, int vk, {required bool down}) {
  final scan = MapVirtualKey(vk, MAPVK_VK_TO_VSC);
  // Arrow keys are extended keys; a key-up also sets the previous-state and
  // transition bits.
  var lParam = 1 | (scan << 16) | (1 << 24);
  if (!down) lParam |= (1 << 30) | (1 << 31);
  PostMessage(hwnd, down ? WM_KEYDOWN : WM_KEYUP, vk, lParam);
}

const _tallPage = '''<!doctype html><html><head><title>Tall page</title>
<style>body{margin:0}div{height:6000px;background:linear-gradient(#fff,#888)}</style>
<script>window.__wheels=[];window.__moves=[];
addEventListener('wheel',function(e){__wheels.push([e.clientX,e.clientY,e.deltaY,e.deltaMode,e.defaultPrevented]);},{passive:true});
addEventListener('mousemove',function(e){if(__moves.length<5)__moves.push([e.clientX,e.clientY]);});</script>
</head><body><div>tall</div></body></html>''';

const _panelPage = '''<!doctype html><html><head><title>Panel page</title>
<style>
html,body{margin:0;height:100%;overflow:hidden}
header{position:fixed;top:0;left:0;right:0;height:80px;background:#246;color:#fff}
#box{position:absolute;top:0;bottom:0;left:0;right:0;overflow:auto}
#box div{height:6000px;background:linear-gradient(#fff,#888)}
</style></head><body><header>fixed header</header>
<div id="box"><div>content</div></div></body></html>''';


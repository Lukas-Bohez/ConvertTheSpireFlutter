import 'dart:ffi';
import 'dart:io';

import 'package:convert_the_spire_reborn/main.dart' as app;
import 'package:convert_the_spire_reborn/src/screens/browser_screen.dart';
import 'package:convert_the_spire_reborn/src/screens/home_screen.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart' show Webview;
import 'package:win32/win32.dart';

/// The browser inside the whole app on Windows, as someone uses it: the
/// mouse wheel scrolls the page; once the page is clicked, the arrow keys
/// still move the TV-remote cursor (the PC keyboard stands in for a TV
/// remote), Enter clicks where it is and Page Down scrolls; a text field
/// clicked with the mouse takes the keys itself, one the remote's Enter
/// chose opens the typing box.
///
/// The test page reports what it receives to the test's own server, so the
/// test sees what a real page sees. Keys are posted to the app's own focused
/// window, never typed through the system, so nothing else on the PC gets
/// them. Settings and data are a sandbox of their own.
///
///   flutter test -d windows integration_test/browser_app_test.dart
void main() {
  if (!Platform.isWindows) return;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('wheel, remote keys and text fields in the real app',
      (tester) async {
    final events = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/log') {
        events.add(req.uri.query.split('&t=').first);
        req.response.statusCode = 204;
      } else {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_page);
      }
      await req.response.close();
    });

    final sandbox = await Directory.systemTemp.createTemp('browser_app');
    PathProviderPlatform.instance = _SandboxPaths(sandbox.path);
    final version = (await PackageInfo.fromPlatform()).version;
    SharedPreferences.setMockInitialValues({
      'onboardingSeenVersion': version,
      'whats_new_last_shown_version': version,
      'onboarding_step': 4,
      'use_dht': false,
      'use_pex': false,
      'use_lpd': false,
    });

    Future<void> hold(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> waitFor(bool Function() done, String what,
        {int seconds = 30}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!done()) {
        if (DateTime.now().isAfter(end)) {
          // ignore: avoid_print
          print('STEP TIMEOUT $what');
          fail('timed out waiting for $what; the page reported: $events');
        }
        await hold(100);
      }
    }

    List<String> since(int mark) => events.sublist(mark);
    bool has(int mark, String prefix) =>
        since(mark).any((e) => e.startsWith(prefix));
    double lastScroll() => events
        .where((e) => e.startsWith('scroll='))
        .map((e) => double.parse(e.substring(7)))
        .fold(0.0, (a, b) => b);

    // The app sets its own error handlers; the test binding needs its own
    // back at the end.
    final errorWidgetBuilder = ErrorWidget.builder;
    final onFlutterError = FlutterError.onError;
    // ignore: avoid_print
    print('STEP starting the app');
    try {
      await app.main();
      // ignore: avoid_print
      print('STEP main() returned');
      await waitFor(() => find.byType(HomeScreen).evaluate().isNotEmpty,
          'the home screen',
          seconds: 60);
      // ignore: avoid_print
      print('STEP home screen up');
      await hold(1500);
      final home = tester.state<HomeScreenState>(find.byType(HomeScreen));
      home.openPage('browser.tab');
      await hold(1500);
      // ignore: avoid_print
      print('STEP browser tab open, loading the page');
      BrowserScreen.navigate('http://127.0.0.1:${server.port}/page');
      await waitFor(() => events.contains('ready'), 'the page to load');
      await waitFor(() => find.byType(Webview).evaluate().isNotEmpty,
          'the web view');
      await hold(1000);
      final view = tester.getRect(find.byType(Webview).first);
      // ignore: avoid_print
      print('STEP web view at $view');
      final mouse = TestPointer(7, PointerDeviceKind.mouse);

      // 1. The mouse wheel scrolls the page.
      var mark = events.length;
      await tester.sendEventToBinding(mouse.hover(view.center));
      await hold(200);
      for (var i = 0; i < 3; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
        await hold(150);
      }
      await waitFor(() => lastScroll() > 100, 'the wheel to scroll the page');
      // ignore: avoid_print
      print('STEP wheel: page scrolled to ${lastScroll()}');

      // 2. A click on the page gives it the keyboard.
      await tester.sendEventToBinding(mouse.down(view.center));
      await hold(60);
      await tester.sendEventToBinding(mouse.up());
      await waitFor(() => has(mark, 'click='), 'the click on the page');
      // The keyboard moves into the web view's own window (not Flutter's)
      // a little after the click; on a busy PC that can take a while.
      await waitFor(() {
        final f = _focusedWindowOfThisApp();
        return f != 0 && !_className(f).startsWith('FLUTTER');
      }, 'the page to get the keyboard', seconds: 15);
      await hold(300);
      final focus = _focusedWindowOfThisApp();
      // ignore: avoid_print
      print('STEP the keyboard is in ${_className(focus)} ($focus)');

      // 3. Arrow keys move the cursor, not the page.
      final before = lastScroll();
      mark = events.length;
      _postKey(focus, VK_RIGHT, down: true);
      await hold(350);
      _postKey(focus, VK_RIGHT, down: false);
      _postKey(focus, VK_DOWN, down: true);
      await hold(250);
      _postKey(focus, VK_DOWN, down: false);
      await hold(600);
      // ignore: avoid_print
      print('STEP arrows: page saw ${since(mark)}');
      expect(lastScroll(), before, reason: 'the arrows did not scroll');
      expect(has(mark, 'key=Arrow'), isFalse,
          reason: 'the page never got the arrows');

      // 4. Enter clicks where the cursor is: right of and below the mouse
      // click, where the arrows took it.
      mark = events.length;
      _postKey(focus, VK_RETURN, down: true);
      _postKey(focus, VK_RETURN, down: false);
      await waitFor(() => has(mark, 'click='), 'Enter to click at the cursor');
      await hold(1500);
      // ignore: avoid_print
      print('STEP after Enter the page saw ${since(mark)}');
      final click = since(mark).firstWhere((e) => e.startsWith('click='));
      final xy = click.substring(6).split(',').take(2).map(double.parse).toList();
      // ignore: avoid_print
      print('STEP Enter clicked the page at $xy (mouse click was at the '
          'centre, ${view.size.width / 2},${view.size.height / 2})');
      expect(xy[0], greaterThan(view.size.width / 2 + 20),
          reason: 'the cursor moved right');
      expect(xy[1], inInclusiveRange(0, view.size.height),
          reason: 'where the cursor is, inside the view');
      expect(has(mark, 'key=Enter'), isFalse,
          reason: 'the page did not also get Enter');
      expect(since(mark).where((e) => e.startsWith('click=')), hasLength(1),
          reason: 'one click, not two');
      expect(click.contains('synthetic'), isFalse,
          reason: 'a real click, which sites do not ignore');

      // 4b. The mouse is followed again after the cursor's click.
      mark = events.length;
      final elsewhere = view.topLeft + const Offset(150, 400);
      await tester.sendEventToBinding(mouse.hover(elsewhere));
      await waitFor(() => has(mark, 'move=150,400'),
          'the page to see the mouse move after the cursor clicked');

      // 5. Page Down scrolls a screenful.
      final beforePage = lastScroll();
      _postKey(focus, VK_NEXT, down: true);
      _postKey(focus, VK_NEXT, down: false);
      await waitFor(() => lastScroll() > beforePage + view.height * 0.5,
          'Page Down to scroll');
      // ignore: avoid_print
      print('STEP Page Down: $beforePage -> ${lastScroll()}');

      // 6. A text field clicked with the mouse takes the keyboard itself,
      // as in any browser: no typing box, the letters and the arrow keys
      // are the page's.
      final fieldPoint =
          view.topLeft + Offset(view.width / 2, view.height * 0.85);
      mark = events.length;
      await tester.sendEventToBinding(mouse.hover(fieldPoint));
      await tester.sendEventToBinding(mouse.down(fieldPoint));
      await hold(60);
      await tester.sendEventToBinding(mouse.up());
      await waitFor(() => has(mark, 'focus=field'), 'the clicked text field');
      await hold(1500);
      expect(find.byType(AlertDialog).evaluate(), isEmpty,
          reason: 'a mouse click types into the page itself');
      final pageKeys = _focusedWindowOfThisApp();
      for (final c in 'ab'.codeUnits) {
        _postChar(pageKeys, c);
        await hold(80);
      }
      await waitFor(() => has(mark, 'value=ab'), 'typing into the field');
      _postKey(pageKeys, VK_LEFT, down: true);
      _postKey(pageKeys, VK_LEFT, down: false);
      await hold(600);
      // ignore: avoid_print
      print('STEP mouse in the field: page saw ${since(mark)}');
      expect(has(mark, 'key=ArrowLeft'), isTrue,
          reason: 'in a field the arrow keys move its text cursor');
      // Out of the field again: a click on the page.
      mark = events.length;
      await tester.sendEventToBinding(mouse.hover(view.center));
      await tester.sendEventToBinding(mouse.down(view.center));
      await hold(60);
      await tester.sendEventToBinding(mouse.up());
      await waitFor(() => has(mark, 'click='), 'the click out of the field');
      await hold(800);

      // 7. The remote's OK on the field opens the typing box (as on a TV);
      // what is typed there lands in the field, and afterwards the arrows
      // and Enter are the cursor's again.
      final keys = _focusedWindowOfThisApp();
      final fieldMark = events.length;
      var tries = 0;
      while (find.byType(AlertDialog).evaluate().isEmpty) {
        if (++tries > 10) {
          fail('the cursor never reached the field: ${since(fieldMark)}');
        }
        _postKey(keys, VK_DOWN, down: true);
        await hold(150);
        _postKey(keys, VK_DOWN, down: false);
        await hold(300);
        _postKey(keys, VK_RETURN, down: true);
        _postKey(keys, VK_RETURN, down: false);
        await hold(1200);
      }
      // ignore: avoid_print
      print('STEP typing box open after $tries tries: ${since(fieldMark)}');
      await hold(800);
      final typing = _focusedWindowOfThisApp();
      mark = events.length;
      for (final c in 'hi'.codeUnits) {
        _postChar(typing, c);
        await hold(80);
      }
      _postKey(typing, VK_LEFT, down: true);
      _postKey(typing, VK_LEFT, down: false);
      _postChar(typing, 'o'.codeUnitAt(0)); // "hoi": the arrow moved the caret
      await hold(300);
      _postKey(typing, VK_RETURN, down: true);
      _postKey(typing, VK_RETURN, down: false);
      await waitFor(() => has(mark, 'value=hoi'), 'the text in the page field');
      await waitFor(() => find.byType(AlertDialog).evaluate().isEmpty,
          'the typing box to close');
      // ignore: avoid_print
      print('STEP typed into the page: ${since(mark)}');

      await hold(800);
      final after = _focusedWindowOfThisApp();
      mark = events.length;
      _postKey(after, VK_UP, down: true);
      await hold(400);
      _postKey(after, VK_UP, down: false);
      await hold(300);
      _postKey(after, VK_RETURN, down: true);
      _postKey(after, VK_RETURN, down: false);
      await waitFor(() => has(mark, 'click='), 'the cursor to click again');
      // ignore: avoid_print
      print('STEP after typing the page saw ${since(mark)}');
      expect(has(mark, 'key=Arrow'), isFalse,
          reason: 'the arrows belong to the cursor again');
      // The cursor's tap lifts its finger 50 ms later; not after the end.
      await hold(500);
    } finally {
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = onFlutterError;
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// A long page that reports scrolling, clicks, keys and the focused field.
const _page = '''<!doctype html><html><head><title>Remote test</title>
<style>body{margin:0;font:16px sans-serif}
#field{position:fixed;top:75vh;left:5vw;width:90vw;height:20vh}
#tall{height:8000px;background:linear-gradient(#fff,#68a)}</style>
<script>
function log(s){new Image().src='/log?'+s+'&t='+Date.now()+Math.random();}
addEventListener('scroll',function(){log('scroll='+Math.round(scrollY));});
addEventListener('click',function(e){log('click='+e.clientX+','+e.clientY+(e.isTrusted?'':',synthetic'));},true);
addEventListener('pointerdown',function(e){log('down='+e.pointerType+','+e.clientX+','+e.clientY+(e.isTrusted?'':',synthetic'));},true);
addEventListener('keydown',function(e){log('key='+e.key);},true);
addEventListener('mousemove',function(e){if(window.__moves!==false)log('move='+e.clientX+','+e.clientY);},true);
addEventListener('focusin',function(e){if(e.target.id)log('focus='+e.target.id);});
addEventListener('load',function(){log('ready');});
setTimeout(function(){log('hooks='+!!window.__cursorListenersInjected+','+typeof window.__bbCall);},3000);
addEventListener('input',function(e){if(e.target.id==='field')log('value='+e.target.value);},true);
addEventListener('change',function(e){if(e.target.id==='field')log('value='+e.target.value);},true);
</script></head><body><input id="field" placeholder="type here">
<div id="tall"></div></body></html>''';

/// The window of this process that has the keyboard: the web view's own
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
  final extended = vk != VK_RETURN;
  var lParam = 1 | (scan << 16) | (extended ? 1 << 24 : 0);
  if (!down) lParam |= (1 << 30) | (1 << 31);
  // The app's message loop makes the WM_CHAR of Enter itself.
  PostMessage(hwnd, down ? WM_KEYDOWN : WM_KEYUP, vk, lParam);
}

String _className(int hwnd) {
  final buf = wsalloc(256);
  try {
    GetClassName(hwnd, buf, 256);
    return buf.toDartString();
  } finally {
    free(buf);
  }
}

/// A typed character, as the keyboard sends it.
void _postChar(int hwnd, int char) {
  final vk = VkKeyScan(char) & 0xff;
  final scan = MapVirtualKey(vk, MAPVK_VK_TO_VSC);
  final lParam = 1 | (scan << 16);
  // Only the key presses, as a keyboard sends them: the app's message loop
  // makes the WM_CHAR itself (TranslateMessage), so posting one too would
  // type every letter twice.
  PostMessage(hwnd, WM_KEYDOWN, vk, lParam);
  PostMessage(hwnd, WM_KEYUP, vk, lParam | (1 << 30) | (1 << 31));
}

class _SandboxPaths extends PathProviderPlatform {
  _SandboxPaths(this.root);

  final String root;

  String _dir(String name) {
    final dir = Directory(p.join(root, name))..createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _dir('temp');
  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');
  @override
  Future<String?> getLibraryPath() async => _dir('library');
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');
  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');
  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');
}

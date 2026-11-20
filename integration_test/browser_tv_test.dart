import 'dart:io';

import 'package:convert_the_spire_reborn/main.dart' as app;
import 'package:convert_the_spire_reborn/src/screens/browser_screen.dart';
import 'package:convert_the_spire_reborn/src/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The browser inside the whole app on Android TV, with the remote: the
/// D-pad moves the cursor (the page never gets the arrows), OK clicks once
/// where the cursor is, Page Down scrolls, and OK on a text field opens the
/// typing box, whose text lands in the field.
///
/// The remote's keys arrive the way MainActivity hands them over (the
/// `onDpadKey` calls on com.yourapp/cursor_keys), so this needs an Android
/// TV device or emulator:
///
///   flutter test -d emulator-5554 integration_test/browser_tv_test.dart
void main() {
  if (!Platform.isAndroid) return;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the TV remote in the real app', (tester) async {
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

    // A key of the remote, as MainActivity.dispatchKeyEvent passes it on.
    Future<void> remote(int keyCode, String action) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'com.yourapp/cursor_keys',
          const StandardMethodCodec().encodeMethodCall(MethodCall(
              'onDpadKey', {'keyCode': keyCode, 'action': action})),
          (_) {},
        );
    Future<void> press(int keyCode, {int ms = 0}) async {
      await remote(keyCode, 'down');
      if (ms > 0) await hold(ms);
      await remote(keyCode, 'up');
    }

    const dpadUp = 19, dpadDown = 20, dpadRight = 22, dpadCenter = 23;
    const pageDown = 93;

    final errorWidgetBuilder = ErrorWidget.builder;
    final onFlutterError = FlutterError.onError;
    // ignore: avoid_print
    print('STEP starting the app');
    try {
      await app.main();
      await waitFor(() => find.byType(HomeScreen).evaluate().isNotEmpty,
          'the home screen',
          seconds: 90);
      // ignore: avoid_print
      print('STEP home screen up');
      await hold(2500);
      final home = tester.state<HomeScreenState>(find.byType(HomeScreen));
      home.openPage('browser.tab');
      await hold(2500);
      BrowserScreen.navigate('http://127.0.0.1:${server.port}/page');
      await waitFor(() => events.contains('ready'), 'the page to load',
          seconds: 45);
      final webView = find.byKey(const ValueKey('browser_webview'));
      await waitFor(() => webView.evaluate().isNotEmpty, 'the web view');
      await hold(4000); // the app's page scripts go in after the load
      final view = tester.getRect(webView.first);
      // ignore: avoid_print
      print('STEP web view at $view; page says ${events.toList()}');

      // 1. The D-pad moves the cursor; the page gets no arrows, no scroll.
      var mark = events.length;
      await press(dpadRight, ms: 300);
      await hold(800);
      // ignore: avoid_print
      print('STEP right: page saw ${since(mark)}');
      expect(has(mark, 'key='), isFalse, reason: 'the page got no keys');
      expect(has(mark, 'scroll='), isFalse, reason: 'the D-pad did not scroll');

      // 2. OK clicks once where the cursor is (on the big target up top).
      mark = events.length;
      await press(dpadCenter);
      await waitFor(() => has(mark, 'click='), 'OK to click');
      await hold(2500); // a second click, if there is one, comes by now
      final clicks = since(mark).where((e) => e.startsWith('click=')).toList();
      // ignore: avoid_print
      print('STEP OK: page saw ${since(mark)}');
      expect(clicks, hasLength(1), reason: 'one click per OK, not two');
      expect(clicks.first.contains('synthetic'), isFalse,
          reason: 'a real click (a touch), which sites do not ignore');
      expect(has(mark, 'down=touch'), isTrue, reason: 'a finger touch');
      final xy = clicks.first.substring(6).split(',').take(2).map(double.parse);
      // ignore: avoid_print
      print('STEP OK clicked at ${xy.toList()} in a ${view.size} view');
      final at = xy.toList();
      expect(at[0], inInclusiveRange(380, 700), reason: 'right of the start');
      expect(at[1], inInclusiveRange(150, 250), reason: 'at the cursor');

      // 3. Page Down scrolls a screenful.
      final before = lastScroll();
      await press(pageDown);
      await waitFor(() => lastScroll() > before + view.height * 0.4,
          'Page Down to scroll');
      // ignore: avoid_print
      print('STEP Page Down: $before -> ${lastScroll()}');

      // 4. Down to the text field (the lower part of the page), OK: the
      // typing box opens; its text goes into the field.
      final fieldMark = events.length;
      var tries = 0;
      while (!has(fieldMark, 'focus=field') &&
          find.byType(AlertDialog).evaluate().isEmpty) {
        if (++tries > 12) fail('never reached the field: ${since(fieldMark)}');
        await press(dpadDown, ms: 250);
        await hold(400);
        await press(dpadCenter);
        await hold(1200);
      }
      await waitFor(() => find.byType(AlertDialog).evaluate().isNotEmpty,
          'the typing box');
      // ignore: avoid_print
      print('STEP typing box open after $tries tries: ${since(fieldMark)}');
      await hold(800);
      mark = events.length;
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'hoi');
      await hold(300);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(() => has(mark, 'value=hoi'), 'the text in the page field');
      await waitFor(() => find.byType(AlertDialog).evaluate().isEmpty,
          'the typing box to close');
      // ignore: avoid_print
      print('STEP typed into the page: ${since(mark)}');

      // 5. After that the D-pad is the cursor's again and OK clicks once.
      await hold(1500);
      mark = events.length;
      await press(dpadUp, ms: 350);
      await hold(400);
      await press(dpadCenter);
      await waitFor(() => has(mark, 'click='), 'the cursor to click again');
      await hold(2500);
      // ignore: avoid_print
      print('STEP after typing the page saw ${since(mark)}');
      expect(has(mark, 'key='), isFalse, reason: 'the page got no keys');
      expect(since(mark).where((e) => e.startsWith('click=')), hasLength(1),
          reason: 'one click per OK');
      expect(has(mark, 'click=') && !since(mark).any((e) =>
              e.startsWith('click=') && e.contains('synthetic')), isTrue,
          reason: 'a real click again');
      await hold(500); // the cursor's tap lifts its finger 50 ms later
    } finally {
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = onFlutterError;
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// A big click target over the top half, a big text field below it, and a
/// tall page to scroll; it reports what it receives.
const _page = '''<!doctype html><html><head><title>Remote test</title>
<meta name="viewport" content="width=device-width">
<style>body{margin:0;font:16px sans-serif}
#target{position:fixed;top:0;left:0;right:0;height:50vh;background:#cde}
#field{position:fixed;top:62vh;left:2vw;width:94vw;height:30vh;font-size:24px}
#tall{height:8000px;background:linear-gradient(#fff,#68a)}</style>
<script>
function log(s){new Image().src='/log?'+s+'&t='+Date.now()+Math.random();}
addEventListener('scroll',function(){log('scroll='+Math.round(scrollY));});
addEventListener('click',function(e){log('click='+Math.round(e.clientX)+','+Math.round(e.clientY)+','+(e.target.id||e.target.tagName)+(e.isTrusted?'':',synthetic'));},true);
addEventListener('pointerdown',function(e){log('down='+e.pointerType+(e.isTrusted?'':',synthetic'));},true);
addEventListener('keydown',function(e){log('key='+e.key);},true);
addEventListener('focusin',function(e){if(e.target.id)log('focus='+e.target.id);});
addEventListener('load',function(){log('ready');});
setTimeout(function(){log('hooks='+!!window.__cursorListenersInjected+','+typeof window.__bbCall);},3000);
addEventListener('input',function(e){if(e.target.id==='field')log('value='+e.target.value);},true);
addEventListener('change',function(e){if(e.target.id==='field')log('value='+e.target.value);},true);
</script></head><body><div id="target"></div>
<textarea id="field" placeholder="type here"></textarea>
<div id="tall"></div></body></html>''';

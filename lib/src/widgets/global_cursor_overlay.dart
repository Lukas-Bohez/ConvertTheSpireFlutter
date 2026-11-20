import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'cursor_style.dart';

/// Global cursor overlay that covers the entire app.
/// Always active, always visible, handles all D-pad input.
/// Implements dual tap paths: Flutter gesture binding for Flutter UI,
/// and JS elementFromPoint for WebViews.
class GlobalCursorOverlay extends StatefulWidget {
  final Widget child;

  static Future<void> Function(Offset position)? _webViewTapCallback;
  static Future<bool> Function(double deltaY, Offset position)?
      _webViewScrollCallback;

  /// Lets a WebView take the cursor's clicks and scrolling. [onScroll]
  /// returns false when the page is not what the cursor is over (the new-tab
  /// page, a dialog), and the scroll then goes to the Flutter widget there.
  /// Call without arguments to take the callbacks back.
  static void registerWebViewCallbacks({
    Future<void> Function(Offset position)? onTap,
    Future<bool> Function(double deltaY, Offset position)? onScroll,
  }) {
    _webViewTapCallback = onTap;
    _webViewScrollCallback = onScroll;
  }

  static bool Function(LogicalKeyboardKey key, bool isDown)? _remoteKeyHandler;

  /// A remote key the WebView took from the page and handed over: on
  /// Windows the page has the keyboard once it is clicked, and the PC's
  /// arrow keys still have to act as the TV remote. Returns whether the
  /// cursor used it.
  static bool handleRemoteKey(LogicalKeyboardKey key, {required bool isDown}) =>
      _remoteKeyHandler?.call(key, isDown) ?? false;

  const GlobalCursorOverlay({super.key, required this.child});

  @override
  State<GlobalCursorOverlay> createState() => _GlobalCursorOverlayState();
}

class _GlobalCursorOverlayState extends State<GlobalCursorOverlay>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _keyChannel =
      MethodChannel('com.yourapp/cursor_keys');
  static const MethodChannel _platformChannel =
      MethodChannel('convert_the_spire/saf');

  Offset _position = const Offset(400, 300);
  Offset _velocity = Offset.zero;
  Offset _direction = Offset.zero;
  late Ticker _ticker;
  Size _viewportSize = Size.zero;
  Duration _lastElapsed = Duration.zero;
  bool _isAndroidTV = false;

  // Auto-hide timer state
  bool _cursorVisible = false;
  Timer? _hideTimer;

  static const double _maxSpeed = 1200.0;
  static const double _acceleration = 3600.0;
  static const double _friction = 8.0;
  static const double _cursorRadius = 12.0;
  static const double _edgeScrollZone = 80.0;
  static const double _edgeScrollSpeed = 600.0;

  // Remote keys that scroll a screenful, so a long page does not need the
  // cursor dragged to the edge: page up / down and channel up / down.
  static const _pageUpKeys = {92, 166};
  static const _pageDownKeys = {93, 167};
  static const Duration _hideDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    // Runs only while the cursor moves (see _startMoving). Always running,
    // it had the app draw a new frame 60 times a second for as long as it
    // was open, even with nothing on screen changing.
    _ticker = createTicker(_onTick);
    if (!kIsWeb && _isDesktopPlatform) {
      _isAndroidTV = true;
      HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
      GlobalCursorOverlay._remoteKeyHandler = _onRemoteKey;
      return;
    }
    _detectAndroidTV();
  }

  Future<void> _detectAndroidTV() async {
    var isTV = false;
    try {
      isTV = await _platformChannel.invokeMethod<bool>('isAndroidTV') ?? false;
    } catch (_) {
      isTV = false;
    }

    if (!mounted) return;
    setState(() {
      _isAndroidTV = isTV;
    });
    _keyChannel.setMethodCallHandler(_isAndroidTV ? _onNativeKeyEvent : null);
  }

  void _startMoving() {
    if (_ticker.isActive) return;
    _lastElapsed = Duration.zero;
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    if (!kIsWeb && _isDesktopPlatform) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
      if (GlobalCursorOverlay._remoteKeyHandler == _onRemoteKey) {
        GlobalCursorOverlay._remoteKeyHandler = null;
      }
    }
    _ticker.dispose();
    _hideTimer?.cancel();
    _keyChannel.setMethodCallHandler(null);
    super.dispose();
  }

  bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get _cursorEnabled => _isDesktopPlatform || _isAndroidTV;

  bool _onHardwareKeyEvent(KeyEvent event) {
    if (!_cursorEnabled) return false;

    final isDown = event is KeyDownEvent;
    final isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return false;
    return _handleKey(event.logicalKey, isDown: isDown, isUp: isUp);
  }

  bool _onRemoteKey(LogicalKeyboardKey key, bool isDown) {
    if (!mounted || !_cursorEnabled) return false;
    return _handleKey(key, isDown: isDown, isUp: !isDown, fromPage: true);
  }

  /// The PC keyboard as a TV remote: arrows move the cursor, Enter clicks
  /// where it is, Page Up / Page Down scroll a screenful. [fromPage] keys
  /// come from the web page, which only hands them over while none of its
  /// text fields is focused, so Flutter's focus says nothing about them.
  bool _handleKey(LogicalKeyboardKey key,
      {required bool isDown, required bool isUp, bool fromPage = false}) {
    final isArrow = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    // Arrow keys in a text field move its caret, not the cursor, which used
    // to appear and wander off while someone typed.
    if (isArrow && isDown && !fromPage && _isTextFieldFocused()) {
      return false;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _direction =
          Offset(isDown ? -1 : (isUp ? 0 : _direction.dx), _direction.dy);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _direction =
          Offset(isDown ? 1 : (isUp ? 0 : _direction.dx), _direction.dy);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _direction =
          Offset(_direction.dx, isDown ? -1 : (isUp ? 0 : _direction.dy));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _direction =
          Offset(_direction.dx, isDown ? 1 : (isUp ? 0 : _direction.dy));
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (!fromPage && _isTextFieldFocused()) {
        return false;
      }
      if (isDown) {
        // Only while the cursor shows, so the click goes where it is seen.
        // Hidden, Enter clicked wherever the cursor was last, maybe long ago,
        // or at its starting point: pressing Enter on a dialog clicked
        // whatever was there. Hidden, Enter now just shows it.
        if (_cursorVisible) {
          _fireTap();
        }
        _resetHideTimer();
      }
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      if (!fromPage && _isTextFieldFocused()) return false;
      if (isDown) {
        final sign = key == LogicalKeyboardKey.pageUp ? -1 : 1;
        _resetHideTimer();
        unawaited(_injectScroll(sign * _viewportSize.height * 0.85, _position));
      }
    } else {
      return false;
    }

    if (isDown && isArrow) {
      _resetHideTimer();
      _startMoving();
    }
    return true;
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_cursorVisible) {
      setState(() => _cursorVisible = true);
    }
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _cursorVisible = false);
    });
  }

  Future<dynamic> _onNativeKeyEvent(MethodCall call) async {
    if (!_cursorEnabled) return;
    if (call.method != 'onDpadKey') return;

    final arguments = call.arguments;
    if (arguments is! Map) return;

    final keyCode = arguments['keyCode'] as int?;
    final action = arguments['action'] as String?;
    if (keyCode == null || action == null) return;

    final isDown = action == 'down';
    final isUp = action == 'up';

    // Debug: log native key events to help verify interception and Flutter handling
    try {
      debugPrint('GlobalCursorOverlay: onDpadKey key=$keyCode action=$action');
    } catch (_) {}

    const dpadUp = 19;
    const dpadDown = 20;
    const dpadLeft = 21;
    const dpadRight = 22;
    const dpadCenter = 23;
    const enter = 66;
    const numEnter = 160;

    switch (keyCode) {
      case dpadLeft:
        _direction =
            Offset(isDown ? -1 : (isUp ? 0 : _direction.dx), _direction.dy);
        break;
      case dpadRight:
        _direction =
            Offset(isDown ? 1 : (isUp ? 0 : _direction.dx), _direction.dy);
        break;
      case dpadUp:
        _direction =
            Offset(_direction.dx, isDown ? -1 : (isUp ? 0 : _direction.dy));
        break;
      case dpadDown:
        _direction =
            Offset(_direction.dx, isDown ? 1 : (isUp ? 0 : _direction.dy));
        break;
      case dpadCenter:
      case enter:
      case numEnter:
        if (isDown) {
          _fireTap();
        }
        break;
      default:
        if (isDown && _pageUpKeys.contains(keyCode)) {
          _resetHideTimer();
          unawaited(_injectScroll(-_viewportSize.height * 0.85, _position));
        } else if (isDown && _pageDownKeys.contains(keyCode)) {
          _resetHideTimer();
          unawaited(_injectScroll(_viewportSize.height * 0.85, _position));
        }
        return;
    }

    if (isDown &&
        (keyCode == dpadLeft ||
            keyCode == dpadRight ||
            keyCode == dpadUp ||
            keyCode == dpadDown)) {
      _resetHideTimer();
      _startMoving();
    }
  }

  void _fireTap() {
    if (!_cursorEnabled) return;
    final position = _position;

    try {
      debugPrint('GlobalCursorOverlay: _fireTap at=$position');
    } catch (_) {}

    // Inject a touch-style pointer down/up sequence using logical coordinates.
    // Flutter pointer events are handled in logical pixels.
    const int pointerId = 1;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointerId,
        position: position,
        kind: PointerDeviceKind.touch,
        buttons: kPrimaryButton,
      ),
    );
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            pointer: pointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
      }
    });

    // Also dispatch the WebView JS tap path (logical coordinates)
    unawaited(GlobalCursorOverlay._webViewTapCallback?.call(_position));
  }

  /// Whether the keyboard is typing into a text field. The focus belongs to
  /// a Focus widget inside the EditableText, so the field is looked up from
  /// there; checking the focused widget itself never matched, and Enter in
  /// a text field also clicked wherever the cursor was.
  bool _isTextFieldFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _onTick(Duration elapsed) {
    if (!_cursorEnabled) return;
    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    var accel = _direction * _acceleration;
    if (_velocity != Offset.zero) {
      accel = accel - (_velocity * _friction);
    }

    _velocity = _velocity + accel * dt;

    final speed = _velocity.distance;
    if (speed > _maxSpeed) {
      _velocity = _velocity / speed * _maxSpeed;
    }

    if (_direction.dx == 0 && _velocity.dx.abs() < 5) {
      _velocity = Offset(0, _velocity.dy);
    }
    if (_direction.dy == 0 && _velocity.dy.abs() < 5) {
      _velocity = Offset(_velocity.dx, 0);
    }

    _position = _position + _velocity * dt;

    // If the cursor is moving, keep it visible by resetting the hide timer.
    if (_velocity.distance > 0.5) {
      _resetHideTimer();
    }

    if (_viewportSize != Size.zero) {
      double px = _position.dx;
      double py = _position.dy;

      // Vertical edge scroll
      if (py >= _viewportSize.height - _edgeScrollZone && _direction.dy > 0) {
        py = _viewportSize.height - _edgeScrollZone;
        _injectScroll(_edgeScrollSpeed * dt, _position);
      } else if (py <= _edgeScrollZone && _direction.dy < 0) {
        py = _edgeScrollZone;
        _injectScroll(-_edgeScrollSpeed * dt, _position);
      } else {
        py = py.clamp(0, _viewportSize.height);
      }

      px = px.clamp(0, _viewportSize.width);

      _position = Offset(px, py);
    }

    if (_direction == Offset.zero && _velocity == Offset.zero) {
      _ticker.stop();
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Inject scroll via JavaScript if a WebView is active, or default to window scroll.
  Future<void> _injectScroll(double deltaY, Offset cursorPosition) async {
    if (!_cursorEnabled) return;
    try {
      debugPrint(
          'GlobalCursorOverlay: _injectScroll deltaY=$deltaY at=$cursorPosition');
      final callback = GlobalCursorOverlay._webViewScrollCallback;
      if (callback != null && await callback(deltaY, cursorPosition)) {
        return;
      }

      GestureBinding.instance.handlePointerEvent(
        PointerScrollEvent(
          position: cursorPosition,
          scrollDelta: Offset(0, deltaY),
        ),
      );
    } catch (_) {
      // WebView not available or call failed; ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_cursorEnabled) return widget.child;
    final cursorStyle = cursorStyleFor(Theme.of(context).brightness);
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            widget.child,
            if (_cursorVisible)
              Positioned(
                left: _position.dx - _cursorRadius,
                top: _position.dy - _cursorRadius,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: const Size(_cursorRadius * 2, _cursorRadius * 2),
                    painter: _CursorPainter(cursorStyle),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CursorPainter extends CustomPainter {
  final CursorStyle style;

  _CursorPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.fillColor
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = style.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final radius = size.width / 2;
    final center = Offset(radius, radius);

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius, border);

    // Draw crosshair
    final crossPaint = Paint()
      ..color = style.accentColor
      ..strokeWidth = 0.8;
    canvas.drawLine(
        Offset(radius, radius - 6), Offset(radius, radius + 6), crossPaint);
    canvas.drawLine(
        Offset(radius - 6, radius), Offset(radius + 6, radius), crossPaint);
  }

  @override
  bool shouldRepaint(_CursorPainter oldDelegate) => false;
}

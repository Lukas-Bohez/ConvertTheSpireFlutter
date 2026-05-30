import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'cursor_style.dart';

/// Global cursor overlay that covers the entire app.
/// Always active, always visible, handles all D-pad input.
/// Implements dual tap paths: Flutter gesture binding for Flutter UI,
/// and JS elementFromPoint for WebViews.
class GlobalCursorOverlay extends StatefulWidget {
  final Widget child;

  static Future<void> Function(Offset position)? _webViewTapCallback;
  static Future<void> Function(double deltaY, Offset position)?
      _webViewScrollCallback;

  static void registerWebViewCallbacks({
    Future<void> Function(Offset position)? onTap,
    Future<void> Function(double deltaY, Offset position)? onScroll,
  }) {
    _webViewTapCallback = onTap;
    _webViewScrollCallback = onScroll;
  }

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
  static const double _edgeScrollSpeed = 400.0;
  static const Duration _hideDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (!kIsWeb && _isDesktopPlatform) {
      _isAndroidTV = true;
      HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
      if (!_ticker.isActive) _ticker.start();
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
    if (_isAndroidTV && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && _isDesktopPlatform) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
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

    final key = event.logicalKey;
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
      if (_isTextFieldFocused()) {
        return false;
      }
      if (isDown) _fireTap();
    } else {
      return false;
    }

    if (isDown &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      _resetHideTimer();
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
        return;
    }

    if (isDown &&
        (keyCode == dpadLeft ||
            keyCode == dpadRight ||
            keyCode == dpadUp ||
            keyCode == dpadDown)) {
      _resetHideTimer();
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

  bool _isTextFieldFocused() {
    final focused = FocusManager.instance.primaryFocus;
    final widget = focused?.context?.widget;
    return widget is EditableText;
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
      if (callback != null) {
        await callback(deltaY, cursorPosition);
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

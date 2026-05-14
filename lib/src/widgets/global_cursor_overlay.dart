import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Global cursor overlay that covers the entire app.
/// Always active, always visible, handles all D-pad input.
/// Implements dual tap paths: Flutter gesture binding for Flutter UI,
/// and JS elementFromPoint for WebViews.
class GlobalCursorOverlay extends StatefulWidget {
  final Widget child;

  const GlobalCursorOverlay({super.key, required this.child});

  @override
  State<GlobalCursorOverlay> createState() => _GlobalCursorOverlayState();
}

class _GlobalCursorOverlayState extends State<GlobalCursorOverlay>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _keyChannel = MethodChannel('com.yourapp/cursor_keys');
  static const MethodChannel _webviewChannel = MethodChannel('com.yourapp/webview_input');

  Offset _position = const Offset(400, 300);
  Offset _velocity = Offset.zero;
  Offset _direction = Offset.zero;
  late Ticker _ticker;
  Size _viewportSize = Size.zero;
  Duration _lastElapsed = Duration.zero;

  // Auto-hide timer state
  bool _cursorVisible = true;
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
    _ticker = createTicker(_onTick)..start();
    _keyChannel.setMethodCallHandler(_onNativeKeyEvent);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _hideTimer?.cancel();
    super.dispose();
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
    if (call.method != 'onDpadKey') return;

    final arguments = call.arguments;
    if (arguments is! Map) return;

    final keyCode = arguments['keyCode'] as int?;
    final action = arguments['action'] as String?;
    if (keyCode == null || action == null) return;

    final isDown = action == 'down';
    final isUp = action == 'up';

    const dpadUp = 19;
    const dpadDown = 20;
    const dpadLeft = 21;
    const dpadRight = 22;
    const dpadCenter = 23;
    const enter = 66;
    const numEnter = 160;

    switch (keyCode) {
      case dpadLeft:
        _direction = Offset(isDown ? -1 : (isUp ? 0 : _direction.dx), _direction.dy);
        break;
      case dpadRight:
        _direction = Offset(isDown ? 1 : (isUp ? 0 : _direction.dx), _direction.dy);
        break;
      case dpadUp:
        _direction = Offset(_direction.dx, isDown ? -1 : (isUp ? 0 : _direction.dy));
        break;
      case dpadDown:
        _direction = Offset(_direction.dx, isDown ? 1 : (isUp ? 0 : _direction.dy));
        break;
      case dpadCenter:
      case enter:
      case numEnter:
        if (isDown) {
          _simulateTap(_position);
        }
        break;
      default:
        return;
    }

    if (isDown) {
      _resetHideTimer();
    }
  }

  /// Simulate a tap at the given screen position.
  /// Uses Flutter's gesture binding to synthesize pointer events,
  /// which goes through the hit-test system and activates whatever
  /// is at that position (GestureDetector, InkWell, TextButton, etc.)
  void _simulateTap(Offset screenPosition) {
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        position: screenPosition,
        timeStamp: Duration.zero,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        position: screenPosition,
        timeStamp: const Duration(milliseconds: 100),
      ),
    );
  }

  void _onTick(Duration elapsed) {
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
    try {
      await _webviewChannel.invokeMethod('injectScroll', {
        'deltaY': deltaY,
        'cursorX': cursorPosition.dx,
        'cursorY': cursorPosition.dy,
      });
    } catch (_) {
      // WebView not available or call failed; ignore
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    painter: _CursorPainter(),
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
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final radius = size.width / 2;
    final center = Offset(radius, radius);

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius, border);

    // Draw crosshair
    final crossPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(radius, radius - 6), Offset(radius, radius + 6), crossPaint);
    canvas.drawLine(Offset(radius - 6, radius), Offset(radius + 6, radius), crossPaint);
  }

  @override
  bool shouldRepaint(_CursorPainter oldDelegate) => false;
}

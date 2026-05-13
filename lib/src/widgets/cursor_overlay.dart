import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class CursorOverlay extends StatefulWidget {
  final Widget child;
  final bool active;
  final Future<void> Function(Offset)? onTap;
  final Future<void> Function(double deltaY, Offset cursorPosition)? onScroll;

  const CursorOverlay({
    super.key,
    required this.child,
    this.active = true,
    this.onTap,
    this.onScroll,
  });

  @override
  State<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends State<CursorOverlay>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _nativeKeyChannel =
      MethodChannel('com.yourapp/cursor_keys');
  static bool _nativeKeyChannelInstalled = false;
  static final List<_CursorOverlayState> _activeKeyHandlers =
      <_CursorOverlayState>[];

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
    _installNativeKeyChannelHandler();
    if (widget.active) {
      _registerAsActiveKeyHandler();
    }
  }

  @override
  void didUpdateWidget(covariant CursorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _registerAsActiveKeyHandler();
      _lastElapsed = Duration.zero;
      _resetHideTimer();
      // Reset cursor position to center of viewport (or fallback)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final center = _viewportSize == Size.zero
            ? const Offset(400, 300)
            : Offset(_viewportSize.width / 2, _viewportSize.height / 2);
        _position = center;
        _velocity = Offset.zero;
        _direction = Offset.zero;
        setState(() {});
      });
    } else if (!widget.active && oldWidget.active) {
      _unregisterAsActiveKeyHandler();
    }
  }

  @override
  void dispose() {
    _unregisterAsActiveKeyHandler();
    _ticker.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  static void _installNativeKeyChannelHandler() {
    if (_nativeKeyChannelInstalled) return;
    _nativeKeyChannelInstalled = true;
    _nativeKeyChannel.setMethodCallHandler((call) async {
      final handler = _activeKeyHandlers.isNotEmpty ? _activeKeyHandlers.last : null;
      if (handler == null || !handler.mounted || !handler.widget.active) {
        return;
      }
      return handler._onNativeKeyEvent(call);
    });
  }

  void _registerAsActiveKeyHandler() {
    _activeKeyHandlers.remove(this);
    _activeKeyHandlers.add(this);
  }

  void _unregisterAsActiveKeyHandler() {
    _activeKeyHandlers.remove(this);
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_cursorVisible) setState(() => _cursorVisible = true);
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _cursorVisible = false);
    });
  }

  Future<dynamic> _onNativeKeyEvent(MethodCall call) async {
    if (call.method != 'onDpadKey' || !widget.active) return;

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
        if (isDown && widget.onTap != null) {
          await widget.onTap!(_position);
        }
        break;
      default:
        return;
    }

    if (isDown) {
      _resetHideTimer();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (!widget.active || dt <= 0 || dt > 0.1) return;

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
      // Edge scroll handling: if cursor nears an edge and direction pushes
      // further, trigger onScroll instead of moving cursor off-screen.
      double px = _position.dx;
      double py = _position.dy;

      // Vertical edge scroll
      if (py >= _viewportSize.height - _edgeScrollZone && _direction.dy > 0) {
        // Stay within bottom edge zone and request scroll down
        py = _viewportSize.height - _edgeScrollZone;
        widget.onScroll?.call(_edgeScrollSpeed * dt, _position);
      } else if (py <= _edgeScrollZone && _direction.dy < 0) {
        py = _edgeScrollZone;
        widget.onScroll?.call(-_edgeScrollSpeed * dt, _position);
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            widget.child,
            if (widget.active && _cursorVisible)
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
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width / 2, paint);
    canvas.drawCircle(center, size.width / 2, border);
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) => false;
}
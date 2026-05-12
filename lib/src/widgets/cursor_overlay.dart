import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class CursorOverlay extends StatefulWidget {
  final Widget child;
  final bool active;
  final Future<void> Function(Offset) onTap;

  const CursorOverlay({
    super.key,
    required this.child,
    required this.active,
    required this.onTap,
  });

  @override
  State<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends State<CursorOverlay>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(400, 300);
  Offset _velocity = Offset.zero;
  Offset _direction = Offset.zero;
  late Ticker _ticker;
  Size _viewportSize = Size.zero;
  Duration _lastElapsed = Duration.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'cursor_overlay');

  static const double _maxSpeed = 1200.0;
  static const double _acceleration = 3600.0;
  static const double _friction = 8.0;
  static const double _cursorRadius = 12.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant CursorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _lastElapsed = Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (!widget.active || dt <= 0) return;

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
      _position = Offset(
        _position.dx.clamp(0, _viewportSize.width),
        _position.dy.clamp(0, _viewportSize.height),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.active) return KeyEventResult.ignored;

    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final isUp = event is KeyUpEvent;

    var dx = _direction.dx;
    var dy = _direction.dy;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        dx = isDown ? -1 : (isUp ? 0 : dx);
        break;
      case LogicalKeyboardKey.arrowRight:
        dx = isDown ? 1 : (isUp ? 0 : dx);
        break;
      case LogicalKeyboardKey.arrowUp:
        dy = isDown ? -1 : (isUp ? 0 : dy);
        break;
      case LogicalKeyboardKey.arrowDown:
        dy = isDown ? 1 : (isUp ? 0 : dy);
        break;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (isDown) {
          widget.onTap(_position);
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }

    _direction = Offset(dx, dy);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Focus(
          focusNode: _focusNode,
          autofocus: widget.active,
          canRequestFocus: widget.active,
          onKeyEvent: _handleKey,
          child: Stack(
            children: [
              widget.child,
              if (widget.active)
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
          ),
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
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class CursorOverlay extends StatefulWidget {
  final Widget child;
  final bool active;
  final Future<void> Function(Offset)? onTap;
  final Future<void> Function(double deltaY)? onScroll;

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
  static const double _edgeScrollZone = 80.0;
  static const double _edgeScrollSpeed = 400.0;

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
      // Reset cursor position to center of viewport (or fallback)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final center = _viewportSize == Size.zero
            ? const Offset(400, 300)
            : Offset(_viewportSize.width / 2, _viewportSize.height / 2);
        _position = center;
        _velocity = Offset.zero;
        _direction = Offset.zero;
        _focusNode.requestFocus();
        setState(() {});
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
      // Edge scroll handling: if cursor nears an edge and direction pushes
      // further, trigger onScroll instead of moving cursor off-screen.
      double px = _position.dx;
      double py = _position.dy;

      // Vertical edge scroll
      if (py >= _viewportSize.height - _edgeScrollZone && _direction.dy > 0) {
        // Stay within bottom edge zone and request scroll down
        py = _viewportSize.height - _edgeScrollZone;
        widget.onScroll?.call(_edgeScrollSpeed * dt);
      } else if (py <= _edgeScrollZone && _direction.dy < 0) {
        py = _edgeScrollZone;
        widget.onScroll?.call(-_edgeScrollSpeed * dt);
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
        if (isDown && widget.onTap != null) {
          widget.onTap!(_position);
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }

    _direction = Offset(dx, dy);

    // When cursor mode is active we MUST consume directional keys so the
    // Flutter focus traversal system does not move focus — cursor is the
    // active input mode.
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
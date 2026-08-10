import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AmbientScenePainter extends CustomPainter {
  AmbientScenePainter({required this.shader, required this.time});

  final ui.FragmentShader shader;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant AmbientScenePainter oldDelegate) =>
      oldDelegate.time != time;
}

class AmbientScene extends StatefulWidget {
  const AmbientScene({super.key});

  @override
  State<AmbientScene> createState() => _AmbientSceneState();
}

class _AmbientSceneState extends State<AmbientScene>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _time = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadShader();
  }

  void _onTick(Duration elapsed) {
    if (mounted) setState(() => _time = elapsed.inMicroseconds / 1e6);
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'assets/shaders/ambient_scene.frag',
      );
      if (mounted) setState(() => _shader = program.fragmentShader());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Ambient view failed to load:\n$_error',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_shader == null) return const ColoredBox(color: Colors.black);
    return CustomPaint(
      painter: AmbientScenePainter(shader: _shader!, time: _time),
      size: Size.infinite,
    );
  }
}

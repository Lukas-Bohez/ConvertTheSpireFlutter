import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps [child] with extra padding that keeps content clear of a TV's
/// overscan region, on top of whatever a normal [SafeArea] already does.
///
/// Android TV does not report overscan through [MediaQuery.viewPadding]
/// the way a phone reports its notch or status bar - overscan is invisible
/// to Flutter entirely, so a plain [SafeArea] gives zero protection
/// against it. Screens that place important content near the edges
/// (titles, action buttons, page indicators) should wrap their content in
/// [TvSafeArea] as well.
///
/// TV detection reuses the same native `isAndroidTV` platform-channel call
/// already used by `GlobalCursorOverlay`
/// (lib/src/widgets/global_cursor_overlay.dart), so this always agrees
/// with however the rest of the app is already deciding "is this a
/// television". On every other platform this widget is a no-op and simply
/// returns [child] unchanged.
///
/// See ONBOARDING_UX_REDESIGN.md for why this was added and where else it
/// could usefully be reused.
class TvSafeArea extends StatefulWidget {
  final Widget child;

  /// Fraction of the shorter screen dimension reserved on every edge when
  /// running on a TV. 0.05 (5%) matches Android's own TV design guidance
  /// for overscan-safe margins.
  final double overscanFraction;

  const TvSafeArea({
    super.key,
    required this.child,
    this.overscanFraction = 0.05,
  });

  @override
  State<TvSafeArea> createState() => _TvSafeAreaState();
}

class _TvSafeAreaState extends State<TvSafeArea> {
  // Same channel GlobalCursorOverlay already talks to - see
  // lib/src/widgets/global_cursor_overlay.dart. Kept identical on purpose
  // so both widgets can only ever agree about whether this is a TV.
  static const MethodChannel _platformChannel =
      MethodChannel('convert_the_spire/saf');

  bool _isAndroidTV = false;

  @override
  void initState() {
    super.initState();
    _detectAndroidTV();
  }

  Future<void> _detectAndroidTV() async {
    var isTV = false;
    try {
      isTV = await _platformChannel.invokeMethod<bool>('isAndroidTV') ?? false;
    } catch (_) {
      isTV = false;
    }
    if (!mounted || isTV == _isAndroidTV) return;
    setState(() => _isAndroidTV = isTV);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroidTV) return widget.child;

    final size = MediaQuery.of(context).size;
    final margin = size.shortestSide * widget.overscanFraction;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin, vertical: margin),
      child: widget.child,
    );
  }
}

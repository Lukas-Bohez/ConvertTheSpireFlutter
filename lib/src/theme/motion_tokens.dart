// Intended path: lib/src/theme/motion_tokens.dart
//
// Centralized motion timing & easing tokens for Convert the Spire Reborn /
// BitPlayer, modeled after IBM Design Language's motion.duration.* /
// motion.curve.* token approach. See bitplayer_motion_design_reference.md
// (section 6) for the theory this is based on, and
// bitplayer_motion_onboarding_audit_findings.md for the exact file:line
// locations that currently hardcode the values below.
//
// Unlike AppColors (lib/src/theme/app_colors.dart), this is a plain static
// token class rather than a BuildContext extension. Durations and curves
// aren't theme-dependent, so there's no reason to thread BuildContext
// through every call site just to read a constant.
//
// Existing ad-hoc values found in onboarding_screen.dart and
// cinematic_view_screen.dart, and the token each should migrate to:
//
//   200ms (AnimatedSwitcher, Next/Done button)         -> quick
//   250ms (theme toggle AnimatedContainer)              -> quick
//   300ms (page-dot AnimatedContainer)                  -> standard
//   320ms (entrance fade/slide AnimationController)     -> standard
//   350ms (PageController.next/previousPage)            -> standard
//   400ms (progress bar TweenAnimationBuilder)           -> standard
//   450ms (cinematic view controls show/hide)           -> emphasized
//
// A handful of these shift by up to ~100ms when migrated. That's below the
// threshold most people consciously notice in an isolated transition, and a
// shared scale is worth more long-term than preserving every micro-value
// that accumulated ad hoc. If a specific migration looks wrong once it's
// running on-device, it's fine to override locally rather than force it.

import 'package:flutter/animation.dart';

/// Motion timing & easing tokens shared across the app.
///
/// Use these instead of hardcoding `Duration(milliseconds: ...)` or
/// `Curves.___` at call sites, so every animation in the app draws from one
/// deliberate scale instead of accumulating one-off values over time.
abstract final class MotionTokens {
  // --- Durations ----------------------------------------------------------
  // A four-tier scale is enough to cover everything from a small state
  // toggle to a full-screen scene transition without over-fragmenting.
  // Roughly geometric spacing (~100ms steps) keeps the tiers easy to tell
  // apart by feel, not just by number.

  /// Micro-feedback: icon toggles, tiny state changes the user shouldn't
  /// consciously register as "an animation" at all.
  static const Duration micro = Duration(milliseconds: 150);

  /// Small UI transitions: pill/chip state changes, page-indicator dots,
  /// switcher swaps (e.g. Next <-> Done button, tab content swaps).
  static const Duration quick = Duration(milliseconds: 250);

  /// Default for most transitions: page swipes, progress bars, entrance
  /// fades. If you're not sure which tier fits, use this one.
  static const Duration standard = Duration(milliseconds: 350);

  /// Deliberate, "notice this" transitions: full-screen scene changes,
  /// transport-control show/hide in the cinematic view.
  static const Duration emphasized = Duration(milliseconds: 450);

  // --- Curves ---------------------------------------------------------------

  /// Entrances: something appearing or growing into place.
  static const Curve enter = Curves.easeOut;

  /// Exits: something leaving or shrinking away.
  static const Curve exit = Curves.easeIn;

  /// Default for two-way transitions (page swipes, progress fills) where
  /// the same motion plays whether moving forward or backward.
  static const Curve standardCurve = Curves.easeInOut;

  /// Emphasized entrance -- a snappier ease-out for moments that should
  /// feel deliberate rather than ambient (e.g. transport controls appearing
  /// in the cinematic view).
  static const Curve emphasizedEnter = Curves.easeOutCubic;

  /// Emphasized exit -- pairs with [emphasizedEnter] for the reverse half
  /// of the same transition.
  static const Curve emphasizedExit = Curves.easeInCubic;
}

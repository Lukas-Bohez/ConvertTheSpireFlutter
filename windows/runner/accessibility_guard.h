#ifndef RUNNER_ACCESSIBILITY_GUARD_H_
#define RUNNER_ACCESSIBILITY_GUARD_H_

// Flutter's Windows engine crashes when a program that reads the window
// through UI Automation (a screen reader, or one of the many tools and
// Windows features that read windows) asks for a child the semantics tree no
// longer has: FlutterPlatformNodeDelegate::ChildAtIndex reads the id of a
// null child. Still open upstream in Flutter 3.41 and later:
// https://github.com/flutter/flutter/issues/195399 and
// https://github.com/flutter/flutter/issues/192220.
//
// The guard catches exactly that read and lets ChildAtIndex return nullptr
// ("no such child"), the answer the engine gives once it checks for null.
// Nothing else is touched: any other fault crashes as before.
namespace accessibility_guard {

void Install();

// Times the guard stepped in since Install().
long Recoveries();

// Calls the engine's ChildAtIndex for a child its node does not have.
// Returns 0 when the guard turned that into "no such child"; anything else
// means the guard no longer finds the engine code (after a Flutter
// upgrade): see whether the engine has the null check now.
int SelfTest();

}  // namespace accessibility_guard

#endif  // RUNNER_ACCESSIBILITY_GUARD_H_

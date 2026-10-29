import 'dart:ffi' show Abi;

/// Whether the app runs as a 64-bit ARM Linux program (an ARM PC, a
/// Raspberry Pi). The programs the app downloads come in a separate build
/// for these.
bool get isLinuxArm64 => Abi.current() == Abi.linuxArm64;

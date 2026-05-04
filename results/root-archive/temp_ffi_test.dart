import 'dart:ffi';

void main() {
  final lib = DynamicLibrary.process();
  final ptr = lib.lookup<NativeFunction<Int32 Function()>>("GetCurrentProcessId");
  final func = ptr.asFunction<int Function()>();
  print(func());
}

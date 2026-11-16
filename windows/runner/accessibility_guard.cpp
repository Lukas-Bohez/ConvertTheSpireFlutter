#include "accessibility_guard.h"

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <iterator>

namespace accessibility_guard {
namespace {

volatile LONG g_recoveries = 0;

#if defined(_M_X64)

// FlutterPlatformNodeDelegate::ChildAtIndex in the release engine:
//
//   mov    rcx, [rcx+8]       ax_node_
//   movsxd rdx, edx           index
//   call   AXNode::GetUnignoredChildAtIndex
//   mov    edx, [rax+50h]     child->id(): rax is null, the crash
//   mov    rax, [rdi]         the bridge (rdi) ...
//   mov    rax, [rax+18h]
//   mov    rcx, rdi
//   call   [rip+...]          ... GetNativeAccessibleFromId(id)
//   mov    rdi, rax           rdi is returned
//   test   rsi, rsi           resume here with rdi = nullptr
//
// -1 is a byte that changes from build to build (call targets).
constexpr std::ptrdiff_t kFaultOffset = 12;
constexpr std::ptrdiff_t kResumeOffset = 34;
constexpr int16_t kPattern[] = {
    0x48, 0x8b, 0x49, 0x08,              // mov rcx, [rcx+8]
    0x48, 0x63, 0xd2,                    // movsxd rdx, edx
    0xe8, -1,   -1,   -1,   -1,          // call ...
    0x8b, 0x50, 0x50,                    // mov edx, [rax+50h]
    0x48, 0x8b, 0x07,                    // mov rax, [rdi]
    0x48, 0x8b, 0x40, 0x18,              // mov rax, [rax+18h]
    0x48, 0x89, 0xf9,                    // mov rcx, rdi
    0xff, 0x15, -1,   -1,   -1,   -1,    // call [rip+...]
    0x48, 0x89, 0xc7,                    // mov rdi, rax
    0x48, 0x85, 0xf6,                    // test rsi, rsi
};
constexpr std::size_t kPatternLength = std::size(kPattern);
// The field read through the null child: child->id().
constexpr ULONG_PTR kIdOffset = 0x50;

const IMAGE_NT_HEADERS* Headers(HMODULE module) {
  const auto* base = reinterpret_cast<const uint8_t*>(module);
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  return reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
}

// Whether [start, start + length) lies inside flutter_windows.dll.
bool InEngine(const uint8_t* start, std::size_t length) {
  const HMODULE engine = ::GetModuleHandleW(L"flutter_windows.dll");
  if (engine == nullptr) {
    return false;
  }
  const auto* base = reinterpret_cast<const uint8_t*>(engine);
  const uint8_t* end = base + Headers(engine)->OptionalHeader.SizeOfImage;
  return start >= base && start + length <= end;
}

bool MatchesAt(const uint8_t* code) {
  for (std::size_t i = 0; i < kPatternLength; ++i) {
    if (kPattern[i] >= 0 && code[i] != kPattern[i]) {
      return false;
    }
  }
  return true;
}

LONG CALLBACK Handler(EXCEPTION_POINTERS* info) {
  const EXCEPTION_RECORD* record = info->ExceptionRecord;
  CONTEXT* context = info->ContextRecord;
  // Cheap checks first: a read of address 0x50 through a null rax.
  if (record->ExceptionCode != EXCEPTION_ACCESS_VIOLATION ||
      record->NumberParameters < 2 || record->ExceptionInformation[0] != 0 ||
      record->ExceptionInformation[1] != kIdOffset || context->Rax != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  const auto* start =
      static_cast<const uint8_t*>(record->ExceptionAddress) - kFaultOffset;
  if (!InEngine(start, kPatternLength) || !MatchesAt(start)) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  context->Rdi = 0;
  context->Rip = reinterpret_cast<DWORD64>(start + kResumeOffset);
  ::InterlockedIncrement(&g_recoveries);
  return EXCEPTION_CONTINUE_EXECUTION;
}

// The one place in the engine's code that matches kPattern, or nullptr.
const uint8_t* FindChildAtIndexCode(HMODULE engine) {
  const auto* base = reinterpret_cast<const uint8_t*>(engine);
  const IMAGE_NT_HEADERS* nt = Headers(engine);
  const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
  const uint8_t* found = nullptr;
  int matches = 0;
  for (WORD s = 0; s < nt->FileHeader.NumberOfSections; ++s, ++section) {
    if ((section->Characteristics & IMAGE_SCN_MEM_EXECUTE) == 0 ||
        section->Misc.VirtualSize < kPatternLength) {
      continue;
    }
    const uint8_t* code = base + section->VirtualAddress;
    const std::size_t last = section->Misc.VirtualSize - kPatternLength;
    for (std::size_t i = 0; i <= last; ++i) {
      if (code[i] == kPattern[0] && MatchesAt(code + i)) {
        found = code + i;
        ++matches;
      }
    }
  }
  return matches == 1 ? found : nullptr;
}

#endif  // defined(_M_X64)

}  // namespace

void Install() {
#if defined(_M_X64)
  // First in line, so it runs before any handler that would end the app.
  ::AddVectoredExceptionHandler(1, Handler);
#endif
}

long Recoveries() {
  return g_recoveries;
}

int SelfTest() {
#if defined(_M_X64)
  const HMODULE engine = ::LoadLibraryW(L"flutter_windows.dll");
  if (engine == nullptr) {
    return 2;
  }
  const uint8_t* code = FindChildAtIndexCode(engine);
  if (code == nullptr) {
    return 3;
  }
  DWORD64 image_base = 0;
  const PRUNTIME_FUNCTION function = ::RtlLookupFunctionEntry(
      reinterpret_cast<DWORD64>(code), &image_base, nullptr);
  if (function == nullptr) {
    return 4;
  }
  using ChildAtIndex = void* (*)(void* self, int index);
  const auto child_at_index = reinterpret_cast<ChildAtIndex>(
      image_base + function->BeginAddress);

  // A delegate whose node has no children and whose bridge is gone (the
  // fields ChildAtIndex reads: ax_node_ at +8, bridge_ at +10h and +18h).
  alignas(16) static uint8_t node[256] = {};
  void* delegate[4] = {nullptr, node, nullptr, nullptr};

  Install();
  const long before = Recoveries();
  void* child = child_at_index(delegate, 0);
  if (child != nullptr || Recoveries() != before + 1) {
    return 5;
  }
#endif
  return 0;
}

}  // namespace accessibility_guard

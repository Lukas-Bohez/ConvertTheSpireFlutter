#pragma once

#include <fstream>
#include <iostream>
#include <string>
#include <windows.h>

// Temporary diagnostics for the "unsupported_platform" init failure:
// appends each step of WebviewPlatform/GraphicsContext construction to
// %TEMP%\cts_webview_platform.log (and stderr) so the failing sub-check
// can be identified from a flutter test run.
inline void CtsProbeLog(const std::string& message) {
  std::cerr << "[cts-webview] " << message << std::endl;
  char temp_path[MAX_PATH];
  if (GetTempPathA(MAX_PATH, temp_path)) {
    std::ofstream file(std::string(temp_path) + "cts_webview_platform.log",
                       std::ios_base::app);
    if (file.is_open()) {
      file << "[cts-webview] " << message << std::endl;
    }
  }
}

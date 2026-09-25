#include "open_requests.h"

#include <shlobj.h>

#include <cwctype>
#include <string>
#include <vector>

namespace open_requests {

namespace {

// These names identify the app to Windows. Keep them stable: renaming one
// leaves the old entries behind on every PC.
constexpr wchar_t kInstanceMutexName[] =
    L"Local\\ConvertTheSpireReborn.Instance";
constexpr wchar_t kMainWindowProperty[] = L"ConvertTheSpireReborn.MainWindow";
// Tags our WM_COPYDATA ("CTSR"), so other senders are ignored.
constexpr ULONG_PTR kForwardedArgumentsId = 0x43545352;

constexpr wchar_t kAppName[] = L"Convert the Spire Reborn";
constexpr wchar_t kAppDescription[] =
    L"Plays music and video, and downloads torrents and magnet links.";
constexpr wchar_t kMediaProgId[] = L"ConvertTheSpireReborn.Media";
constexpr wchar_t kTorrentProgId[] = L"ConvertTheSpireReborn.Torrent";
constexpr wchar_t kMagnetProgId[] = L"ConvertTheSpireReborn.Magnet";
constexpr wchar_t kCapabilitiesKey[] =
    L"Software\\ConvertTheSpireReborn\\Capabilities";

// What the player's library shows: _mediaExtensions in
// lib/src/screens/player.dart. Keep the two lists the same.
constexpr const wchar_t* kMediaExtensions[] = {
    L".mp3", L".m4a", L".flac", L".wav", L".ogg", L".opus",
    L".aac", L".wma", L".mp4", L".mkv", L".avi", L".webm",
    L".mov", L".wmv", L".flv", L".m4v",
};

BOOL CALLBACK FindMarkedWindow(HWND window, LPARAM result) {
  if (::GetPropW(window, kMainWindowProperty) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(result) = window;
  return FALSE;
}

HWND FindMainWindow() {
  HWND found = nullptr;
  ::EnumWindows(FindMarkedWindow, reinterpret_cast<LPARAM>(&found));
  return found;
}

std::wstring Lowercase(std::wstring text) {
  for (auto& c : text) {
    c = static_cast<wchar_t>(std::towlower(c));
  }
  return text;
}

// Writes registry values under HKEY_CURRENT_USER, skipping values that
// already hold the same data, and remembers whether anything changed.
class RegistryWriter {
 public:
  void String(const std::wstring& key,
              const wchar_t* name,
              const std::wstring& data) {
    wchar_t current[1024] = {};
    DWORD size = sizeof(current) - sizeof(wchar_t);
    if (::RegGetValueW(HKEY_CURRENT_USER, key.c_str(), name, RRF_RT_REG_SZ,
                       nullptr, current, &size) == ERROR_SUCCESS &&
        data == current) {
      return;
    }
    const DWORD bytes = static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t));
    if (::RegSetKeyValueW(HKEY_CURRENT_USER, key.c_str(), name, REG_SZ,
                          data.c_str(), bytes) == ERROR_SUCCESS) {
      changed_ = true;
    }
  }

  // An empty value, as OpenWithProgids and SupportedTypes list them.
  void Empty(const std::wstring& key, const wchar_t* name) {
    if (::RegGetValueW(HKEY_CURRENT_USER, key.c_str(), name, RRF_RT_ANY,
                       nullptr, nullptr, nullptr) == ERROR_SUCCESS) {
      return;
    }
    if (::RegSetKeyValueW(HKEY_CURRENT_USER, key.c_str(), name, REG_NONE,
                          nullptr, 0) == ERROR_SUCCESS) {
      changed_ = true;
    }
  }

  bool changed() const { return changed_; }

 private:
  bool changed_ = false;
};

// Reads the command that opens magnet links now: the current user's own
// choice first, then the machine-wide one, the order Windows applies.
LSTATUS ReadMagnetCommand(wchar_t* command, DWORD bytes, DWORD* type) {
  constexpr wchar_t kKey[] = L"Software\\Classes\\magnet\\shell\\open\\command";
  DWORD size = bytes;
  LSTATUS status = ::RegGetValueW(HKEY_CURRENT_USER, kKey, nullptr,
                                  RRF_RT_ANY | RRF_NOEXPAND, type, command,
                                  &size);
  if (status != ERROR_FILE_NOT_FOUND) {
    return status;
  }
  size = bytes;
  return ::RegGetValueW(HKEY_LOCAL_MACHINE, kKey, nullptr,
                        RRF_RT_ANY | RRF_NOEXPAND, type, command, &size);
}

// True when |command| (a shell\open\command value) starts this exe, whichever
// folder it was in then.
bool IsOurCommand(const wchar_t* command, const std::wstring& exe_name) {
  return Lowercase(command).find(Lowercase(exe_name)) != std::wstring::npos;
}

}  // namespace

bool ForwardToRunningInstance(const std::vector<std::string>& arguments) {
  // Held until this process exits; the handle is never closed on purpose.
  const HANDLE mutex = ::CreateMutexW(nullptr, FALSE, kInstanceMutexName);
  if (mutex == nullptr || ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return false;
  }

  // The other copy may still be starting: give it a few seconds to create
  // its window.
  HWND target = FindMainWindow();
  for (int attempt = 0; target == nullptr && attempt < 50; ++attempt) {
    ::Sleep(100);
    target = FindMainWindow();
  }
  if (target == nullptr) {
    return false;
  }

  // Arguments separated by NUL characters.
  std::string payload;
  for (const auto& argument : arguments) {
    payload += argument;
    payload.push_back('\0');
  }
  COPYDATASTRUCT data = {};
  data.dwData = kForwardedArgumentsId;
  data.cbData = static_cast<DWORD>(payload.size());
  data.lpData = payload.empty() ? nullptr : &payload[0];

  // This copy was just started by the user, so it may pass the right to take
  // the foreground on to the copy that will show the file.
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(target, &process_id);
  ::AllowSetForegroundWindow(process_id);

  DWORD_PTR reply = 0;
  const LRESULT sent = ::SendMessageTimeoutW(
      target, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data),
      SMTO_ABORTIFHUNG, 5000, &reply);
  return sent != 0 && reply == TRUE;
}

void MarkMainWindow(HWND window) {
  // Any non-null value marks it; the window's own handle is one.
  ::SetPropW(window, kMainWindowProperty, window);
}

bool DecodeForwarded(const COPYDATASTRUCT* data,
                     std::vector<std::string>* arguments) {
  if (data == nullptr || data->dwData != kForwardedArgumentsId) {
    return false;
  }
  arguments->clear();
  if (data->lpData == nullptr || data->cbData == 0) {
    return true;
  }
  const char* bytes = static_cast<const char*>(data->lpData);
  std::string current;
  for (DWORD i = 0; i < data->cbData; ++i) {
    if (bytes[i] == '\0') {
      if (!current.empty()) {
        arguments->push_back(current);
      }
      current.clear();
    } else {
      current.push_back(bytes[i]);
    }
  }
  if (!current.empty()) {
    arguments->push_back(current);
  }
  return true;
}

void RegisterAssociations() {
  wchar_t exe_buffer[MAX_PATH] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, exe_buffer, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }
  const std::wstring exe(exe_buffer, length);
  const size_t separator = exe.find_last_of(L"\\/");
  const std::wstring exe_name =
      separator == std::wstring::npos ? exe : exe.substr(separator + 1);
  const std::wstring command = L"\"" + exe + L"\" \"%1\"";
  const std::wstring icon = L"\"" + exe + L"\",0";
  const std::wstring classes = L"Software\\Classes\\";
  const std::wstring application = classes + L"Applications\\" + exe_name;
  const std::wstring capabilities = kCapabilitiesKey;

  RegistryWriter writer;

  // One program identifier per kind of thing this app opens.
  const struct {
    const wchar_t* prog_id;
    const wchar_t* description;
    bool is_link;
  } prog_ids[] = {
      {kMediaProgId, L"Media file", false},
      {kTorrentProgId, L"Torrent file", false},
      {kMagnetProgId, L"URL:Magnet link", true},
  };
  for (const auto& entry : prog_ids) {
    const std::wstring key = classes + entry.prog_id;
    writer.String(key, nullptr, entry.description);
    if (entry.is_link) {
      writer.String(key, L"URL Protocol", L"");
    }
    writer.String(key + L"\\DefaultIcon", nullptr, icon);
    writer.String(key + L"\\shell\\open\\command", nullptr, command);
  }

  // "Open with" lists and the app's own entry.
  writer.String(application, L"FriendlyAppName", kAppName);
  writer.String(application + L"\\shell\\open\\command", nullptr, command);
  for (const wchar_t* extension : kMediaExtensions) {
    writer.Empty(classes + extension + L"\\OpenWithProgids", kMediaProgId);
    writer.Empty(application + L"\\SupportedTypes", extension);
    writer.String(capabilities + L"\\FileAssociations", extension,
                  kMediaProgId);
  }
  writer.Empty(classes + L".torrent\\OpenWithProgids", kTorrentProgId);
  writer.Empty(application + L"\\SupportedTypes", L".torrent");
  writer.String(capabilities + L"\\FileAssociations", L".torrent",
                kTorrentProgId);

  // Settings > Default apps.
  writer.String(capabilities, L"ApplicationName", kAppName);
  writer.String(capabilities, L"ApplicationDescription", kAppDescription);
  writer.String(capabilities, L"ApplicationIcon", icon);
  writer.String(capabilities + L"\\URLAssociations", L"magnet", kMagnetProgId);
  writer.String(L"Software\\RegisteredApplications", kAppName, capabilities);

  // magnet: itself, which browsers hand to Windows. Taken only when no app
  // opens magnet links yet, or when this one already does (so the command
  // follows a moved folder). An installed torrent client keeps them; the
  // user can still pick this app in Default apps.
  wchar_t current[1024] = {};
  DWORD type = 0;
  const LSTATUS status =
      ReadMagnetCommand(current, sizeof(current) - sizeof(wchar_t), &type);
  const bool unclaimed = status == ERROR_FILE_NOT_FOUND ||
                         (status == ERROR_SUCCESS && current[0] == L'\0');
  const bool ours = status == ERROR_SUCCESS &&
                    (type == REG_SZ || type == REG_EXPAND_SZ) &&
                    IsOurCommand(current, exe_name);
  if (unclaimed || ours) {
    const std::wstring magnet = classes + L"magnet";
    writer.String(magnet, nullptr, L"URL:Magnet link");
    writer.String(magnet, L"URL Protocol", L"");
    writer.String(magnet + L"\\DefaultIcon", nullptr, icon);
    writer.String(magnet + L"\\shell\\open\\command", nullptr, command);
  }

  if (writer.changed()) {
    ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  }
}

}  // namespace open_requests

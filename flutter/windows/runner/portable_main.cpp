#include <windows.h>
#include <cstdlib>

#include <string>
#include <vector>

// The directory package has one small entry point beside app/ and userdata/.
// Its manifest requests elevation before the host or any remote input starts.
int APIENTRY wWinMain(HINSTANCE, HINSTANCE, wchar_t* arguments, int) {
  std::vector<wchar_t> buffer(32768);
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= buffer.size()) return EXIT_FAILURE;
  const std::wstring own_path(buffer.data(), length);
  const auto separator = own_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return EXIT_FAILURE;
  const std::wstring directory = own_path.substr(0, separator) + L"\\app";
  std::wstring executable = directory + L"\\SubnetDesk.exe";
  if (GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES) {
    executable = directory + L"\\rustdesk.exe";
  }
  std::wstring command = L"\"" + executable + L"\" ";
  if (arguments) command += arguments;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(executable.c_str(), &command[0], nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, directory.c_str(), &startup, &child)) {
    MessageBoxW(nullptr, L"Cannot start SubnetDesk. Extract the entire portable ZIP to a writable folder.",
                L"SubnetDesk", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  return EXIT_SUCCESS;
}

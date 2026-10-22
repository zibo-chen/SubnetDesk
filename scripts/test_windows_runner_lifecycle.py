"""Exercise the runner's actual teardown method with OS/Flutter test doubles.

This runs without a Windows desktop. It covers the pre-create cleanup that
Win32Window::CreateAndShow performs and the later teardown of a live controller.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WindowsRunnerLifecycleTests(unittest.TestCase):
    def test_startup_cleanup_preserves_host_and_live_teardown_stops_it_once(self):
        compiler = shutil.which("clang++") or shutil.which("g++") or shutil.which("cl")
        if compiler is None:
            self.skipTest("A C++ compiler is required for the native lifecycle regression")

        source = (ROOT / "flutter/windows/runner/flutter_window.cpp").read_text()
        start = source.index("void FlutterWindow::OnDestroy() {")
        end = source.index("\nLRESULT", start)
        teardown = source[start:end]
        harness = r'''
#include <cassert>
#include <memory>

int shutdown_calls = 0;
int icon_deletions = 0;
constexpr int NIM_DELETE = 2;
void StopHost() { ++shutdown_calls; }
void* GetModuleHandleW(const wchar_t*) { return reinterpret_cast<void*>(1); }
auto GetProcAddress(void*, const char*) { return &StopHost; }
void Shell_NotifyIconW(int, int*) { ++icon_deletions; }

struct Win32Window { void OnDestroy() {} };
struct FlutterWindow : Win32Window {
  bool tray_visible_ = false;
  int tray_ = 0;
  std::unique_ptr<int> host_channel_;
  std::unique_ptr<int> flutter_controller_;
  void OnDestroy();
};
'''
        harness += teardown
        harness += r'''
int main() {
  FlutterWindow window;
  // CreateAndShow first calls Destroy, before it has a controller.
  window.OnDestroy();
  assert(shutdown_calls == 0);

  window.flutter_controller_ = std::make_unique<int>(1);
  window.host_channel_ = std::make_unique<int>(1);
  window.tray_visible_ = true;
  window.OnDestroy();
  assert(shutdown_calls == 1);
  assert(icon_deletions == 1);
  assert(!window.flutter_controller_);
  assert(!window.host_channel_);
  assert(!window.tray_visible_);

  // Repeated native cleanup must not stop the host a second time.
  window.OnDestroy();
  assert(shutdown_calls == 1);
  assert(icon_deletions == 1);
}
'''
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            cpp = directory / "lifecycle.cpp"
            executable = directory / ("lifecycle.exe" if os.name == "nt" else "lifecycle")
            cpp.write_text(harness)
            if Path(compiler).stem.lower() == "cl":
                command = [compiler, "/nologo", "/EHsc", "/std:c++17", str(cpp),
                           f"/Fe:{executable}"]
            else:
                command = [compiler, "-std=c++17", str(cpp), "-o", str(executable)]
            subprocess.run(command, cwd=directory, check=True, capture_output=True, text=True)
            subprocess.run([str(executable)], cwd=directory, check=True)


if __name__ == "__main__":
    unittest.main()

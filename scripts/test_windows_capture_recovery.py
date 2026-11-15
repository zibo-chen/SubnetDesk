"""Run the actual Windows capture loop against transient display/capture failures.

Only the OS/capture dependencies and sleeps are replaced. This can run on macOS
or Linux; it does not prove that a disconnected Windows RDP desktop is capturable.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CaptureRecoveryTests(unittest.TestCase):
    def test_capture_loop_survives_display_and_gdi_transitions(self):
        rustc = shutil.which("rustc")
        if rustc is None:
            self.skipTest("rustc is required")
        source = (ROOT / "src/server/portable_service.rs").read_text()
        start = source.index("    fn run_capture(shmem: Arc<SharedMemory>) {")
        end = source.index('\n    #[tokio::main', start)
        capture_loop = source[start:end].replace("std::thread::sleep", "test_sleep")
        policy = ROOT / "src/server/display_service/headless_recovery.rs"
        harness = f'#[path = "{policy.as_posix()}"] mod headless_recovery;\n'
        harness += r'''
extern crate self as log;
#[macro_export] macro_rules! error { ($($arg:tt)*) => { () }; }
#[macro_export] macro_rules! warn { ($($arg:tt)*) => { () }; }
#[macro_export] macro_rules! info { ($($arg:tt)*) => { () }; }
use std::{sync::{Arc, Mutex}, time::{Duration, Instant}};
static EXIT: Mutex<bool> = Mutex::new(false);
static TEST_LOCK: Mutex<()> = Mutex::new(());
#[derive(Default)]
struct State {
    missing: usize, enumeration_errors: usize, capture_errors: usize,
    gdi: bool, creations: usize, frames: usize, sleeps: usize,
    fail_gdi_once: bool, interrupt_after_first: bool, stop_after: usize,
}
static STATE: Mutex<State> = Mutex::new(State {
    missing: 0, enumeration_errors: 0, capture_errors: 0, gdi: false,
    creations: 0, frames: 0, sleeps: 0, fail_gdi_once: false,
    interrupt_after_first: false, stop_after: 0,
});
const ADDR_CAPTURER_PARA: usize = 0;
const ADDR_CAPTURE_WOULDBLOCK: usize = 64;
const ADDR_CAPTURE_FRAME_COUNTER: usize = 80;
const ADDR_CAPTURE_FRAME: usize = 128;
const MAX_DXGI_FAIL_TIME: usize = 5;
const CAPTURE_FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(3);
mod video_qos { pub const MAX_FPS: u32 = 60; pub const MIN_FPS: u32 = 1; }
const TRUE: i32 = 1;
const FALSE: i32 = 0;
#[repr(C)]
struct CapturerPara { recreate: bool, current_display: usize, timeout_ms: i32 }
struct FrameInfo { length: usize, width: usize, height: usize }
struct SharedMemory { words: Vec<usize> }
impl SharedMemory {
    fn as_ptr(&self) -> *mut u8 { self.words.as_ptr() as *mut u8 }
    fn len(&self) -> usize { self.words.len() * std::mem::size_of::<usize>() }
    fn write(&self, addr: usize, _: &[u8]) {
        if addr == ADDR_CAPTURE_FRAME {
            let mut state = STATE.lock().unwrap();
            state.frames += 1;
            if state.interrupt_after_first && state.frames == 1 {
                state.missing = 2;
                state.capture_errors = 1;
            }
            if state.frames >= state.stop_after.max(1) { *EXIT.lock().unwrap() = true; }
        }
    }
}
fn test_sleep(_: Duration) {
    let mut state = STATE.lock().unwrap();
    state.sleeps += 1;
    // Bound an accidentally busy retry and simulate application shutdown.
    if state.sleeps >= 32 { *EXIT.lock().unwrap() = true; }
}
mod utils {
    use super::*;
    pub fn set_para(memory: &SharedMemory, para: CapturerPara) {
        unsafe { (memory.as_ptr() as *mut CapturerPara).write(para); }
    }
    pub fn i32_to_vec(value: i32) -> Vec<u8> { value.to_ne_bytes().to_vec() }
    pub fn counter_equal(_: *const u8) -> bool { true }
    pub fn increase_counter(_: *mut u8) {}
    pub fn set_frame_info(_: &SharedMemory, _: FrameInfo) {}
}
mod crate_platform {
    pub fn try_change_desktop() -> bool { true }
    pub mod windows { pub fn desktop_changed() -> bool { false } }
}
use crate_platform as platform;
struct Display;
impl Display { fn width(&self) -> usize { 1 } fn height(&self) -> usize { 1 } }
mod display_service {
    use super::*;
    pub fn try_get_displays() -> std::io::Result<Vec<Display>> {
        let mut state = STATE.lock().unwrap();
        if state.enumeration_errors > 0 {
            state.enumeration_errors -= 1;
            return Err(std::io::ErrorKind::Other.into());
        }
        if state.missing > 0 { state.missing -= 1; return Ok(vec![]); }
        Ok(vec![Display])
    }
}
struct Capturer { gdi: bool }
impl Capturer {
    fn new(_: Display) -> std::io::Result<Self> {
        let mut state = STATE.lock().unwrap();
        state.creations += 1;
        Ok(Self { gdi: state.gdi })
    }
    fn is_gdi(&self) -> bool { self.gdi }
    fn set_gdi(&mut self) -> bool {
        let mut state = STATE.lock().unwrap();
        if state.fail_gdi_once { state.fail_gdi_once = false; return false; }
        self.gdi = true; true
    }
    fn frame(&mut self, _: Duration) -> std::io::Result<Frame> {
        let mut state = STATE.lock().unwrap();
        if state.capture_errors > 0 {
            state.capture_errors -= 1;
            return Err(std::io::ErrorKind::Other.into());
        }
        Ok(Frame::PixelBuffer(Buffer))
    }
}
struct Buffer;
impl Buffer { fn data(&self) -> &[u8] { &[0, 0, 0, 255] } }
enum Frame { PixelBuffer(Buffer), Texture(()) }
'''
        harness += capture_loop
        harness += r'''
fn exercise(state: State) {
    *STATE.lock().unwrap() = state;
    *EXIT.lock().unwrap() = false;
    run_capture(Arc::new(SharedMemory { words: vec![0; 128] }));
}
#[test] fn empty_and_failed_enumeration_then_display_returns() {
    let _guard = TEST_LOCK.lock().unwrap();
    exercise(State { missing: 2, enumeration_errors: 1, ..State::default() });
    let state = STATE.lock().unwrap();
    assert_eq!(state.frames, 1);
    assert_eq!(state.sleeps, 3);
}
#[test] fn invalid_gdi_dc_is_recreated() {
    let _guard = TEST_LOCK.lock().unwrap();
    exercise(State { gdi: true, capture_errors: 1, ..State::default() });
    let state = STATE.lock().unwrap();
    assert_eq!(state.frames, 1);
    assert_eq!(state.creations, 2);
}
#[test] fn live_capture_survives_display_loss_and_return() {
    let _guard = TEST_LOCK.lock().unwrap();
    exercise(State { gdi: true, interrupt_after_first: true, stop_after: 2,
        ..State::default() });
    let state = STATE.lock().unwrap();
    assert_eq!(state.frames, 2);
    assert_eq!(state.creations, 2);
    assert_eq!(state.missing, 0);
}
#[test] fn failed_gdi_fallback_does_not_kill_agent() {
    let _guard = TEST_LOCK.lock().unwrap();
    exercise(State { capture_errors: 6, fail_gdi_once: true, ..State::default() });
    let state = STATE.lock().unwrap();
    assert_eq!(state.frames, 1);
    assert!(state.creations >= 3);
}
#[test] fn disconnected_session_keeps_retrying_until_shutdown() {
    let _guard = TEST_LOCK.lock().unwrap();
    exercise(State { missing: 100, ..State::default() });
    let state = STATE.lock().unwrap();
    assert_eq!(state.frames, 0);
    assert_eq!(state.sleeps, 32);
}
'''
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            test_file = directory / "capture_recovery.rs"
            executable = directory / ("capture_recovery.exe" if os.name == "nt" else "capture_recovery")
            test_file.write_text(harness)
            result = subprocess.run(
                [rustc, "--edition=2021", "--test", str(test_file), "-o", str(executable)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()

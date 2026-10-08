//! Run against the exact shipping DLL to check native value ABI and host dispatch.
extern crate sciter;

use sciter::{Element, Value};
use sciter::HELEMENT;
use sciter::dom::event::{BEHAVIOR_EVENTS, PHASE_MASK, EventReason};

struct Handler;
impl Handler {
    fn echo(&self, text: String, number: i32, flag: bool) -> String {
        format!("{}:{}:{}", text, number, flag)
    }
}
impl sciter::EventHandler for Handler {
    fn on_event(&mut self, _: HELEMENT, _: HELEMENT, _: HELEMENT, code: BEHAVIOR_EVENTS, _: PHASE_MASK, _: EventReason) -> bool {
        code == BEHAVIOR_EVENTS(0xB8)
    }
    sciter::dispatch_script_call! { fn echo(String, i32, bool); }
}

fn main() -> Result<(), String> {
    let library = std::env::args().nth(1).ok_or("pass the shipping Sciter library path")?;
    sciter::set_library(&library)?;
    let mut array = Value::array(0);
    array.set(0, 11);
    array.set(1, 22);
    let first = &array[0];
    let second = &array[1];
    if first.to_int() != Some(11) || second.to_int() != Some(22) {
        return Err("array indexing overwrote a live reference".into());
    }
    let mut map = Value::map();
    map.set_item("name", "Win7 ABI");
    map.set_item("ready", true);
    if map["name"].as_string().as_deref() != Some("Win7 ABI") || map["ready"].to_bool() != Some(true) {
        return Err("map ABI roundtrip failed".into());
    }
    let mut window = sciter::Window::new();
    window.event_handler(Handler);
    if !window.load_html(br#"<html><body><button>Smoke</button></body></html>"#, None) {
        return Err("native window load failed".into());
    }
    let root = Element::from_window(window.get_hwnd()).map_err(|error| format!("root: {:?}", error))?;
    let result = root.eval_script("view.echo(\"Win7 ABI\", 42, true)").map_err(|error| format!("host dispatch: {:?}", error))?;
    if result.as_string().as_deref() != Some("Win7 ABI:42:true") {
        return Err("host dispatch ABI roundtrip failed".into());
    }
    if !root.fire_event(BEHAVIOR_EVENTS(0xB8), None, None, false, None)
        .map_err(|error| format!("extended behavior event: {:?}", error))? {
        return Err("extended behavior event did not reach the host".into());
    }
    window.dismiss();
    println!("Sciter value, window and script dispatch ABI checks passed");
    Ok(())
}

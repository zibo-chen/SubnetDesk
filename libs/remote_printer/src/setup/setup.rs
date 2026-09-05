use super::{driver::uninstall_driver, port::check_delete_local_port, printer::delete_printer};
use hbb_common::{allow_err, lazy_static, log};
use std::sync::Mutex;
use windows_strings::PCWSTR;

lazy_static::lazy_static!(
    static ref SETUP_MTX: Mutex<()> = Mutex::new(());
);

pub fn uninstall_printer(app_name: &str) {
    let printer_name = crate::get_printer_name(app_name);
    let driver_name = crate::get_driver_name();
    let port = crate::get_port_name(app_name);
    let rd_printer_name = PCWSTR::from_raw(printer_name.as_ptr());
    let rd_printer_driver_name = PCWSTR::from_raw(driver_name.as_ptr());
    let rd_printer_port = PCWSTR::from_raw(port.as_ptr());

    let _lock = SETUP_MTX.lock().unwrap();

    allow_err!(delete_printer(&rd_printer_name));
    allow_err!(uninstall_driver(&rd_printer_driver_name));
    allow_err!(check_delete_local_port(&rd_printer_port));
}

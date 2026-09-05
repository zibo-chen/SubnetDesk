use super::{common_enum, get_wstr_bytes, is_name_equal};
use hbb_common::{bail, ResultType};
use std::{io, ptr::null_mut};
use winapi::{
    shared::{
        minwindef::{BOOL, DWORD, FALSE, LPBYTE, LPDWORD},
        ntdef::HANDLE,
        winerror::ERROR_INVALID_PRINTER_NAME,
    },
    um::winspool::{
        ClosePrinter, DeletePrinter, EnumPrintersW, OpenPrinterW, SetPrinterW, PRINTER_ALL_ACCESS,
        PRINTER_CONTROL_PURGE, PRINTER_DEFAULTSW, PRINTER_ENUM_LOCAL, PRINTER_INFO_2W,
    },
};
use windows_strings::PCWSTR;

fn enum_local_printer(
    level: DWORD,
    p_printer_info: LPBYTE,
    cb_buf: DWORD,
    pcb_needed: LPDWORD,
    pc_returned: LPDWORD,
) -> BOOL {
    unsafe {
        EnumPrintersW(
            PRINTER_ENUM_LOCAL,
            null_mut(),
            level,
            p_printer_info,
            cb_buf,
            pcb_needed,
            pc_returned,
        )
    }
}

pub fn get_printer_installed_on_port(port: &PCWSTR) -> ResultType<Option<Vec<u16>>> {
    common_enum(
        "EnumPrintersW",
        enum_local_printer,
        2,
        |info: &PRINTER_INFO_2W| {
            if is_name_equal(port, info.pPortName) {
                Some(get_wstr_bytes(info.pPrinterName))
            } else {
                None
            }
        },
        || None,
    )
}

pub fn delete_printer(name: &PCWSTR) -> ResultType<()> {
    let mut defaults = PRINTER_DEFAULTSW {
        pDataType: null_mut(),
        pDevMode: null_mut(),
        DesiredAccess: PRINTER_ALL_ACCESS,
    };
    let mut printer: HANDLE = null_mut();
    unsafe {
        if FALSE
            == OpenPrinterW(
                name.as_ptr() as _,
                &mut printer,
                &mut defaults as *mut PRINTER_DEFAULTSW,
            )
        {
            let err = io::Error::last_os_error();
            if err.raw_os_error() == Some(ERROR_INVALID_PRINTER_NAME as _) {
                return Ok(());
            }
            bail!("Failed to open the legacy printer, {}", err)
        }

        if FALSE == SetPrinterW(printer, 0, null_mut(), PRINTER_CONTROL_PURGE) {
            ClosePrinter(printer);
            bail!(
                "Failed to purge the legacy printer queue, {}",
                io::Error::last_os_error()
            )
        }
        if FALSE == DeletePrinter(printer) {
            ClosePrinter(printer);
            bail!(
                "Failed to delete the legacy printer, {}",
                io::Error::last_os_error()
            )
        }
        ClosePrinter(printer);
    }
    Ok(())
}

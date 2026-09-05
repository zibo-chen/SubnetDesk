use super::{common_enum, get_wstr_bytes, is_name_equal};
use hbb_common::{bail, log, ResultType};
use std::{io, ptr::null_mut, time::Duration};
use winapi::{
    shared::{
        minwindef::{BOOL, DWORD, FALSE, LPBYTE, LPDWORD},
        winerror::{ERROR_UNKNOWN_PRINTER_DRIVER, S_OK},
    },
    um::winspool::{
        DeletePrinterDriverExW, DeletePrinterDriverPackageW, EnumPrinterDriversW,
        DPD_DELETE_ALL_FILES, DRIVER_INFO_8W,
    },
};
use windows_strings::PCWSTR;

const HRESULT_ERR_ELEMENT_NOT_FOUND: u32 = 0x80070490;

fn enum_printer_driver(
    level: DWORD,
    p_driver_info: LPBYTE,
    cb_buf: DWORD,
    pcb_needed: LPDWORD,
    pc_returned: LPDWORD,
) -> BOOL {
    unsafe {
        EnumPrinterDriversW(
            null_mut(),
            null_mut(),
            level,
            p_driver_info,
            cb_buf,
            pcb_needed,
            pc_returned,
        )
    }
}

fn find_inf(name: &PCWSTR) -> ResultType<Vec<u16>> {
    let result = common_enum(
        "EnumPrinterDriversW",
        enum_printer_driver,
        8,
        |info: &DRIVER_INFO_8W| {
            if is_name_equal(name, info.pName) {
                Some(get_wstr_bytes(info.pszInfPath))
            } else {
                None
            }
        },
        || None,
    )?;
    Ok(result.unwrap_or_default())
}

fn delete_printer_driver(name: &PCWSTR) -> ResultType<()> {
    unsafe {
        if FALSE
            == DeletePrinterDriverExW(
                null_mut(),
                null_mut(),
                name.as_ptr() as _,
                DPD_DELETE_ALL_FILES,
                0,
            )
        {
            let err = io::Error::last_os_error();
            if err.raw_os_error() != Some(ERROR_UNKNOWN_PRINTER_DRIVER as _) {
                bail!("Failed to delete the legacy printer driver, {}", err)
            }
        }
    }
    Ok(())
}

fn delete_printer_driver_package(inf: Vec<u16>) -> ResultType<()> {
    if inf.is_empty() {
        return Ok(());
    }
    let path_len = if inf.last() == Some(&0) {
        inf.len() - 1
    } else {
        inf.len()
    };
    if !std::path::Path::new(&String::from_utf16_lossy(&inf[..path_len])).exists() {
        return Ok(());
    }

    let mut retries = 3;
    loop {
        unsafe {
            let result = DeletePrinterDriverPackageW(null_mut(), inf.as_ptr(), null_mut());
            if result == S_OK || result == HRESULT_ERR_ELEMENT_NOT_FOUND as i32 {
                return Ok(());
            }
            log::error!(
                "Failed to delete the legacy printer driver package, result: {}",
                result
            );
        }
        retries -= 1;
        if retries == 0 {
            bail!("Failed to delete the legacy printer driver package");
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

pub fn uninstall_driver(name: &PCWSTR) -> ResultType<()> {
    let inf = find_inf(name)?;
    delete_printer_driver(name)?;
    delete_printer_driver_package(inf)
}

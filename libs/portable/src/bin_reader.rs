use std::{
    fs::{self},
    io::{Cursor, Read},
    path::Path,
};

#[cfg(windows)]
const BIN_DATA: &[u8] = include_bytes!("../data.bin");
#[cfg(not(windows))]
const BIN_DATA: &[u8] = &[];
// 4bytes
const LENGTH: usize = 4;
const IDENTIFIER_LENGTH: usize = 8;
const MD5_LENGTH: usize = 32;
const BUF_SIZE: usize = 4096;

pub(crate) struct BinaryData {
    pub md5_code: &'static [u8],
    // compressed gzip data
    pub raw: &'static [u8],
    pub path: String,
}

pub(crate) struct BinaryReader {
    pub files: Vec<BinaryData>,
    pub exe: String,
}

impl Default for BinaryReader {
    fn default() -> Self {
        let (files, exe) = BinaryReader::read();
        Self { files, exe }
    }
}

impl BinaryData {
    fn decompress(&self) -> std::io::Result<Vec<u8>> {
        let cursor = Cursor::new(self.raw);
        let mut decoder = brotli::Decompressor::new(cursor, BUF_SIZE);
        let mut buf = Vec::new();
        decoder.read_to_end(&mut buf)?;
        Ok(buf)
    }

    pub fn write_to_file(&self, prefix: &Path) -> std::io::Result<()> {
        use std::path::Component;
        let normalized = self.path.replace('\\', "/");
        let relative = Path::new(&normalized);
        // generate.py stores paths with a leading ./ (or .\ on Windows).
        if relative.components().any(|part| !matches!(part, Component::Normal(_) | Component::CurDir))
            || !relative.components().any(|part| matches!(part, Component::Normal(_)))
            || normalized.contains(':')
        {
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "Invalid portable archive path"));
        }
        let p = prefix.join(relative);
        if let Some(parent) = p.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }
        if p.exists() {
            // check md5
            let f = fs::read(&p)?;
            let digest = format!("{:x}", md5::compute(&f));
            let md5_record = String::from_utf8_lossy(self.md5_code);
            if digest == md5_record {
                // same, skip this file
                println!("skip {}", &self.path);
                return Ok(());
            } else {
                println!("writing {}", p.display());
                println!("{} -> {}", md5_record, digest)
            }
        }
        fs::write(p, self.decompress()?)
    }
}

#[cfg(test)]
mod tests {
    use super::BinaryData;
    use std::{fs, io::ErrorKind};

    #[test]
    fn extracts_generator_relative_paths() {
        let root = std::env::temp_dir().join(format!("subnetdesk-unpack-test-{}", std::process::id()));
        // Brotli-compressed "hello", as stored by generate.py.
        let raw = &[11, 2, 128, 104, 101, 108, 108, 111, 3];
        for path in [r".\SubnetDesk.exe", "./librustdesk.dll", r".\data\app.so"] {
            let file = BinaryData {
                md5_code: b"5d41402abc4b2a76b9719d911017c592",
                raw,
                path: path.to_owned(),
            };
            file.write_to_file(&root).unwrap();
            assert_eq!(fs::read(root.join(path.replace('\\', "/"))).unwrap(), b"hello");
        }
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_paths_outside_the_runtime_directory() {
        for path in [
            "", ".", "./", "../escape", r".\..\escape", "/escape", r"C:\escape",
            "C:escape", r"\\server\share\escape", "file:stream",
        ] {
            let file = BinaryData {
                md5_code: b"",
                raw: b"",
                path: path.to_owned(),
            };
            assert_eq!(
                file.write_to_file(std::path::Path::new("unused")).unwrap_err().kind(),
                ErrorKind::InvalidData,
                "{path:?}",
            );
        }
    }
}

impl BinaryReader {
    fn read() -> (Vec<BinaryData>, String) {
        let mut base: usize = 0;
        let mut parsed = vec![];
        assert!(BIN_DATA.len() > IDENTIFIER_LENGTH, "bin data invalid!");
        let mut iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
        if iden != "rustdesk" {
            panic!("bin file is not valid!");
        }
        base += IDENTIFIER_LENGTH;
        loop {
            iden = String::from_utf8_lossy(&BIN_DATA[base..base + IDENTIFIER_LENGTH]);
            if iden == "rustdesk" {
                base += IDENTIFIER_LENGTH;
                break;
            }
            // start reading
            let mut offset = 0;
            let path_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let path =
                String::from_utf8_lossy(&BIN_DATA[base + offset..base + offset + path_length])
                    .to_string();
            offset += path_length;
            // file sz
            let file_length = u32::from_be_bytes([
                BIN_DATA[base + offset],
                BIN_DATA[base + offset + 1],
                BIN_DATA[base + offset + 2],
                BIN_DATA[base + offset + 3],
            ]) as usize;
            offset += LENGTH;
            let raw = &BIN_DATA[base + offset..base + offset + file_length];
            offset += file_length;
            // md5
            let md5 = &BIN_DATA[base + offset..base + offset + MD5_LENGTH];
            offset += MD5_LENGTH;
            parsed.push(BinaryData {
                md5_code: md5,
                raw: raw,
                path: path,
            });
            base += offset;
        }
        // executable
        let executable = String::from_utf8_lossy(&BIN_DATA[base..]).to_string();
        (parsed, executable)
    }

    #[cfg(linux)]
    pub fn configure_permission(&self, prefix: &Path) {
        use std::os::unix::prelude::PermissionsExt;

        let exe_path = prefix.join(&self.exe);
        if exe_path.exists() {
            if let Ok(f) = File::open(exe_path) {
                if let Ok(meta) = f.metadata() {
                    let mut permissions = meta.permissions();
                    permissions.set_mode(0o755);
                    f.set_permissions(permissions).ok();
                }
            }
        }
    }
}

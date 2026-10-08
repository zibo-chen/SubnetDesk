#!/usr/bin/env python3

import re


def strip(s): return re.sub(r'\s+\n', '\n', re.sub(r'\n\s+', '\n', s))

common_css = open('src/ui/common.css', encoding='utf-8').read()
common_tis = open('src/ui/common.tis', encoding='UTF8').read()

index = open('src/ui/index.html', encoding='utf-8').read() \
    .replace('@import url(index.css);', open('src/ui/index.css', encoding='utf-8').read()) \
    .replace('include "index.tis";', open('src/ui/index.tis', encoding='utf-8').read().replace('include "icons.tis";', open('src/ui/icons.tis', encoding='utf-8').read())) \
    .replace('include "msgbox.tis";', open('src/ui/msgbox.tis', encoding='utf-8').read()) \
    .replace('include "ab.tis";', open('src/ui/ab.tis', encoding='utf-8').read())

remote = open('src/ui/remote.html', encoding='utf-8').read() \
    .replace('@import url(remote.css);', open('src/ui/remote.css', encoding='utf-8').read()) \
    .replace('@import url(header.css);', open('src/ui/header.css', encoding='utf-8').read()) \
    .replace('@import url(file_transfer.css);', open('src/ui/file_transfer.css', encoding='utf-8').read()) \
    .replace('include "remote.tis";', open('src/ui/remote.tis', encoding='utf-8').read()) \
    .replace('include "msgbox.tis";', open('src/ui/msgbox.tis', encoding='utf-8').read()) \
    .replace('include "grid.tis";', open('src/ui/grid.tis', encoding='utf-8').read()) \
    .replace('include "header.tis";', open('src/ui/header.tis', encoding='utf-8').read()) \
    .replace('include "file_transfer.tis";', open('src/ui/file_transfer.tis', encoding='utf-8').read()) \
    .replace('include "port_forward.tis";', open('src/ui/port_forward.tis', encoding='utf-8').read())

chatbox = open('src/ui/chatbox.html', encoding='utf-8').read()
install = open('src/ui/install.html', encoding='utf-8').read().replace('include "install.tis";', open('src/ui/install.tis', encoding='utf-8').read())

cm = open('src/ui/cm.html', encoding='utf-8').read() \
    .replace('@import url(cm.css);', open('src/ui/cm.css', encoding='utf-8').read()) \
    .replace('include "cm.tis";', open('src/ui/cm.tis', encoding='utf-8').read())


def compress(s):
    s = s.replace("\r\n", "\n")
    x = bytes(s, encoding='utf-8')
    return '&[u8; ' + str(len(x)) + '] = b"' + str(x)[2:-1].replace(r"\'", "'").replace(r'"',
                                                                                  r'\"') + '"'


with open('src/ui/inline.rs', 'wt', encoding='utf-8') as fh:
    fh.write('const _COMMON_CSS: ' + compress(strip(common_css)) + ';\n')
    fh.write('const _COMMON_TIS: ' + compress(strip(common_tis)) + ';\n')
    fh.write('const _INDEX: ' + compress(strip(index)) + ';\n')
    fh.write('const _REMOTE: ' + compress(strip(remote)) + ';\n')
    fh.write('const _CHATBOX: ' + compress(strip(chatbox)) + ';\n')
    fh.write('const _INSTALL: ' + compress(strip(install)) + ';\n')
    fh.write('const _CONNECTION_MANAGER: ' + compress(strip(cm)) + ';\n')
    fh.write('''
fn get(data: &[u8]) -> String {
    String::from_utf8_lossy(data).to_string()
}
fn replace(data: &[u8]) -> String {
    let css = get(&_COMMON_CSS[..]);
    let res = get(data).replace("@import url(common.css);", &css);
    let tis = get(&_COMMON_TIS[..]);
    res.replace("include \\\"common.tis\\\";", &tis)
}
#[inline]
pub fn get_index() -> String {
    replace(&_INDEX[..])
}
#[inline]
pub fn get_remote() -> String {
    replace(&_REMOTE[..])
}
#[inline]
pub fn get_install() -> String {
    replace(&_INSTALL[..])
}
#[inline]
pub fn get_chatbox() -> String {
    replace(&_CHATBOX[..])
}
#[inline]
pub fn get_cm() -> String {
    replace(&_CONNECTION_MANAGER[..])
}
''')

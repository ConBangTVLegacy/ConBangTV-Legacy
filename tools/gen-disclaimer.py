#!/usr/bin/env python3
"""Sinh app/UI/CBDisclaimerText.m từ linux/core/src/disclaimer.rs của repo chính (nguồn chung của mọi bản) — chạy lại mỗi khi
bản miễn trừ trách nhiệm đổi (VERSION tăng).
    python3 tools/gen-disclaimer.py <đường dẫn disclaimer.rs> app/UI/CBDisclaimerText.m
"""
import re
import sys


def rust_str(s):
    # Chuỗi Rust thường "…" (có thể có \" và \n) hoặc nối dòng bằng \ cuối dòng
    s = re.sub(r"\\\n\s*", "", s)
    return s.replace('\\"', '"').replace("\\n", "\n")


def objc(s):
    return '@"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    src = open(sys.argv[1], encoding="utf-8").read()
    version = re.search(r"pub const VERSION: i64 = (\d+);", src).group(1)
    title = rust_str(re.search(r'pub const TITLE: &str = "((?:[^"\\]|\\.)*)";', src, re.S).group(1))
    date = rust_str(re.search(r'pub const DATE: &str = "((?:[^"\\]|\\.)*)";', src, re.S).group(1))
    consent = rust_str(re.search(r'pub const CONSENT: &str = "((?:[^"\\]|\\.)*)";', src, re.S).group(1))
    body = re.search(r"pub const SECTIONS: &\[\(&str, &str\)\] = &\[(.*?)\n\];", src, re.S).group(1)
    # Mỗi mục: ( "tiêu đề", concat!("…", "…") ) hoặc ( "tiêu đề", "…" ) — tách theo ngoặc cấp 1, chuỗi đầu là tiêu đề
    pairs, depth, start, i = [], 0, None, 0
    while i < len(body):
        c = body[i]
        if c == '"':
            j = i + 1
            while body[j] != '"':
                j += 2 if body[j] == "\\" else 1
            i = j + 1
            continue
        if c == "(":
            if depth == 0:
                start = i
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                lits = [rust_str(x) for x in re.findall(r'"((?:[^"\\]|\\.)*)"', body[start:i + 1], re.S)]
                pairs.append((lits[0], "".join(lits[1:])))
        i += 1
    if not pairs:
        sys.exit("không đọc được SECTIONS")
    out = [
        "// TỆP SINH TỰ ĐỘNG bởi tools/gen-disclaimer.py từ linux/core/src/disclaimer.rs của repo chính — đừng sửa tay.",
        '#import "CBDisclaimer.h"',
        "",
        "const NSInteger CBDisclaimerVersion = %s;" % version,
        "NSString *const CBDisclaimerTitle = %s;" % objc(title),
        "NSString *const CBDisclaimerDate = %s;" % objc(date),
        "NSString *const CBDisclaimerConsent = %s;" % objc(consent),
        "",
        "NSArray *CBDisclaimerSections(void) {",
        "    return @[",
    ]
    for t, b in pairs:
        out.append("        @[%s, %s]," % (objc(t), objc(b)))
    out += ["    ];", "}", ""]
    open(sys.argv[2], "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("bản %s, %d mục" % (version, len(pairs)))


if __name__ == "__main__":
    main()

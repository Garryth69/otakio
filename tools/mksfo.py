"""Writes a PS Vita param.sfo in pure Python (replaces vita-mksfoex, so the VPK can be built on any OS / in CI).

The layout matches vita-mksfoex: the same 19 keys, sorted, with the same maximum lengths; only TITLE, STITLE, TITLE_ID
and APP_VER change.

  python tools/mksfo.py --title Otakio --title-id OTAK00001 --app-ver 01.10 out/param.sfo
"""
import argparse, struct

UTF8, INT32 = 0x0204, 0x0404

# key: (format, max length, default)
FIELDS = {
    "APP_VER": (UTF8, 8, "01.00"),
    "ATTRIBUTE": (INT32, 4, 0x8000),
    "ATTRIBUTE2": (INT32, 4, 0),
    "ATTRIBUTE_MINOR": (INT32, 4, 0x10),
    "BOOT_FILE": (UTF8, 32, ""),
    "CATEGORY": (UTF8, 4, "gd"),
    "CONTENT_ID": (UTF8, 48, ""),
    "EBOOT_APP_MEMSIZE": (INT32, 4, 0),
    "EBOOT_ATTRIBUTE": (INT32, 4, 0),
    "EBOOT_PHY_MEMSIZE": (INT32, 4, 0),
    "LAREA_TYPE": (INT32, 4, 0),
    "NP_COMMUNICATION_ID": (UTF8, 16, ""),
    "PARENTAL_LEVEL": (INT32, 4, 0),
    "PSP2_DISP_VER": (UTF8, 8, "00.000"),
    "PSP2_SYSTEM_VER": (INT32, 4, 0),
    "STITLE": (UTF8, 52, ""),
    "TITLE": (UTF8, 128, ""),
    "TITLE_ID": (UTF8, 12, ""),
    "VERSION": (UTF8, 8, "00.00"),
}


def build(values):
    keys = sorted(FIELDS)
    key_table = b""
    key_offsets = []
    for k in keys:
        key_offsets.append(len(key_table))
        key_table += k.encode() + b"\0"
    key_table += b"\0" * (-len(key_table) % 4)
    index, data = b"", b""
    for k, ko in zip(keys, key_offsets):
        fmt, max_len, default = FIELDS[k]
        v = values.get(k, default)
        if fmt == INT32:
            raw = struct.pack("<I", int(v))
        else:
            raw = str(v).encode("utf-8") + b"\0"
            if len(raw) > max_len:
                raise ValueError("%s is longer than %d bytes" % (k, max_len - 1))
        index += struct.pack("<HHIII", ko, fmt, len(raw), max_len, len(data))
        data += raw + b"\0" * (max_len - len(raw))
    key_start = 20 + len(index)
    data_start = key_start + len(key_table)
    header = struct.pack("<4sIIII", b"\0PSF", 0x0101, key_start, data_start, len(keys))
    return header + index + key_table + data


def write(path, title, title_id, app_ver, stitle=None):
    with open(path, "wb") as fh:
        fh.write(build({"TITLE": title, "STITLE": stitle or title, "TITLE_ID": title_id, "APP_VER": app_ver}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--title", required=True)
    ap.add_argument("--title-id", required=True)
    ap.add_argument("--app-ver", required=True, help="XX.YY, e.g. 01.10")
    args = ap.parse_args()
    write(args.out, args.title, args.title_id, args.app_ver)


if __name__ == "__main__":
    main()

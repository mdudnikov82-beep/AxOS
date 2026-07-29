"""Converts a flat raw binary (objcopy -O binary output) into a
$readmemh-compatible hex text file: one 32-bit little-endian word per
line, 8 hex digits, no '0x' prefix - the format instr_mem.v's
$readmemh() call expects. No existing tool in this repo does this
(AxOS's own FAT12 image tooling works in whole-sector terms, not
memory-word hex text)."""
import sys


def main():
    if len(sys.argv) != 3:
        print("usage: bin2hex.py <in.bin> <out.hex>")
        sys.exit(1)
    in_path, out_path = sys.argv[1], sys.argv[2]

    with open(in_path, "rb") as f:
        data = f.read()
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)

    with open(out_path, "w") as f:
        for i in range(0, len(data), 4):
            word = int.from_bytes(data[i:i + 4], "little")
            f.write("%08x\n" % word)

    print("wrote %d words (%d bytes) to %s" % (len(data) // 4, len(data), out_path))


if __name__ == "__main__":
    main()

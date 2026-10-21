#!/usr/bin/env bash
# Unpack the recovered Breachline place into something rbxmk can read.
#
# The download is a binary place whose chunks are zstd frames. rbxmk only
# understands uncompressed or lz4 chunks, so this repacks each chunk as
# stored-uncompressed. The result is byte-equivalent in content; it is a
# different encoding of the same instances.
#
# Usage:
#   bash scripts/unpack-breachline.sh [input] [output]
#
# Defaults: breachline-src/breachline-place.rbxl -> breachline/base.rbxl

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IN="${1:-$ROOT/breachline-src/breachline-place.rbxl}"
OUT="${2:-$ROOT/breachline/base.rbxl}"

python3 - "$IN" "$OUT" <<'PY'
import struct
import sys

try:
    import zstandard as zstd
except ImportError:
    sys.exit("zstandard is required: pip install zstandard")

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()

decoder = zstd.ZstdDecompressor()
out = bytearray(data[:32])  # magic, version, class/instance counts, reserved
pos = 32
chunks = 0

while pos < len(data):
    name = data[pos:pos + 4]

    # END and anything after it (the signature) pass through untouched.
    if name == b"END\0":
        out += data[pos:]
        break

    pos += 4
    comp, uncomp, reserved = struct.unpack("<III", data[pos:pos + 12])
    pos += 12
    payload = data[pos:pos + comp]
    pos += comp

    raw = decoder.decompress(payload, max_output_size=uncomp + 1024)

    # A stored chunk advertises compressedLength 0; the reader then takes
    # uncompressedLength bytes verbatim.
    out += name + struct.pack("<III", 0, len(raw), reserved) + raw
    chunks += 1

open(dst, "wb").write(bytes(out))
print(f"UNPACK_OK chunks={chunks} bytes={len(out)} out={dst}")
PY

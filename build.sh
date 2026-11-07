#!/bin/sh
# Build hc.zig into a small static binary.
#
#   ./build.sh                          # x86_64-linux, TLS, no embedded CA (use --ca at runtime)
#   CA=ca.pem ./build.sh                # embed your private CA (PEM) -> no --ca needed at runtime
#   TLS=0 ./build.sh                    # tcp/http only, ~1/3 the size
#   TARGET=aarch64-linux ./build.sh     # or riscv64-linux, x86-linux, arm-linux-musleabihf, ...
#   OUT=hc ZIG="python3 -m ziglang" ./build.sh
#
# Tested with Zig 0.17.1 (std.Io / std.crypto.tls APIs change between releases: pin the version).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ZIG=${ZIG:-zig}
TARGET=${TARGET:-x86_64-linux}
TLS=${TLS:-1}
OUT=${OUT:-hc-$TARGET}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [ "$TLS" = 1 ]; then with_tls=true; else with_tls=false; fi
if [ -n "${CA:-}" ]; then
    cp "$CA" "$work/ca.pem"
    echo "pub const pem: []const u8 = @embedFile(\"ca.pem\");" > "$work/cfg.zig"
else
    echo 'pub const pem: []const u8 = "";' > "$work/cfg.zig"
fi
echo "pub const with_tls = $with_tls;" >> "$work/cfg.zig"

# NB: per-module flags (-target, -O, -fsingle-threaded, ...) must precede the -M they
# apply to; placed after, Zig silently ignores them (you'd get a native Debug build).
$ZIG build-exe -target "$TARGET" -O ReleaseSmall -fsingle-threaded -fno-unwind-tables -fstrip \
    --dep embedded_ca -Mroot="$here/hc.zig" -Membedded_ca="$work/cfg.zig" \
    -femit-bin="$OUT"
ls -l "$OUT"

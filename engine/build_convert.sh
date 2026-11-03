# Rebuilds the Otakio engine with System.convertImage (run in Linux/WSL with VitaSDK installed).
# Usage: bash engine/build_convert.sh [path to the lpp-vita checkout, default ~/otakio-engine/lpp-vita]
set -e
PATCHES="$(cd "$(dirname "$0")/patches" && pwd)"
LPP="${1:-$HOME/otakio-engine/lpp-vita}"
cd "$LPP/source"
cp "$PATCHES/imgconv.c" include/imgconv.c
python3 "$PATCHES/patch_convertimage.py"
cd ..
export VITASDK=${VITASDK:-/usr/local/vitasdk} PATH=${VITASDK:-/usr/local/vitasdk}/bin:$PATH
sed -i 's/-lwebp /-lwebp -lsharpyuv /' Makefile 2>/dev/null || true
make -j8 2>&1 | grep -iE "error|undefined" | head -20 || true
ls -la eboot_unsafe.bin

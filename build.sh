#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
TOOLCHAIN="${TOOLCHAIN_DIR:-}"
FLAVOR="${CONFIG:-release}"
NO_TEST="${NO_TEST:-0}"

find_tool() {
  local name="$1"
  if [[ -n "$TOOLCHAIN" ]]; then
    for p in "$TOOLCHAIN/dist/$FLAVOR/$name" "$TOOLCHAIN/dist/release/$name" "$TOOLCHAIN/$name"; do
      if [[ -x "$p" ]]; then
        (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
        return 0
      fi
    done
  fi
  command -v "$name" 2>/dev/null && return 0
  echo "error: cannot find $name; set TOOLCHAIN_DIR or add toolchain to PATH" >&2
  return 1
}

run() { echo "+ $*"; "$@"; }

SCMDC="$(find_tool scmdc)"
SCMDSIM="$(find_tool scmdsim)"
VCS16SCMD="$(find_tool vcs16scmd)"

echo "[AliasOS] scmdc:     $SCMDC"
echo "[AliasOS] scmdsim:   $SCMDSIM"
echo "[AliasOS] vcs16scmd: $VCS16SCMD"

mkdir -p src/generated
rm -f src/generated/kernel_vcs.scmd src/generated/hello_vcs.scmd src/generated/sysinfo_vcs.scmd
run "$VCS16SCMD" vcs/kernel.vcs -o src/generated/kernel_vcs.scmd --prefix aos_kernel
run "$VCS16SCMD" vcs/hello.vcs -o src/generated/hello_vcs.scmd --prefix aos_hello
run "$VCS16SCMD" vcs/sysinfo.vcs -o src/generated/sysinfo_vcs.scmd --prefix aos_sysinfo
run "$SCMDC" build AliasOS.scmdproj

mkdir -p build/aliasos
cp cfg/public.cfg build/aliasos/public.cfg
cp cfg/boot_show.cfg build/aliasos/boot_show.cfg
cp cfg/AliasOS.cfg build/AliasOS.cfg

if [[ "$NO_TEST" != "1" ]]; then
  run tests/run.sh "$SCMDSIM" "$ROOT/build"
fi

rm -rf dist/cs2
mkdir -p dist/cs2
cp build/AliasOS.cfg dist/cs2/
cp -R build/aliasos dist/cs2/
printf '\n[AliasOS] Build complete.\n[AliasOS] Deploy directory: %s/dist/cs2\n' "$ROOT"
printf '[AliasOS] Copy its contents to game/csgo/cfg/, then run:\n          sv_cheats 1\n          exec AliasOS\n'

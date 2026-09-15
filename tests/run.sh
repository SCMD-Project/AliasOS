#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCMDSIM="${1:?usage: tests/run.sh /path/to/scmdsim [build-dir]}"
BUILD="${2:-$ROOT/build}"

cases=(
  demo.script
  fs_mutation.script
  argv_controls.script
  real_ui.script
  path_v2.script
  raw_alias.script
  raw_alias_transaction.script
  raw_alias_missing.script
  raw_alias_guard.script
  raw_history.script
  sysinfo.script
  raw_gc.script
)

expect_demo=("AliasOS 0.1-dev" "bin/" "root@alias:$" "cwd:" "home/" "hello" "world" "file created" "write mode: enter line tokens, then end to save" "saved" "line1" "line2" "AliasFS inodes: 6/16" "PID STATE APP" "[counter] done" "hello from vCS-16/2 userland")
expect_fs_mutation=("directory created" "file created" "saved" "directory not empty" "removed" "not found")
expect_argv_controls=("args:" "cancelled" "not found" "> line1")
expect_real_ui=("cwd:" "bin/" "sh" "taskkill" "/" "AliasOS command guide:")
expect_path_v2=("directory created" "cwd:" "home/" "project/" "docs/" "file created" "saved" "line1" "line2" "removed" "vCS-16/2 + SCMD alias runtime" "AliasFS capacity: 16 inodes, 1024 token cells")
expect_raw_alias=("raw alias slot:" "aos_str_1" "raw alias ready - type end to commit" "saved" "这是运行时才输入的字符串" "CS2里真的写进去了")
expect_raw_alias_transaction=("OLD_RAW_CONTENT" "cancelled" "NEW_RAW_CONTENT")
expect_raw_alias_missing=("raw alias not ready - define the shown slot and run rawready before end" "cancelled")
expect_raw_alias_guard=("raw alias not ready - define the shown slot and run rawready before end" "cancelled" "114514,hello world!")
expect_raw_history=("OLD_IMMUTABLE_RAW" "NEW_FILE_CONTENT" "removed")
expect_sysinfo=("$ sysinfo" "AliasOS system information:" "AliasOS 0.1-dev" "vCS-16/2: flags-free CFG-oriented virtual execution architecture" "raw strings: 32 immutable runtime objects" "AliasFS inodes: 5/16" "PID STATE APP" "1 RUNNING sh")
expect_raw_gc=("aos_str_1")

check_viewports() {
  local file="$1" case_name="$2"
  awk -v case_name="$case_name" '
    /^\[screen\]$/ { in_screen=1; n=0; next }
    in_screen && n < 25 {
      low=tolower($0)
      if (index(low,"[inputservice]") && index(low,"aliasos/")) {
        print case_name ": leaked AliasOS InputService noise: " $0 > "/dev/stderr"; bad=1
      }
      if (index($0,"[Console]")==1) {
        print case_name ": leaked Source echo/[Console] output: " $0 > "/dev/stderr"; bad=1
      }
      n++
    }
    END { exit bad ? 1 : 0 }
  ' "$file"
}

last_screen() {
  awk '
    /^\[screen\]$/ { buf=""; in_screen=1; next }
    in_screen { buf=buf $0 "\n" }
    END { printf "%s", buf }
  ' "$1"
}

for script in "${cases[@]}"; do
  base="${script%.script}"
  var="expect_${base}"
  eval 'expected=("${'"$var"'[@]}")'
  log="$(mktemp)"
  trap 'rm -f "$log"' RETURN
  echo "+ $SCMDSIM $BUILD --exec AliasOS --script $ROOT/tests/$script --no-interactive --no-ansi"
  if ! "$SCMDSIM" "$BUILD" --exec AliasOS --script "$ROOT/tests/$script" --no-interactive --no-ansi >"$log" 2>&1; then
    cat "$log" >&2
    echo "FAIL $script: simulator returned nonzero" >&2
    exit 1
  fi
  for text in "${expected[@]}"; do
    if ! grep -Fq -- "$text" "$log"; then
      cat "$log" >&2
      echo "FAIL $script: missing expected output: $text" >&2
      exit 1
    fi
  done
  check_viewports "$log" "$script"

  if [[ "$script" == raw_alias_transaction.script ]]; then
    cancel_line="$(grep -n -m1 -F 'cancelled' "$log" | cut -d: -f1 || true)"
    [[ -n "$cancel_line" ]] || { echo "FAIL $script: no cancel marker" >&2; exit 1; }
    tail -n "+$cancel_line" "$log" >"$log.tail"
    old_line="$(grep -n -m1 -F 'OLD_RAW_CONTENT' "$log.tail" | cut -d: -f1 || true)"
    new_line="$(grep -n -m1 -F 'NEW_RAW_CONTENT' "$log.tail" | cut -d: -f1 || true)"
    rm -f "$log.tail"
    [[ -n "$old_line" ]] || { echo "FAIL $script: committed old raw content did not survive cancel" >&2; exit 1; }
    if [[ -n "$new_line" && "$new_line" -lt "$old_line" ]]; then
      echo "FAIL $script: uncommitted raw content became visible before old content" >&2; exit 1
    fi
  elif [[ "$script" == raw_history.script ]]; then
    screen="$(last_screen "$log")"
    [[ "$screen" == *"OLD_IMMUTABLE_RAW"* && "$screen" == *"NEW_FILE_CONTENT"* ]] || {
      echo "FAIL $script: immutable raw TTY history did not survive rewrite/removal" >&2; printf '%s\n' "$screen" >&2; exit 1;
    }
  elif [[ "$script" == raw_gc.script ]]; then
    screen="$(last_screen "$log")"
    [[ "$screen" == *"aos_str_1"* ]] || {
      echo "FAIL $script: raw string object was not reclaimed after rm + cls" >&2; printf '%s\n' "$screen" >&2; exit 1;
    }
  fi

  echo "PASS $script"
  rm -f "$log"
  trap - RETURN
done

echo "AliasOS standalone regression: ${#cases[@]}/${#cases[@]} PASS"

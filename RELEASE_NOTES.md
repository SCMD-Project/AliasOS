# AliasOS 0.1-dev notes

## SCMD 0.11 native source migration

- AliasOS runtime is now stored as real `.scmd` modules under `src/runtime/`.
- Removed the external Python source generator, Python build wrapper, and Python regression runner.
- Build scripts call only `vcs16scmd`, `scmdc`, and `scmdsim`.
- SCMD 0.11 fixed arrays and `compile {}` replace generator-emitted scalar state and build-time initialization.
- `src/generated/` contains build outputs from `vcs16scmd` only; it is not the source of AliasOS runtime logic.
- Windows regression runner is PowerShell; Unix regression runner is POSIX-style shell/Bash.

## TTY / real-CS2 output correctness

- Source `echo` is not used for AliasOS terminal text; real CS2 prefixes it with `[Console]`. TTY text lowers through `console.print` / `echoln`.
- `con_filter_*` is not used because the tested real CS2 build reports those commands as unavailable.
- Commands update authoritative TTY history first, then perform `clear` + settle + resident redraw.
- Cold boot hides the Console only while the CFG graph initializes, then performs delayed `showconsole`, `clear`, and resident redraw.
- Final viewport tests reject visible AliasOS `[InputService]` paths and `[Console]`-prefixed TTY output.

## Paths / VFS

- Canonical tokens use `arg_<name>` to avoid CS2 command/convar collisions.
- `..` is supported with `arg_dotdot` fallback.
- Path capacity is 8 components.
- `cd`, `ls+`, `mkdir`, `touch`, `cat`, `write`, `rm`, and `rmdir` share the same multi-component resolver.
- `/bin`, `/etc`, and `/proc` are read-only virtual directories.

## Runtime strings

- Default `write` stores arbitrary runtime text in a 32-slot immutable `aos_str_N` object pool.
- A write transaction requires `rawready` before `end` can commit.
- Files and TTY history store object references, so old `cat` output stays historically correct after rewrite/removal.
- TTY history conservatively pins displayed raw objects until `cls`; unowned objects are then reusable.
- `writetok` remains the advanced structured token-line writer.

## vCS userland

- `vcs/sysinfo.vcs` is AOT-lowered by `vcs16scmd` and exposed as `sysinfo`.
- `sysinfo` queries live AliasFS inode/task state through the host SYS ABI.

## Validation

- SCMD 0.11.1 Release + ASan/UBSan: 68/68 CTest PASS.
- AliasOS standalone: 12/12 PASS with engine-message modeling enabled.
- Real CS2 remains the compatibility authority for Console timing/visibility semantics.

## SCMD 0.11.1 backend/source optimization

- Requires SCMD Toolchain 0.11.1.
- Direct `dst = array[index]` loads now use the compiler's balanced control-flow
  array-load lowering.
- TTY history and filesystem metadata keep their SCMD fixed-array representation
  without paying the previous full mux cost on direct reads.
- Removed only the hot internal export boundaries that benchmark as a net win;
  other internal exports remain intentionally as demand-load boundaries.
- Same `stats_ops.script` workload drops from 278,424 to 206,178 cumulative
  modeled commands relative to the original SCMD 0.11 no-Python build.
- Generated package drops from 18,274 to 11,934 CFG files in the measured clean build.
- AliasOS regression remains 12/12 PASS.

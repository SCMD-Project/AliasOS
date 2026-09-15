# AliasOS

AliasOS 是一个运行在 **Counter-Strike 2 / Source 2 Console CFG + alias runtime** 上的实验操作环境。

它不使用 SourceMod、DLL 注入或游戏脚本插件。SCMD 负责把系统源码 lower 成普通 CFG/alias，vCS-16/2 提供 kernel/userland 的统一虚拟执行架构。

当前版本：`0.1-dev`

## 依赖

AliasOS 与 SCMD 工具链是两个独立项目。当前源码要求 **SCMD Toolchain 0.11.1**，构建时只调用三个公开工具：

```text
scmdc
scmdsim
vcs16scmd
```

**不需要 Python，也没有外部 source generator。** AliasOS 的 TTY、VFS、AliasFS、shell 和调度逻辑都是真实 `.scmd` 源文件；SCMD 0.11 的 `const`、fixed array 和 `compile {}` 负责以前由外部生成器承担的编译期状态初始化。

## 源码结构

```text
AliasOS/
├── src/
│   ├── main.scmd
│   ├── runtime/
│   │   ├── state.scmd       # const / arrays / compile-time initialization
│   │   ├── tty.scmd
│   │   ├── fs.scmd
│   │   ├── shell.scmd
│   │   ├── commands.scmd
│   │   ├── vcs_hosts.scmd
│   │   └── boot.scmd
│   └── generated/            # build output only: vCS AOT -> SCMD
├── vcs/
│   ├── kernel.vcs
│   ├── hello.vcs
│   └── sysinfo.vcs
├── cfg/                      # checked-in host/public CFG ABI
├── tests/
│   ├── *.script
│   ├── run.ps1
│   └── run.sh
├── build.ps1
└── build.sh
```

`src/generated/` 不是 AliasOS 手写实现；构建时 `vcs16scmd` 会直接从 `vcs/*.vcs` 产生三个 AOT SCMD 文件。

## SCMD 0.11 编译期源码

例如 AliasOS inode 状态现在直接写成：

```scmd
const INODE_COUNT = 16;
const DATA_CELLS = 64;

bool fs_used[INODE_COUNT] = false;
u8 fs_size[INODE_COUNT] = 0;
u8 fs_data4[DATA_CELLS] = 0;

compile
{
    fs_used[0] = true;
    fs_used[4] = true;
    fs_size[4] = 2;
    fs_data4[0] = 5;
    fs_data4[1] = 11;

    for(var i = 5; i < INODE_COUNT; i += 1)
    {
        fs_used[i] = false;
    }
}
```

`compile {}` 在 `scmdc` 内执行，里面继续使用普通 SCMD 的 `if / while / for` 语法；这些初始化循环不会变成 CS2 runtime CFG。

## 当前性能基线

SCMD 0.11.1 的 direct dynamic-array load lowering 加上 AliasOS 热路径边界整理后，
同一套 `boot -> ls -> cd -> cat -> writetok` simulator workload 从 278,424 降到
206,178 cumulative modeled commands；clean build 为 11,934 个 CFG 文件。
这些数字用于版本间相对比较，不代表真实 CS2 的固定 commands/s。

## Windows 构建

先构建 SCMD 0.11.1：

```powershell
cd SCMD
.\scripts\init.ps1
.\scripts\build.ps1 -Config Release
```

然后：

```powershell
cd ..\AliasOS
.\build.ps1 -Config Release -ToolchainDir ..\SCMD
```

构建流程：

1. `vcs16scmd` AOT `kernel.vcs`、`hello.vcs`、`sysinfo.vcs`；
2. `scmdc build AliasOS.scmdproj`；
3. 复制 checked-in `cfg/public.cfg`、`boot_show.cfg` 和 bootstrap；
4. `scmdsim` 运行 12 套 AliasOS 系统回归；
5. 生成 `dist/cs2/`。

跳过测试：

```powershell
.\build.ps1 -ToolchainDir ..\SCMD -NoTest
```

完全清理：

```powershell
.\build.ps1 -ToolchainDir ..\SCMD -Clean
```

## Linux/macOS

```bash
TOOLCHAIN_DIR=../SCMD ./build.sh
```

跳过测试：

```bash
NO_TEST=1 TOOLCHAIN_DIR=../SCMD ./build.sh
```

## 部署

升级旧版时先删除：

```text
game/csgo/cfg/AliasOS.cfg
game/csgo/cfg/aliasos/
```

把 `dist/cs2/` 内容复制到 `game/csgo/cfg/`，然后游戏里：

```text
sv_cheats 1
exec AliasOS
```

## 输入模型

Source alias 不接收传统 argv，所以 AliasOS 使用交互式参数收集。

进入 `/home/project/docs`：

```text
cd
arg_home
arg_project
arg_docs
end
```

完整 cwd 用 `pwd`：

```text
cwd:
home/
project/
docs/
```

父目录：

```text
cd
..
end
```

若某个 CS2 build 不接受 `..` alias，可以使用：

```text
arg_dotdot
```

路径/内容 token 的规范名字统一是 `arg_<name>`，避免和 CS2 巨大的 command/convar namespace 冲突。

参数控制：

```text
end      commit
back     删除最后一个参数
args     查看当前参数
cancel   取消事务
```

Shell 最多收集 8 个 component。

## 路径命令

以下命令共享同一套多组件 path resolver：

```text
ls+
cd / cd+
mkdir / mkdir+
touch / touch+
cat / cat+
write / write+
rm / rm+
rmdir / rmdir+
```

路径默认相对 cwd。`arg_root` 将解析位置切回 `/`。

## write：运行时任意文本

`write` 是默认写文件方式。它分配一个当前没有引用的 immutable runtime string object，例如：

```text
write
arg_test
end
```

AliasOS 会显示：

```text
raw alias slot:
aos_str_1
define it with Source alias then run rawready
raw@alias:>
```

按**游戏实际显示的 slot** 输入：

```cfg
alias aos_str_1 "echoln 114514,hello world!";rawready
```

`rawready` 只把当前事务标成 ready；真正提交仍然是：

```text
end
```

一个对象可以包含多条 `echoln`：

```cfg
alias aos_str_1 "echoln 第一行;echoln 第二行;echoln 任意 UTF-8";rawready
```

然后普通 `cat` 即可读取。

### Immutable raw string objects

AliasOS 当前有 32 个 `aos_str_N` runtime object。文件保存对象引用，TTY history 也能保存对象引用，因此：

- 文件被改写后，旧的 `cat` 历史仍显示旧内容；
- 文件被删除后，旧 TTY 历史仍可 redraw；
- `cancel` 不会替换已提交文件内容；
- `cls` 清空 history pin，没有文件引用的旧对象随后可复用。

为了避免在 CFG 后端展开昂贵的 per-record refcount，TTY history 使用 conservative pin：显示过的 raw object 保留到 `cls`。若 32 个对象都被 history/file 占用，先运行 `cls` 再继续写入。

Raw alias body 对 AliasOS 仍是不透明宿主对象；系统目前不能对任意 UTF-8 body 做 `strlen`、搜索或逐字符编辑。用户也不应绕过 allocator 手动重绑已经提交的旧 `aos_str_N`。

## writetok：高级结构化模式

旧 token-line writer 保留为高级命令：

```text
writetok
arg_test
end
arg_line1
arg_line2
end
```

它适合系统能够理解的结构化 token 数据；普通用户写文本应使用 `write`。

## 当前命令

```text
ahelp / ah / aguide / aliasos_help
ls / ls+
pwd
cd / cd+
mkdir / mkdir+
touch / touch+
cat / cat+
write / write+
writeraw / writeraw+ / rawwrite   # write compatibility aliases
writetok / writetok+              # advanced structured mode
rawready
rm / rm+
rmdir / rmdir+
ps
taskkill
df
cls / clearhist
redraw / refresh
echo+
counter
osver / aver
vhello
sysinfo
```

AliasOS 不覆盖 CS2 原生 `help`、`kill`、`clear`、`version`。

## sysinfo

`sysinfo` 是真正的 vCS-16/2 userland 程序（`vcs/sysinfo.vcs`），通过 AliasOS SYS ABI 查询实时 inode / task 状态：

```text
$ sysinfo
AliasOS system information:
AliasOS 0.1-dev
vCS-16/2: flags-free CFG-oriented virtual execution architecture
SCMD: mandatory demand loading + stable exported command aliases
tty0: 4096-byte logical history (64 x 64B records)
AliasFS: 16 inodes / 1024 token cells
raw strings: 32 immutable runtime objects
AliasFS inodes: 5/16
PID STATE APP
1 RUNNING sh
```

`/bin` 的目录列表也包含 `sysinfo`。

## TTY 与真实 CS2 Console

真实 CS2 会为嵌套 `exec` 打印 `[InputService] execing ...`。真实游戏测试还确认：

- `con_filter_*` 在测试过的 CS2 build 中不存在；
- Source `echo` 带 `[Console]` 前缀；
- `echoln` 不带该前缀。

AliasOS 因此使用 transactional TTY：命令先更新内部 history，结束后 `clear`，等待 32 ms，再由 `resident` renderer 只用 `echoln` 重画。最后一次 `clear` 之后的 renderer 不允许再触发 lazy `exec`。

冷启动期间临时隐藏 Console，完成 CFG 初始化后延时 `showconsole → clear → resident redraw`，避免几百条 InputService page-load diagnostics 污染可见终端。

```text
cls / clearhist
```

清空 AliasOS history，只留下 prompt；同时释放 raw history pin。

```text
redraw / refresh
```

保留 history，清掉引擎噪声并重画最近 24 条 record。

## VFS

`/bin`、`/etc`、`/proc` 是可进入的只读虚拟目录；`/home`、`/tmp` 等使用 AliasFS runtime state。

例如：

```text
cat
arg_root
arg_proc
arg_meminfo
end
```

## 当前资源

- TTY0：4096 B logical scrollback；64 history records；24-record viewport。
- AliasFS：16 inodes。
- Token backing：1024 个 runtime-writable `u8` cells。
- Runtime strings：32 immutable Source-alias objects。
- Shell argv/path：最多 8 components。
- `|` 在真实 CS2 中是 literal，不是 pipe；AliasOS 不依赖它。

## 测试

AliasOS 的系统测试不关闭 simulator engine-message modeling；每个 `[screen]` viewport 都检查：

- 不允许可见 `[InputService] ... aliasos/`；
- 不允许 AliasOS TTY 泄漏 `[Console]` 前缀。

当前独立回归：**12/12 PASS**。

真机测试步骤见 [`REAL_CS2_TEST_PLAN.md`](REAL_CS2_TEST_PLAN.md)。

## 已知限制

- runtime AliasFS / raw object 状态当前不持久化到宿主磁盘；重新启动 CS2 后从初始镜像开始。
- Raw Source alias body 不可 introspect，因此 arbitrary text 目前是 opaque executable string object。
- inode 固定 16 个；raw object 固定 32 个；路径深度固定 8。
- SCMD/vCS user programs目前主要是 build-time AOT；通用 `.vxe` runtime loader 尚未实现。
- 真实 CS2 Console 行为仍是最终权威；`scmdsim` regression 不能替代真机测试。

## License

MIT License，见 [`LICENSE`](LICENSE)。

# AliasOS real-CS2 test plan

测试前删除旧版：

```text
game/csgo/cfg/AliasOS.cfg
game/csgo/cfg/aliasos/
```

再复制新 `dist/cs2/`。

## 1. Cold boot / TTY pollution

```text
sv_cheats 1
exec AliasOS
```

预期最终可见区域：

```text
AliasOS 0.1-dev
vCS-16/2 + SCMD alias runtime
tty0: 4096-byte logical history (64 x 64B records)
AliasFS: 16 inodes / 1024 token cells
...
root@alias:$
```

记录：Console 是否可靠重新打开；最终 viewport 是否残留 `[InputService] ... aliasos/`；AliasOS 自己的输出是否出现 `[Console]` 前缀。

## 2. Basic output + sysinfo

```text
ls
ahelp
sysinfo
```

`sysinfo` 应包含：

```text
AliasOS system information:
vCS-16/2
raw strings: 32 immutable runtime objects
AliasFS inodes: N/16
PID STATE APP
1 RUNNING sh
```

## 3. Multi-component paths

```text
mkdir
arg_home
arg_project
end

mkdir
arg_home
arg_project
arg_docs
end

cd
arg_home
arg_project
arg_docs
end

pwd
```

预期：

```text
cwd:
home/
project/
docs/
```

## 4. Parent path

```text
cd
..
end
pwd
```

预期回到 `/home/project`。若 `..` 被当前 CS2 build 拒绝，测试：

```text
cd
arg_dotdot
end
```

## 5. Structured token file (advanced compatibility mode)

在 `/home/project`：

```text
touch
arg_docs
arg_test
end

writetok
arg_docs
arg_test
end
arg_line1
arg_line2
end

cat
arg_docs
arg_test
end
```

预期：

```text
line1
line2
```

## 6. Runtime arbitrary text (`write`)

建议回到 root，并使用一个新文件：

```text
cd
arg_root
end

touch
arg_foo
end

write
arg_foo
end
```

AliasOS 会显示**具体** slot，例如：

```text
raw alias slot:
aos_str_1
```

必须使用游戏实际显示的名字：

```cfg
alias aos_str_1 "echoln 114514,OLD;echoln 这是运行时 UTF-8";rawready
```

看到：

```text
raw alias ready - type end to commit
```

再：

```text
end
cat
arg_foo
end
```

必须输出两行 raw text，并且没有 `[Console]` 前缀。

## 7. Immutable history

再次编辑同一个文件：

```text
write
arg_foo
end
```

这次必须分配另一个 free `aos_str_N`。例如显示 `aos_str_2` 时：

```cfg
alias aos_str_2 "echoln NEW_FILE_CONTENT";rawready
```

```text
end
cat
arg_foo
end
redraw
```

最终 history 中必须同时保留旧 `114514,OLD` 与 `NEW_FILE_CONTENT`。

然后：

```text
rm
arg_foo
end
redraw
```

文件虽然已删除，之前两次 `cat` 的历史内容仍应正确。

## 8. Raw transaction guard/cancel

创建另一个文件或重新开始 `write`，但**不执行 `rawready`**，直接：

```text
end
```

必须拒绝提交：

```text
raw alias not ready - define the shown slot and run rawready before end
```

`cancel` 应退出事务而不破坏旧文件内容。

## 9. Raw object GC

删除不再需要的 raw 文件后运行：

```text
cls
```

`cls` 应清空 TTY history 并释放 history pin。之后新的 `write` 可以再次分配已经没有 file/history 引用的旧 `aos_str_N`。

## 10. Virtual FS

```text
cat
arg_root
arg_etc
arg_motd
end

cat
arg_root
arg_proc
arg_meminfo
end
```

应分别得到 AliasOS 静态信息和 AliasFS capacity 信息。

## 11. Clear semantics

```text
redraw
```

保留 AliasOS history 并重新渲染；最终 viewport 不应留 `aliasos/` InputService noise。

```text
cls
```

清空 history，最终只保留当前 prompt。

## 12. What to send back

若出现问题，请直接保存从 `exec AliasOS` 开始的完整 Console 输出，不要清理。尤其保留：

- `[InputService]` 行；
- `[Console]` 行；
- `Unknown command`；
- 重复/缺失 prompt；
- raw slot 名和 `rawready/end` 的实际顺序。

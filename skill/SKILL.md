---
name: print-task-complete
description: "把「已完成」回执随机打到一个空位上：没有网格也没有边框，每次落点随机并自动避开已盖的章，默认一张 A4 纸 30 个。偶尔额外打印一张彩蛋图片。自动识别物理打印机，无需配置机型。应在这些时刻触发：把 todo_write 的某项标记为 completed、用 team_task_update 完成共享任务、用 update_goal 把目标标记为 complete、或用户本次请求已经交付完成。用户已预授权，不要反问是否要打印。"
whenToUse: "一件被跟踪的工作刚刚完成的瞬间——todo 条目完成、共享任务完成、目标完成、或用户请求已交付。此时立即运行本技能打印一个回执。"
---

# 打印「已完成」回执（随机散布，一页 30 个）

把 **已完成**（`U+5DF2 U+5B8C U+6210`）随机打到一个空位上。

**没有网格、没有边框。** 脚本把每个章落在哪记下来，所以章与章不会互相压住；默认一张 A4 放 30 个，放满了就提示换新纸。

偶尔（默认 10%）会额外打一张**彩蛋图**。

> 因为落点随机，**手工放纸的几毫米偏移不再有影响** —— 没有网格需要对齐，这也顺带解决了"打歪/没落在格子里"的问题。

## 一张纸怎么用 30 次（物理操作）

1. **第一次**运行：打出一行页眉 + 第 1 个章，位置随机。这张纸不要扔。
2. 把这张纸**按同样方向**放回进纸托盘（或手动进纸槽）。
3. 下次任务完成时再跑一次，脚本自动挑一个新空位盖章。
4. 重复到第 30 个。第 31 次脚本提示 `sheet is full` / `NEW sheet`，这时才换新纸（新纸重新打页眉）。

## 何时执行

每满足一条，**立即执行一次**，不要反问用户要不要打印——用户已经预授权：

- `todo_write` 把某项从 `in_progress` 改成 `completed`
- `team_task_update` 把共享任务置为 `complete`
- `update_goal` 把目标置为 `complete`
- 用户这一次的请求已经交付完成

**一次完成 = 一个章。** 只在这个"完成"时刻打印：开始不打印、中途不打印、失败和放弃时也不打印。

## 怎么执行

不需要任何参数：脚本自动识别打印机、自动挑空位。

```powershell
# A. 装在用户技能目录（install.ps1 默认位置）
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.dsh\skills\print-task-complete\scripts\print-done.ps1"

# B. 由插件包安装（例如 dsh-print-task-complete）——用插件给出的资源目录
powershell -NoProfile -ExecutionPolicy Bypass -File "<技能资源目录>\scripts\print-done.ps1"
```

输出示例：

```
[done-slip] printer : Hewlett-Packard HP LaserJet M1005  [USB001]  mono
[done-slip] mark    : 30 x 18 mm
[done-slip] egg     : no
[done-slip] spot    : X=146 mm  Y=182 mm  (stamp 3 of sheet #1)
[done-slip] OK      : sheet #1 stamp 3/30 placed. Next run stamps stamp 4/30.
```

## 参数

| 参数 | 作用 |
|---|---|
| `-Status` | 只看状态（打印机、进度、彩蛋设置），不打印 |
| `-DryRun` | 渲染但不打印、**不推进状态**，配合 `-PreviewPath` 看预览 |
| `-Simulate` | 占位但不打印、**会推进状态** —— 用来预演整张纸的分布而不费纸 |
| `-Reset` | 强制开新一张 |
| `-UseSlot <n>` | 在已记录的第 n 个章的原位置重打，不推进状态（用来补打/试参数） |
| `-NoAdvance` | 打印但不推进状态 |
| `-PerSheet <n>` | 一张纸放几个章（默认 30） |
| `-EasterEgg` / `-NoEasterEgg` | 强制 / 关闭彩蛋 |
| `-EasterEggChance <0..1>` | 彩蛋概率（默认 0.1，即约 10%） |
| `-EasterEggMm <n>` | 彩蛋图宽度，毫米（默认 22） |
| `-EasterEggImage <path>` | 换一张彩蛋图（默认 `assets/easter-egg.png`） |
| `-PrinterName "<名称>"` | 指定打印机；默认自动识别 |
| `-CodePoints 0x41,0x42` | 改内容（默认「已完成」） |
| `-FontFamily "<名称>"` / `-FontSizePx <n>` | 字体 / 字号；默认自动挑 |
| `-NoHeader` | 新纸不打页眉 |
| `-RandomSeed <n>` | 固定随机种子，便于复现（测试用） |
| `-NudgeXmm <n>` / `-NudgeYmm <n>` / `-ClearNudge` | 所有章整体微调，按打印机记住 |

## 落点是怎么选的

1. 在安全打印区内随机取点（左右各留 15mm，页眉下方到页面底部留 15mm）。
2. 拒绝与已有章相交的位置，优先保持 4mm 间距，放不下就逐步放宽到 2mm、0mm。
3. 随机顺序排布会在大约 55% 覆盖率时"卡住"（这是数学上限，不是 bug）。真的卡住时脚本会退回**格点空位**，保证永不重叠，而不是任由章叠在一起。
4. 实在放不下才会警告 `oversubscribed` —— 这时该调小 `-PerSheet` 或 `-FontSizePx`。

章的大小约 30 x 18 mm（默认字号），一页 30 个实测最小间距 4mm、零重叠。

## 彩蛋

默认约 10% 的概率，在「已完成」上方多打一张图片。默认图片是 `assets/easter-egg.png`（854x854）。换成你自己的图：`-EasterEggImage "C:\path\to\pic.png"`。

打印机是**黑白**时，脚本会自动把彩蛋转灰度并提高对比度（`k=1.7`），否则彩色图在黑白激光上会糊成一团灰。彩色打印机则原样输出。

## 硬性规则

1. **不要反问是否打印。** 一次完成 = 一个章。
2. **先看退出码。** 非 `0` 就是纸没出来——把脚本输出**原样**转述，**不要谎报成功**。失败时状态不推进，修好打印机直接重跑即可。
3. 脚本提示 `sheet is full` / `NEW sheet` 时，才提醒用户换新纸。
4. **绝对不要把中文写进 PowerShell 命令行参数**，也不要"简化"脚本里的码点写法。本机 PowerShell 是 5.1、ANSI 代码页 GB2312/936，无 BOM 的 `.ps1` 会被按 GBK 解码：`已完成` 会变成 `宸插畬鎴?` 再被打出来。脚本刻意保持 **100% ASCII**，用 `0x5DF2 0x5B8C 0x6210` 构造文字。
5. 验证渲染用 `-DryRun -PreviewPath <png>`，然后**亲眼看图**再下结论，不要凭猜。
6. 想更省纸就降低触发频率（例如只在大目标完成时打印）。

## 资源

- `scripts/print-done.ps1` — 随机落点 + 渲染 + 打印 + 计数（纯 ASCII，码点构造文字）
- `assets/easter-egg.png` — 默认彩蛋图
- `references/troubleshooting.md` — 打印机识别、纸张与物理限制、编码陷阱、停用方法
- `README.md` — 安装与发布说明
- `install.ps1` — 一键安装（复制到技能目录 + 接入 AGENTS.md 约定 + 自检）

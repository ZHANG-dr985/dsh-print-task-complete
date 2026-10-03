# print-task-complete

给 DeepSeek Harness 用的技能：**任务完成时，在 A4 纸上随机打一个「已完成」回执。**

**没有网格、没有边框。** 脚本每次挑一个空位盖章，并记住已经盖在哪，所以章与章不会互相压住；一张纸默认放 **30 个**。偶尔（约 10%）还会额外打一张**彩蛋图**。

落点随机，所以**手工放纸的几毫米偏移不再有影响** —— 没有网格需要对齐。打印机**自动识别**，不写死任何机型。

## 安装

### 方式 A：一键安装（推荐）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本会：把技能复制到用户技能根目录（`$env:DSH_HOME\skills`，默认 `%USERPROFILE%\.dsh\skills`）→ 把"任务完成就打印"的约定写进 `$env:DSH_HOME\AGENTS.md` → 自动识别打印机并报状态。

常用开关：

```powershell
... -File .\install.ps1 -Scope Project      # 装到当前项目而不是整个用户
... -File .\install.ps1 -NoInstructions     # 只装文件，不动 AGENTS.md
... -File .\install.ps1 -Test               # 装完立刻打一个试
... -File .\install.ps1 -PrinterName "HP LaserJet M1005"
```

### 方式 B：手动

把本文件夹（连同 `SKILL.md`）放到任一被扫描的技能根目录下，目录名保持 `print-task-complete`：

| 作用域 | 路径 |
|---|---|
| 用户级 | `%USERPROFILE%\.dsh\skills\print-task-complete\` |
| 用户级（DSH_HOME 已设） | `%DSH_HOME%\skills\print-task-complete\` |
| 项目级 | `<项目根>\.dsh\skills\print-task-complete\` |

只放文件不会自动触发 —— 还要把 `assets/agents-snippet.md` 的内容（替换里面的两个占位符）加到对应的 `AGENTS.md` 里。

### 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.dsh\skills\print-task-complete\scripts\print-done.ps1" -Status
```

## 怎么用

装好之后**不需要你再做任何事**：agent 每次完成一件被跟踪的工作就会自动打一个。

**物理操作**（第一次之后）：

1. 第 1 次运行打出一行页眉 + 第 1 个章，位置随机。**这张纸别扔。**
2. 把这张纸按**同样方向**放回纸盒或手动进纸槽。
3. 下次完成时脚本自动挑一个新空位盖章。重复到第 30 个。
4. 第 31 次脚本提示 `sheet is full`，这时才换一张新纸（新纸重新打页眉）。

## 参数

| 参数 | 作用 |
|---|---|
| `-Status` | 只看状态（打印机、进度、彩蛋设置），不打印 |
| `-DryRun -PreviewPath out.png` | 渲染预览，不打印、不推进状态 |
| `-Simulate` | 占位但不打印、**会推进状态** —— 预演整张纸的分布而不费纸 |
| `-Reset` | 强制开新一张 |
| `-UseSlot 3` | 在已记录的第 3 个章的原位置重打，不推进状态 |
| `-NoAdvance` | 打印但不推进状态 |
| `-PerSheet 24` | 一张纸放几个章（默认 30） |
| `-EasterEgg` / `-NoEasterEgg` | 强制 / 关闭彩蛋 |
| `-EasterEggChance 0.2` | 彩蛋概率（默认 0.1） |
| `-EasterEggMm 30` | 彩蛋图宽度（毫米，默认 22） |
| `-EasterEggImage "C:\pic.png"` | 换彩蛋图 |
| `-PrinterName "..."` | 指定打印机；默认自动识别 |
| `-CodePoints 0x41,0x42` | 改打印内容（默认「已完成」） |
| `-FontFamily "SimSun"` / `-FontSizePx 90` | 字体 / 字号 |
| `-NoHeader` | 新纸不打页眉 |
| `-RandomSeed 7` | 固定随机种子，便于复现 |
| `-NudgeXmm <n>` / `-NudgeYmm <n>` / `-ClearNudge` | 所有章整体微调，按打印机记住 |

## 原理

- **随机落点**：在安全打印区内随机取点（四周留 15mm），拒绝与已有章相交的位置；优先保持 4mm 间距，放不下就放宽到 2mm、0mm。
- **格点保底**：随机顺序排布会在约 55% 覆盖率时"卡住"（数学上限，不是 bug）。真卡住时退回**格点空位**，保证永不重叠，而不是任由章叠在一起。默认字号（章 30x18mm）下实测 30 个**一次都没用到保底**。
- **打印成功才推进**：作业卡在后台超过 45 秒就报错退出，且**不推进状态** —— 修好打印机直接重跑，不会多盖一个章。
- **打印机自动识别**：`Get-Printer` 过滤掉 PDF、XPS、传真、OneNote 等虚拟设备，优先系统默认，选中后写回 `state.json`。
- **彩蛋自适应**：黑白打印机自动把彩蛋转灰度并提高对比度（`k=1.7`）；彩色打印机原样输出。
- **纯 ASCII 脚本**：见下文「编码陷阱」。
- **自带自检**：码点不对、字体画不出字（空白页）、打印机不存在，都会直接报错退出，不会把废纸送出来。

进度存在 `%LOCALAPPDATA%\dsh-print-task-complete\state.json`，**按打印机分开记账**，并且记录每个章的坐标用于避让。

### 编码陷阱（改代码前必读）

本机 `powershell.exe` 是 **Windows PowerShell 5.1**，中文 Windows 的 ANSI 代码页是 **GB2312 / 936**。PS 5.1 读取**没有 BOM** 的 `.ps1` 时按 ANSI 解码，所以脚本里的中文字面量会被静默毁掉：

| 环节 | 字节 |
|---|---|
| `已完成` 的 UTF-8 字节 | `E5 B7 B2 E5 AE 8C E6 88 90` |
| 被当成 GBK 分组 | `E5B7` `B2E5` `AE8C` `E688` + 落单 `90` |
| 解出的字符 | `宸` `插` `畬` `鎴` + `?` |

所以 `scripts/print-done.ps1` 和 `install.ps1` 刻意保持 **100% ASCII**，中文用 Unicode 码点构造：

```powershell
[int[]] $CodePoints = @(0x5DF2, 0x5B8C, 0x6210)   # 已完成
$Text = -join ($CodePoints | ForEach-Object { [char]$_ })
```

需要给脚本附带中文时，放进独立的 `.md` 资源文件按 UTF-8 字节读写。`assets/agents-snippet.md` 就是这么做的。

自检：

```powershell
$b = [System.IO.File]::ReadAllBytes('scripts\print-done.ps1')
@($b | Where-Object { $_ -gt 127 }).Count   # 必须为 0
```

## 卸载

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\skills\print-task-complete"
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\dsh-print-task-complete"   # 可选：清掉进度
```

再从 `AGENTS.md` 里删掉「任务完成回执」那一节。

## 分发与发布

这个目录本身就是一个完整、可直接分发的技能包。别人的机器上解压后跑 `install.ps1` 即可，不需要构建步骤。

```powershell
Compress-Archive -Path .\print-task-complete -DestinationPath .\print-task-complete.zip -Force
```

**关于 DSH 的两种安装形态**：

- **技能包（本包）**：靠 `SKILL.md` 被技能发现机制扫到，装到技能根目录即可。零依赖、零构建。
- **npm 插件 bundle**（`dsh-print-task-complete`）：DSH 的插件管理按**包名**安装的就是这个。它注册技能提供方，装完立即可用。姊妹仓库里那一份就是它。

> ⚠️ 实测提醒：在当前这个 DSH 部署里，把技能放进全部 4 个默认技能根目录后 `skill` 工具仍然查不到，**只有插件包注册的技能提供方立即可用**。所以如果你装完发现 agent 不认这个技能，先确认技能发现对你这个部署是否可用；`AGENTS.md` 那条路是稳的。

## 已知限制

- **仅 Windows**：依赖 PowerShell + .NET GDI+ 打印管线。
- **需要 CJK 字体**：默认内容是中文，系统没有中文字体时会报错（可用 `-FontFamily` 或 `-CodePoints` 改）。
- **要人工复用纸**：脚本只能在空位盖章，把纸放回去得靠人。
- **一张纸多次过定影**：反复加热同一张纸，30 次后早期章迹可能变淡或轻微蹭脏，属正常。
- **黑白打印机上的彩蛋**：会自动转灰度，细节比原图损失一些。
- **换纸靠提示**：脚本只能打印并提示 `NEW sheet`，不会自己去换纸。

## 许可

建议随包附一个 MIT LICENSE 再发布。

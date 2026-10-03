# dsh-print-task-complete

DeepSeek Harness 插件包（bundle）：装上之后，agent 每完成一件被跟踪的工作，就在 A4 纸上**随机打一个「已完成」回执**。

**没有网格、没有边框。** 脚本每回挑一个空位盖章，并记住已经盖在哪，所以章与章不会互相压住；一张纸默认 **30 个**。偶尔（约 10%）还会额外打一张**彩蛋图**。

落点随机，所以手工放纸的几毫米偏移不再有影响。打印机**自动识别**，不写死任何机型。

## 安装

### 方式 A：直接从 GitHub 装（不需要 npm 账号）

```powershell
plugin_manager install_bundle --target github:ZHANG-dr985/dsh-print-task-complete
```

pnpm 从公开仓库拉取并解包（约 15 秒）。装完 `print-task-complete` 就出现在会话的技能目录里。更新同理，重跑这条命令即可。

### 方式 B：按包名从 npm 装（包已发布到 npm 后）

```powershell
plugin_manager install_bundle --target dsh-print-task-complete
```

也可以在 DSH 的插件管理界面里直接填包名 `dsh-print-task-complete`。

### 方式 C：裸技能（零依赖，不经过插件加载器）

把本仓库的 `skill/` 目录复制到 `~/.dsh/skills/print-task-complete/`，然后跑里面的 `install.ps1`。适合只想拿技能、不想动插件配置的情况。

> **这个包做什么**：它是一个 cordis 插件，在 apply 时把 `print-task-complete` 注册进 Harness 的技能注册表（`ctx.skills.registerProvider`）。技能正文、脚本和彩蛋图随包发布在 `skill/` 下，通过 `resourceBase` 暴露给 agent。

## 它和"技能目录里的技能"是什么关系

DeepSeek Harness 有两条互不相同的路径，别混淆：

| | 技能目录（skill root） | 插件包（本包） |
|---|---|---|
| 形态 | 磁盘上的 `SKILL.md` + 资源 | npm 包 + `cordis.patch.yml` |
| 怎么来 | 手放 / 复制到 `~/.dsh/skills` | 按**包名**安装 |
| 能否按包名一键下载 | **不能**，技能目录没有这个功能 | **能**，这就是本包存在的理由 |

技能 UI（`dsh-client-ui-skill`）只负责 `/name` 调用和列出已发现的技能，它**不提供按包名下载**。在 DSH 里"通过包名一键下载"只能是插件包。

如果你更喜欢裸技能（零依赖），也可以直接把本包的 `skill/` 目录复制到 `~/.dsh/skills/print-task-complete/`，然后跑里面的 `install.ps1`。

## 装完之后

**不需要任何配置。** agent 会在任务完成时自动调用技能；也可以手动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill资源目录>\scripts\print-done.ps1" -Status
```

**物理操作**：

1. 第 1 次运行打出一行页眉 + 第 1 个章（位置随机）—— **这张纸别扔**
2. 把这张纸按**同样方向**放回纸盒或手动进纸槽
3. 下次完成时脚本自动挑一个新空位盖章，重复到第 30 个
4. 第 31 次提示 `sheet is full`，这时才换新纸

> 想让 agent 无条件执行（不依赖模型判断是否加载技能），把 `skill/assets/agents-snippet.md` 的内容（替换其中的 `__PRINT_SCRIPT__` / `__SKILL_DIR__` 占位符）加进 `~/.dsh/AGENTS.md`。也可以直接跑 `skill/install.ps1`。

## 参数

| 参数 | 作用 |
|---|---|
| `-Status` | 只看状态，不打印 |
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

进度存在 `%LOCALAPPDATA%\dsh-print-task-complete\state.json`，**按打印机分开记账**，并记录每个章的坐标用于避让。只有打印作业成功离开后台队列才推进状态，失败直接重跑不会多盖一个章。

### 彩蛋

默认约 10% 概率在「已完成」上方多打一张图（`skill/assets/easter-egg.png`）。黑白打印机上脚本会自动转灰度并提对比度（`k=1.7`），彩色打印机原样输出。换图用 `-EasterEggImage`。

## 卸载

```powershell
plugin_manager remove_bundle --target dsh-print-task-complete
```

再清掉进度（可选）：

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\dsh-print-task-complete"
```

## 平台要求

- **Windows**：依赖 PowerShell + .NET GDI+ 打印管线。
- **需要物理打印机**：自动跳过 PDF / XPS / 传真 / OneNote 等虚拟打印机；一台都没有时会报错并列出已安装的打印机。
- **需要中文字体**：内容是中文，系统没有中文字体时用 `-FontFamily` 指定，或用 `-CodePoints` 换成别的文字。

## 编码陷阱（改脚本前必读）

`skill/scripts/print-done.ps1` 和 `skill/install.ps1` 刻意保持 **100% ASCII**。原因：中文 Windows 上 `powershell.exe` 是 5.1、ANSI 代码页 GB2312/936，它会按 ANSI 解码**无 BOM** 的 `.ps1`，把中文字面量静默毁成乱码：

| 环节 | 字节 |
|---|---|
| `已完成` 的 UTF-8 字节 | `E5 B7 B2 E5 AE 8C E6 88 90` |
| 被当成 GBK 分组 | `E5B7` `B2E5` `AE8C` `E688` + 落单 `90` |
| 解出的字符 | `宸` `插` `畬` `鎴` + `?` |

所以中文用 Unicode 码点构造：

```powershell
[int[]] $CodePoints = @(0x5DF2, 0x5B8C, 0x6210)   # 已完成
$Text = -join ($CodePoints | ForEach-Object { [char]$_ })
```

需要给脚本附带中文时，放进独立的 `.md` 资源文件按 UTF-8 字节读写，不要写进 `.ps1`。

## 包结构

```
dsh-print-task-complete/
├── package.json          name / dsh.bundle.patch / engines
├── cordis.patch.yml      insert 一行挂载插件
├── lib/index.js          cordis 插件：注册 skill provider
├── skill/                技能本体
│   ├── SKILL.md
│   ├── README.md
│   ├── install.ps1
│   ├── scripts/print-done.ps1
│   ├── assets/easter-egg.png
│   ├── assets/agents-snippet.md
│   ├── assets/preview.png
│   └── references/troubleshooting.md
├── README.md
└── LICENSE
```

## License

MIT

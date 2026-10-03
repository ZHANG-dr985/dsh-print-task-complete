# print-task-complete — 排障与背景

## 打印机识别

脚本不写死机型。安装后会这样挑打印机：

1. `Get-Printer` 列出全部打印机；
2. **过滤掉虚拟设备** —— 名称/驱动/端口命中 `pdf`、`xps`、`fax`、`onenote`、`virtual`、`kingsoft`、`acrobat`、`PORTPROMPT:`、`FILE:` 的都被排除（这类"打印机"只会生成文件）；
3. 优先选**系统默认打印机**，否则按名称排序取第一个；
4. 选中的名字写进 `state.json`，以后固定用它；那台机器不见了会自动重新识别。

```powershell
Get-Printer | Select-Object Name, DriverName, PortName, PrinterStatus
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.dsh\skills\print-task-complete\scripts\print-done.ps1" -Status
```

本机的物理打印机是 `Hewlett-Packard HP LaserJet M1005`（`USB001`，A4，黑白）。`导出为WPS PDF`、`Microsoft Print to PDF` 会被自动跳过。

## 随机落点与进度

进度文件：`%LOCALAPPDATA%\dsh-print-task-complete\state.json`，按打印机分开记账：

```json
{
  "version": 2,
  "printer": "Hewlett-Packard HP LaserJet M1005",
  "perSheet": 30,
  "sheets": {
    "Hewlett-Packard HP LaserJet M1005": {
      "sheet": 1,
      "index": 4,
      "stamps": [ { "x0": 800, "y0": 1500, "x1": 1155, "y1": 1712, "egg": false } ]
    }
  },
  "nudges": { "...": { "x": 0, "y": 0 } }
}
```

`index` 是**下一个**要盖的章（1..PerSheet），`stamps` 是已经盖过的矩形（像素，300dpi），用来避让。

落点怎么选：

1. 在安全打印区内随机取点（四周留 15mm；有页眉时上边多留）。
2. 拒绝与已有章相交的位置；优先 4mm 间距，放不下放宽到 2mm、0mm。
3. 随机顺序排布在约 **55% 覆盖率会"卡住"** —— 这是随机顺序吸附的数学上限，不是 bug。真卡住时脚本退回**格点空位**，保证不重叠。
4. 连格点都满了才警告 `oversubscribed`，这时该调小 `-PerSheet` 或 `-FontSizePx`。

默认字号下章是 **30 x 18 mm**；一页 30 个实测最小间距 4mm、**零重叠**，而且保底格点一次都没触发。

常见操作：

| 想做什么 | 命令 |
|---|---|
| 看进度 | `print-done.ps1 -Status` |
| 纸换了，重新开始 | `print-done.ps1 -Reset` |
| 补打第 3 个章 | `print-done.ps1 -UseSlot 3` |
| 试渲染不打 | `print-done.ps1 -DryRun -PreviewPath out.png` |
| 预演整张分布（不费纸但会记进度） | `print-done.ps1 -Simulate` |
| 一页只要 20 个 | `print-done.ps1 -PerSheet 20` |
| 章大一点 | `print-done.ps1 -FontSizePx 110 -PerSheet 20` |

**失败不会多盖章**：只有打印作业成功离开后台队列之后状态才推进。打印机报错后直接重跑即可。

## 彩蛋

默认约 10% 概率在「已完成」上方多打一张图，默认是 `assets/easter-egg.png`（854x854）。

- 换图：`-EasterEggImage "C:\path\pic.png"`
- 改概率：`-EasterEggChance 0.25`（0 = 关闭）
- 改大小：`-EasterEggMm 30`
- 关掉：`-NoEasterEgg`
- 想看效果：`-DryRun -EasterEgg -PreviewPath egg.png`

**黑白打印机会自动转灰度**并提高对比度（`k=1.7`）。原图是彩色插画，转灰度后细节会损失一些，属正常。彩色打印机会原样输出。

彩蛋图会让章变高（约 +22mm），所以一张纸能放的数量会略受影响 —— 脚本仍然会避让，只是更早用上格点保底。

## 物理限制（重要）

- **必须人工复用纸。** 激光打印机没法在一张纸上自动跑 30 趟，得靠人把纸放回去。
- **放纸方向要一致。** 因为没有网格，几毫米的位置偏移无所谓；但**方向反了**会让前后的章错位到无法辨认，也会让页眉倒过来。
- **过定影 30 次。** 同一张纸反复被定影器加热，早期章迹可能变淡、发亮或轻微蹭脏，属正常。想要更好的效果就把 `-PerSheet` 调小。
- **卡纸与双张进纸。** 有手动进纸槽（优先进纸槽）的机型优先用它，比反复插纸盒更稳。
- **字倾斜是物理问题。** 如果打出来的字本身转了角度（不是位置偏），那是走纸歪斜：换单页优先进纸槽、夹紧导轨、把卷曲的纸压平。

## 常见故障

| 现象 | 原因 / 处理 |
|---|---|
| `no physical printer found` | 一台物理打印机都没检测到。用 `Get-Printer` 确认，或 `-PrinterName` 指定 |
| `remembered printer ... is gone` | 之前记的打印机拔了/改名了，脚本会自动重挑 |
| 退出码 1，`still stuck in the spooler after 45s` | 脱机 / 缺纸 / 休眠。处理后重跑，**不会多盖章** |
| `WARN: sheet is oversubscribed` | 一页塞不下这么多章。调小 `-PerSheet`，或调小 `-FontSizePx` |
| `sheet is filling up: used a tidy slot` | 随机位置放不下了，退回格点空位。正常，不重叠 |
| 退出码 1，`rendered text is blank` | 字体画不出这些字。用 `-FontFamily` 指定中文字体 |
| 退出码 1，`no CJK-capable font found` | 系统没有中文字体。装一个，或用 `-CodePoints` 换成 ASCII 内容 |
| 纸上出现 `宸插畬鎴?` 之类乱码 | 有人把码点写法改回了中文字面量。见下面「编码陷阱」 |
| 同一个章被打了两次 | 上次成功但被当成失败重跑了；用 `-UseSlot` 或 `-Reset` 纠正 |
| 一次完成打了两个章 | `AGENTS.md` 里有两份约定（用户级 + 项目级），删掉一份 |
| 彩蛋是灰的、细节糊 | 黑白打印机。想看彩色得用彩色打印机，或把图换成高对比度的线稿 |

## 编码陷阱（改代码前必读）

本机 `powershell.exe` 是 **Windows PowerShell 5.1**，ANSI 代码页 **GB2312 / 936**。PS 5.1 读取**无 BOM** 的 `.ps1` 时按 ANSI 解码，中文字面量会被静默毁掉：

| 环节 | 字节 |
|---|---|
| `已完成` 的 UTF-8 字节 | `E5 B7 B2 E5 AE 8C E6 88 90` |
| 被当成 GBK 分组 | `E5B7` `B2E5` `AE8C` `E688` + 落单 `90` |
| 解出的字符 | `宸` `插` `畬` `鎴` + `?` |

对策：所有 `.ps1` 保持 **100% ASCII**，中文用码点构造：

```powershell
[int[]] $CodePoints = @(0x5DF2, 0x5B8C, 0x6210)   # 已完成
$Text = -join ($CodePoints | ForEach-Object { [char]$_ })
```

需要脚本附带中文时，放进独立的 `.md` 资源文件，按**字节**读写（`assets/agents-snippet.md` 就是模板，`install.ps1` 用 `ReadAllText(..., UTF8)` 读、`WriteAllText(..., UTF8 no BOM)` 写）。

自检：

```powershell
foreach ($f in @('scripts\print-done.ps1','install.ps1')) {
  $b = [System.IO.File]::ReadAllBytes("$env:USERPROFILE\.dsh\skills\print-task-complete\$f")
  "$f non-ASCII: " + @($b | Where-Object { $_ -gt 127 }).Count   # 必须为 0
}
```

## 停用

- **临时**：从 `AGENTS.md` 里删掉「任务完成回执」那一节。
- **彻底**：删目录 + 删进度文件 + 删 `AGENTS.md` 那一节。

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\skills\print-task-complete"
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\dsh-print-task-complete"
```

技能根目录是热监视的，删掉不需要重启。`AGENTS.md` 的改动在下一次请求生效。

## 想让它更自动 / 更省纸

- **更自动**：本包靠 `AGENTS.md` 约定驱动，最终由模型决定何时调用。要"每次回合结束必然打印"需要一个真正的插件，订阅宿主事件 `agent/turn-stopping`，在回调里起子进程跑同一个脚本。代价是纯聊天也会盖章。
- **更省纸**：升高触发门槛（只在大目标完成时打）；`-PerSheet` 调大；或者关掉彩蛋（彩蛋章更高）。
- **更好看**：`-RandomSeed` 固定后分布可复现；`-PerSheet 20` 会让章更大更舒展。

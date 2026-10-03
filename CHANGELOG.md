# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。按包名安装的用户拿到的是**安装时点的最新已发布版本**；要升级就重新执行一次安装（或等 DSH 的插件管理更新）。

## 0.2.0

**破坏性变更** —— 版式从"网格"改为"随机散布"。

- **移除网格与格子边框**：不再画任何网格线或格子框，纸面只留页眉和章。
- **随机落点**：每个章落在安全打印区内的随机空位；脚本记录已盖的矩形并拒绝相交的位置。
- **保底格点**：随机顺序排布在约 55% 覆盖率会"卡住"（随机顺序吸附的数学上限）。卡住时退回格点空位，保证永不重叠。
- **打印彩蛋**：默认约 10% 概率在「已完成」上方多打一张图片。黑白打印机自动转灰度并提高对比度（k=1.7）。
- 章缩小到约 30 x 18 mm，使 30 个章能在一页内零重叠放下。
- 参数变化：
  - 新增 `-PerSheet`、`-Simulate`、`-EasterEgg`、`-NoEasterEgg`、`-EasterEggChance`、`-EasterEggMm`、`-EasterEggImage`、`-NoHeader`、`-RandomSeed`
  - 删除 `-Columns` / `-Rows`（无网格）、`-MarkOffsetXmm` / `-MarkOffsetYmm`（改为通用微调 `-NudgeXmm` / `-NudgeYmm` / `-ClearNudge`）
- 状态文件 schema 升至 v2：按打印机记录 `stamps`（每个章的坐标）用于避让；v1 的 `offsets` 自动迁移为 `nudges`。
- `install.ps1` 改为**幂等**：用 `<!-- dsh-print-task-complete:begin/end -->` 标记包裹 `AGENTS.md` 段落，重装时原地替换而不是跳过或重复追加。
- 新增 `scripts/verify.mjs` 发布前校验（`prepublishOnly`）：校验 patch 挂载的包名、插件契约、技能正文 frontmatter、`resourceBase` 可达性、以及**所有 `.ps1` 必须是纯 ASCII**。

> 升级说明：0.1.0 的网格纸不再适用（纸上印着 30 个格子框），换一张新纸并 `-Reset` 即可。

## 0.1.0

首个版本。

- 技能：任务完成时在 A4 网格纸上盖一个「已完成」章，一张纸 30 格。
- 网格 + 格子边框；每格一个章，脚本记录进度。
- 打印机自动识别（跳过 PDF / XPS / 传真等虚拟打印机）。
- 纯 ASCII 脚本 + Unicode 码点构造文字，规避 PowerShell 5.1 的 GBK 解码陷阱。
- npm bundle 形态：`cordis.patch.yml` + `lib/index.js` 注册 skill provider。

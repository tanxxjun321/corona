# UI 与交互规格

## 视觉与信息架构方向

Mobbin 调研结论：

- 参考范围以 Web app 的 `Settings & Preferences`、`Setting Up`、`Searching & Finding`、`Filtering & Sorting`、`Dropdown Menu`、`Dialog` 和 `Table` 模式为主。
- 这些模式适合迁移到本项目的设置窗口、权限引导、隐藏区面板、搜索面板和布局编辑器。
- Mobbin 上大量移动端大卡片、营销 hero、强品牌渐变和内容流式首页不适合本项目；本项目是低频配置、高频轻交互的 macOS 菜单栏工具。

总体 UI 风格：

- 采用 macOS 原生、安静、紧凑的系统工具风格，优先使用 SwiftUI/AppKit 原生控件、系统字体、系统材质、系统强调色和 SF Symbols。
- 信息密度接近系统设置、Raycast/Alfred 类工具面板，而不是 SaaS dashboard 或移动 app 首页。
- 默认浅色和深色模式都必须可用；不要绑定单一品牌色主题。强调色只用于主操作、当前选中状态和危险/警告状态。
- 圆角保持克制：popover、列表行、输入框、分区容器遵循 macOS 原生半径；不要使用大圆角卡片堆叠。
- 图标优先承载操作含义，文字用于状态、名称和不可误解的命令；图标按钮必须有 tooltip 或 accessibility label。
- 面板内避免营销文案，只说明当前状态、后果和下一步操作。

主要界面形态：

- 主状态项：只承担入口和状态提示，图标应在系统菜单栏中低存在感，不做彩色品牌标识。
- 隐藏区面板：小型 popover，像菜单栏扩展抽屉，优先展示图标网格或紧凑列表，不做完整窗口。
- 搜索面板：命令面板风格，顶部搜索框、下方结果列表，支持键盘上下选择和回车触发。
- 设置窗口：左侧窄导航，右侧分组表单；每个设置项是一行 label + control + 可选说明。
- 布局编辑器：三列分区管理面板，使用可拖拽列表或图标条，不做复杂仪表盘。
- 权限页：步骤式设置引导，明确区分必需权限和增强权限。

## 参考模式到本项目的映射

| Mobbin 参考模式 | 本项目落点 | 实现要求 |
| --- | --- | --- |
| Settings & Preferences | 设置窗口 | 左侧导航 + 右侧分组表单，避免整页卡片化 |
| Setting Up / Onboarding | 权限页 | 按步骤展示 Accessibility、Screen Recording 和降级能力 |
| Searching & Finding | 搜索面板 | 命令面板式搜索，支持键盘优先操作 |
| Filtering & Sorting | 布局编辑器 | 分区筛选、排序、默认落点和隐藏策略 |
| Dropdown Menu | 主状态项菜单、item 右键菜单 | 命令短、分组清晰、危险操作隔离 |
| Dialog / Banner | 错误、权限、移动失败提示 | 非阻塞优先；阻塞弹窗只用于不可恢复操作 |
| Table / Stacked List | 设置列表、诊断列表、隐藏项列表 | 行高紧凑，状态和操作在同一行可扫读 |

## 主状态项

主状态项位于菜单栏右侧，承担：

- 展示/隐藏 hidden 区。
- 打开设置。
- 打开布局编辑器。
- 显示权限状态。
- 触发搜索或隐藏区面板。

未授权 Accessibility 时：

- 主状态项可点击。
- 菜单显示“需要辅助功能权限”。
- 隐藏、移动、临时展示入口禁用。
- 图标可带警告状态点或斜杠变体，但不要使用持续弹窗打扰用户。

## 权限页

权限页必须区分：

- 必需：Accessibility。
- 可选：Screen Recording。

Accessibility 缺失文案：

```text
需要辅助功能权限来识别和移动菜单栏图标。没有该权限，应用无法隐藏或恢复第三方菜单栏项。
```

Screen Recording 缺失文案：

```text
没有屏幕录制权限时，应用会使用应用图标或占位图展示隐藏项；隐藏和展示功能仍可使用。
```

页面结构：

- 顶部显示当前权限总状态，例如“需要 1 项权限”或“所有核心功能已启用”。
- 权限列表按重要性排序：Accessibility 在前，Screen Recording 在后。
- 每项权限使用状态图标、短说明、主要操作按钮和降级说明。
- 系统设置跳转失败时提供手动路径说明，但不默认展开长说明。
- 权限授予后自动刷新状态，不要求用户重启应用。

## 隐藏区面板

隐藏区面板展示 hidden 或 alwaysHidden 分区。

视觉结构：

- 默认使用紧凑图标网格；当 item 名称重要或图标不可用时切换为列表。
- 面板宽度和高度有上限，超出时内部滚动，不改变菜单栏主窗口位置。
- 当前临时展示中的 item 需要有轻量状态标识。
- alwaysHidden 分区与 hidden 分区应有明确分隔，但不要使用嵌套卡片。

无 Screen Recording 模式：

- 显示应用 bundle icon。
- 显示 `displayName`。
- 图标失败时显示首字母或通用状态项符号。
- 不提示“功能不可用”，只提示“真实图标预览未启用”。

Screen Recording 增强模式：

- 显示真实菜单栏项像素缩略图。
- 缩略图本地缓存。
- 权限撤销时自动回退到 bundle icon。

点击行为：

- 左键：临时展示 item，点击其菜单。
- 右键：显示本应用操作菜单，例如移动到 visible/hidden/alwaysHidden、自定义名称、忽略该项。
- 双击：可配置为临时展示或移动到 visible。

## 布局编辑器

布局编辑器展示三个分区：

- Visible
- Hidden
- Always Hidden

视觉结构：

- 三个分区并列展示，分区标题下显示 item 数量和默认落点状态。
- item 行展示图标、名称、source app、状态徽标和拖拽把手。
- 分区为空时显示一行空状态提示和可执行的下一步，例如“拖入图标以隐藏”。
- 使用 toolbar 承载搜索、筛选、重置布局和诊断导出入口。

交互：

- 拖拽 item 到目标分区。
- 分区内拖拽排序。
- 设置新出现图标默认落点。
- 启用/禁用 always-hidden 分区。
- 无 Screen Recording 时使用 bundle icon 或占位图。

保存：

- 用户拖拽后立即更新内存期望布局。
- 实际 move 成功后写入 `savedSectionOrder`。
- move 失败时 UI 回滚到最新 cache，并显示非阻塞错误。

## 快捷键与触发

支持触发：

- 点击主状态项。
- hover 主状态项。
- scroll 菜单栏区域。
- 快捷键切换 hidden 区。
- 快捷键切换 alwaysHidden 区。
- 快捷键打开搜索。

默认：

- 点击展示 hidden 区。
- 自动重隐藏开启。
- hover 默认关闭。
- scroll 默认可配置。

## 自动重隐藏 UX

重隐藏前检查：

- 是否还有菜单/弹窗窗口显示。
- 最近是否有鼠标移动、点击或滚轮。
- 当前是否有临时展示任务还在执行。

用户可配置：

- smart：菜单关闭、用户停止输入或前台应用变化后重隐藏。
- timer：固定秒数后重隐藏。
- appSwitch：前台应用变化后重隐藏。

## 搜索

搜索面板应采用命令面板风格：

- 顶部单一搜索框，获得焦点后直接输入。
- 结果按 visible、hidden、alwaysHidden 和最近使用分组。
- 每条结果展示图标、名称、source app、当前分区和可执行动作。
- 支持键盘选择、回车临时展示、Command + Return 移到 visible、Escape 关闭。
- 无结果时显示短提示，不展示大插画。

搜索数据：

- item displayName。
- source app name。
- bundle id。
- 自定义名称。

无 Screen Recording：

- 搜索仍可用。
- 结果使用 bundle icon/占位图。

有 Screen Recording：

- 结果显示真实菜单栏缩略图。

## 设置项

MVP 必需：

- 开机启动。
- 显示/隐藏主图标。
- 自动重隐藏开关和间隔。
- 新图标默认分区。
- always-hidden 分区开关。
- Screen Recording 增强缩略图开关。
- 诊断日志开关。

高级设置：

- spacer 宽度策略。
- 刘海屏 overflow。
- 多显示器行为。
- 重置布局。
- 导出诊断。

# 阶段开发路线

## P0：项目骨架与权限外壳

目标：应用可以启动为菜单栏 app，显示主状态项、设置入口和权限状态。

交付物：

- `LSUIElement` 菜单栏应用外壳。
- 主 `NSStatusItem`、菜单、设置窗口、诊断日志开关。
- 权限状态模型：missing、hasRequired、hasAll。
- Accessibility 权限检测和系统设置引导。
- Screen Recording 权限检测，但只作为增强能力展示。

验收条件：

- 未授权 Accessibility 时不启动菜单栏项移动/扫描主链路。
- 用户能清楚看到缺少 Accessibility 后哪些功能不可用。
- 无 Screen Recording 时应用仍可进入主界面。

## P1：菜单栏项发现与身份模型

目标：能获取当前菜单栏项快照，建立稳定身份和缓存。

交付物：

- `MenuBarItem`、`MenuBarItemTag`、`ItemCache`。
- 窗口扫描 provider：
  - 官网完整版使用完整 Window Server provider。
  - App Store 版使用公开 API 降级 provider。
- source PID resolver：通过 AX extras menu bar frame 与 CG window bounds 匹配。
- instanceIndex 分配：同 namespace/title 项按稳定规则区分。

验收条件：

- 可输出当前菜单栏项列表、bounds、ownerPID、sourcePID、displayID。
- sourcePID 未解析的项不写入长期持久化。
- 多个同名状态项不会互相覆盖缓存。

## P2：控制项分区与基础隐藏/展示

目标：用自有 `NSStatusItem` 控制项划分 visible、hidden、alwaysHidden 区域，并跑通隐藏区 show/hide。

交付物：

- visible control item：主图标。
- hidden control item：隐藏区边界。
- optional always-hidden control item：深度隐藏区边界。
- 控制项状态：
  - showSection：普通宽度、可见。
  - hideSection：大宽度、透明、不可交互。
- 分区判定器：按控制项 bounds 对 item 分类。

验收条件：

- 用户点击主图标可切换隐藏区展示/隐藏。
- 隐藏区控制项在视觉隐藏时仍保留窗口和 bounds。
- 宽屏下 spacer status items 能扩展隐藏宽度。

## P3：移动执行器与布局恢复

目标：通过合成 `Command + 拖拽` 移动第三方菜单栏项，并能按保存顺序恢复布局。

交付物：

- `MoveDestination.leftOfItem/rightOfItem`。
- `MoveEventExecutor.move(item:to:on:skipInputPause:maxAttempts:)`。
- 事件串行化、用户输入暂停检测、光标隐藏/恢复。
- bounds 轮询、最终相对位置校验、失败重试。
- `savedSectionOrder` 保存和启动后恢复。

验收条件：

- 可把一个可移动第三方菜单栏项移动到 hidden 控制项左侧。
- 移动失败不会留下卡住的鼠标或拖拽状态。
- 应用重启后能恢复已保存布局。

## P4：临时展示与自动重隐藏

目标：隐藏图标可被临时移动到可见区，并按 timer 策略自动回到原分区。

交付物：

- temporary reveal controller。
- return destination 捕获：主邻居、备用邻居、原分区。
- pending relocation 持久化。
- auto-rehide 策略：首版只启用 timer。

验收条件：

- 临时展示后可按 timer 自动重隐藏。
- 图标所属应用在展示期间退出，重启后可恢复原分区。

## P5：硬化、缩略图与发布

目标：覆盖复杂硬件、权限降级、真实缩略图、发布签名和完整测试。

交付物：

- 多显示器 active menu bar display 选择。
- 刘海屏可用宽度和 overflow 策略。
- blocked item 恢复：`x == -1` 移回可见区。
- 无 Screen Recording 模式：bundle icon/文字/占位图。
- Screen Recording 增强模式：首版提供隐藏列表和扫描列表的真实像素缩略图。
- Developer ID 签名、hardened runtime、notarization、staple 和发布 zip。
- 完整自动化测试和手工验收清单。

验收条件：

- 外接显示器和刘海屏场景不误点系统菜单。
- 无 Screen Recording 时核心隐藏/恢复可用。
- 连续失败的重隐藏不会无限占用事件串行器。

## v1.1 延后项

- smart rehide：菜单弹窗关闭检测、前台 app 切换策略、用户输入暂停策略。
- click executor：左键、右键和备用点击。
- Screen Recording 增强：菜单栏背景取色、搜索预览、tooltip 预览。
- 多显示器高级策略、刘海屏专项策略。
- App Store 降级版。

## 不做事项

- 不直接修改第三方应用内部状态。
- 不把 `windowID` 作为长期身份。
- 不在没有 Accessibility 时尝试合成移动第三方菜单栏项。
- 不在 App Store 版中依赖私有 API 作为唯一实现路径。

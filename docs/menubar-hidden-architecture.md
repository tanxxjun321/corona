# macOS 菜单栏图标隐藏管理架构

## 目标

构建一个 macOS 菜单栏图标管理应用，支持把菜单栏图标划分为可见、隐藏、深度隐藏三个区域，并能通过点击、悬停、滚动或快捷键临时展示隐藏图标。隐藏不是修改第三方应用状态，而是通过系统认可的菜单栏拖拽行为，把图标移动到由本应用控制的分区锚点附近或屏幕外区域，再通过缓存、重排和恢复逻辑维持用户期望布局。

## 核心技术路线

应用自身创建若干 `NSStatusItem` 作为分区控制项：

- `visibleControlItem`：可见区入口，通常显示为主图标。
- `hiddenControlItem`：隐藏区边界锚点。
- `alwaysHiddenControlItem`：深度隐藏区边界锚点，可选启用。

隐藏区控制项在隐藏状态下保持存在，但把长度扩展到一个很大的值，例如 `10000` 点，并让按钮透明、不可交互。这样系统会把位于其左侧的菜单栏项推到屏幕外或可见范围之外。展示隐藏区时，控制项恢复普通宽度，隐藏图标重新进入可交互范围。

移动菜单栏项时不直接改写第三方应用内部状态，而是模拟用户 `Command + 拖拽` 菜单栏图标：

1. 通过 Window Server 获取菜单栏项窗口列表、窗口 ID、bounds、owner PID、标题和显示器位置。
2. 根据目标分区控制项计算拖拽起点/终点。
3. 构造带 Command 修饰键的 `CGEvent` 鼠标按下/抬起事件。
4. 把事件定向到对应窗口 ID 和目标进程。
5. 轮询窗口 bounds，确认图标确实移动。
6. 失败时重试，并在必要时发额外 mouse-up 清理系统拖拽状态。

## 具体隐藏机制

菜单栏隐藏的本质是“改变菜单栏项的物理排序和可见区域”，不是调用某个系统开关把图标标记为 hidden。实现依赖三个事实：

1. macOS 允许用户按住 Command 拖拽大多数菜单栏项。
2. `NSStatusItem` 可以设置自定义长度，并且这个长度会参与系统菜单栏排版。
3. 当某个状态项变得非常宽时，排在它左侧的菜单栏项会被挤出当前显示器可见菜单栏区域，但窗口对象仍然存在。

隐藏区控制项的状态变化如下：

```text
showSection:
  statusItem.length = variableLength 或窄分隔宽度
  button.enabled = true
  button.alpha = 1
  hidden items stay inline and clickable

hideSection:
  statusItem.length = 10000
  button.enabled = false
  button.alpha = 0
  hidden items are pushed left/off-screen
```

如果显示器非常宽，单个 `NSStatusItem` 的 10000 点宽度可能不够，可以动态添加额外 spacer status items，每个 spacer 同样设置为大宽度。spacer 只用于占位，不响应点击，不参与用户可见 UI。

分区边界推荐这样定义：

```text
visible section:
  items whose maxX/right edge is to the right of hiddenControlItem

hidden section:
  items left of hiddenControlItem and right of alwaysHiddenControlItem

always-hidden section:
  items left of alwaysHiddenControlItem
```

隐藏一个已有图标时，先把它移动到对应分区控制项左侧，再把该分区控制项切回 `hideSection`。展示时不需要逐个移动图标，只需要把控制项恢复普通宽度，系统排版会让这些图标重新回到可见范围。

### 拖拽移动细节

移动事件的关键是让目标应用相信它收到了用户的菜单栏 Command 拖拽：

```text
mouseDown:
  type = leftMouseDown
  flags = maskCommand
  location = target insertion point
  window under pointer = item.windowID
  target PID = sourcePID ?? ownerPID

mouseUp:
  type = leftMouseUp
  flags = []
  location = target insertion point
  window under pointer = anchor.windowID
  target PID = sourcePID ?? ownerPID
```

事件执行顺序：

1. 读取待移动 item 当前 bounds，记下初始 origin。
2. 根据 destination 计算投放点：
   - `leftOfItem(anchor)` 使用 `anchor.bounds.minX`。
   - `rightOfItem(anchor)` 使用 `anchor.bounds.maxX`。
3. 创建 `CGEventSource(.hidSystemState)`。
4. 设置本地事件 suppression 策略为允许，避免合成事件被系统抑制。
5. 隐藏光标并把光标 warp 到目标点；如果目标点离屏则跳过 warp。
6. 发送 Command + mouseDown。
7. 每 10 到 15 ms 轮询 item bounds，直到 origin 变化。
8. 发送 mouseUp，建议重复发送 2 次，降低拖拽状态卡住概率。
9. 再次等待 bounds 变化并校验最终相对位置。
10. 恢复光标位置并重启输入监听。

为了提高成功率，可以在事件发送周围临时创建 event tap：

- 第一层 tap 作为 barrier，确保入口 null event 被处理后才投递目标事件。
- 第二层 tap 监听 session event stream，确认相同窗口字段的事件出现。
- 必要时把事件在 pid tap 和 session tap 之间中继，直到收到响应或超时。

实际移动完成的判断不能只看事件发送是否成功，必须看 Window Server 返回的实时 bounds 是否变化，并最终满足：

```text
leftOfItem:  item.bounds.maxX == anchor.bounds.minX
rightOfItem: item.bounds.minX == anchor.bounds.maxX
```

## App Store 与权限矩阵

需要区分三类能力：用户在系统设置中授予的隐私权限、应用签名里的 sandbox entitlement、以及需要在 App Store Connect 解释或向 Apple 申请的临时例外。它们不是同一件事。

### 必需的用户授权

| 能力 | 是否核心必需 | 用途 | 申请方式 |
| --- | --- | --- | --- |
| Accessibility | 是 | 读取其他应用菜单栏辅助功能元素、监听/合成输入事件、驱动菜单栏项移动 | 用 `AXIsProcessTrustedWithOptions` 引导用户到 System Settings |
| Screen Recording / Screen & System Audio Recording | 非隐藏主链路必需，只有读取屏幕/窗口像素时需要 | 截取真实菜单栏图标当前外观、搜索界面真实图标预览、tooltip 真实图标、菜单栏背景取色 | 使用 ScreenCaptureKit 或相关屏幕捕获 API 时由系统提示 |

仅实现“隐藏/展示/重排”时，技术上可以不依赖屏幕录制权限。隐藏区列表也可以不申请屏幕录制权限，但 UI 只能展示非像素来源的替代信息，例如应用名称、bundle icon、已知系统符号、用户自定义图标或纯文字。

如果产品要求展示“真实菜单栏图标缩略图”，也就是第三方状态项在菜单栏中的当前像素外观，则需要屏幕录制授权。原因是公开 API 无法直接读取其他应用 `NSStatusItem` 的 image；可行实现通常只能捕获该状态项窗口或屏幕区域，再裁剪出图标。只要读取其他应用窗口/屏幕像素，就会进入屏幕录制权限范畴。

因此推荐设计两个模式：

- 无屏幕录制模式：显示应用 bundle icon、名称、占位符或用户自定义图标；隐藏、展示、重排功能完整可用。
- 屏幕录制增强模式：用户授权后，额外显示真实菜单栏项截图缩略图和菜单栏背景取色。

### Mac App Store 基础要求

Mac App Store 版本必须启用 App Sandbox：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

如果使用 XPC service，XPC target 也应启用 sandbox，并通过嵌入式 XPC 服务与主 app 通信。嵌入式同团队 XPC 不等同于全局 Mach service，通常不需要 `mach-lookup.global-name` 临时例外。

如果应用需要网络更新、账户、远程配置或诊断上传，再按实际功能添加：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

隐藏主链路本身不需要网络 entitlement。

### 可能需要说明或规避的能力

| 项目 | App Store 处理建议 |
| --- | --- |
| Accessibility 权限 | 不属于 entitlement 文件里的键，但审核时需要清楚说明为什么必须让用户手动授予。应用内文案应说明只用于管理菜单栏图标位置和触发用户请求的显示/隐藏操作。 |
| Screen Recording | 只在需要真实像素缩略图、窗口截图或菜单栏背景取色时申请。缺失时降级为 bundle icon、文字列表或占位图。审核说明中写明不录制用户内容、不上传截图。 |
| Global event tap / HID event tap | 高风险但可能是功能所需。只监听鼠标/滚轮/菜单栏区域，不记录按键内容；合成事件只在用户触发隐藏、展示、点击时执行。 |
| Apple Events automation | 该架构不需要向其他 app 发送 Apple Events。不要申请 `com.apple.security.automation.apple-events`，除非后续加入明确的自动化脚本能力。 |
| Temporary exception entitlements | 尽量不要使用。若确实需要，必须在 App Store Connect 的 App Sandbox information 中逐项解释用途、评估方式、启用功能和数组值含义。 |
| 私有 SkyLight/CGS API | Mac App Store 高拒审风险。若目标是上架，应设计 public-API fallback，或把完整能力放到 Developer ID notarized 版本。 |

### 私有 API 风险

完整可靠的菜单栏管理常会用到 Window Server 私有符号，例如：

```text
CGSGetProcessMenuBarWindowList
CGSGetScreenRectForWindow
CGSCopySpacesForWindows
CGSCopyActiveMenuBarDisplayIdentifier
```

这些 API 能提供精确的菜单栏窗口列表、离屏窗口 bounds、当前空间和活跃菜单栏显示器，是实现高可靠隐藏/恢复的关键。但它们不是公开 SDK 的稳定接口。若提交 Mac App Store，建议不要把这些符号直接编进商店版本，也不要通过动态加载规避审核。

可选路线：

- App Store 版本：只使用公开 API，功能降级为控制自有状态项、基础事件监听、有限窗口信息和用户手动排序辅助。
- 官网版本：Developer ID 签名并 notarize，保留完整 Window Server 桥接能力。
- 双版本：共享 UI、设置、布局求解器；把窗口扫描和移动执行器做成可替换 provider。

### 审核说明建议

提交审核时的说明应集中在用户价值和最小权限：

```text
This app helps users organize their macOS menu bar by moving menu bar items
only after explicit user actions such as clicking the app icon, using a
configured hotkey, or dragging items in the app's layout editor.

Accessibility permission is required to identify menu bar extras and perform
the same Command-drag operation that users can perform manually.

Screen Recording permission is optional and only used to render local icon
previews and menu bar appearance. Captured images are processed locally and
are not uploaded.
```

如果启用了任何 temporary exception entitlement，还需要在 App Store Connect 的 App Sandbox information 单独写明：

- entitlement key；
- 如何让审核人员验证；
- 为什么该能力是功能必需；
- 启用了什么功能；
- 如果值是数组，逐项解释每个值。

## 权限

基础功能需要辅助功能权限，用于读取菜单栏辅助功能结构、发送和监听输入事件。图像识别、截图取色或菜单栏背景适配等增强功能可能需要屏幕录制权限，但隐藏/重排主链路以辅助功能和窗口服务信息为核心。

权限状态应集中管理：

- `missing`：缺少必要权限，禁止启动菜单栏项扫描和事件模拟。
- `hasRequired`：具备核心隐藏/展示能力。
- `hasAll`：具备完整外观与辅助能力。

权限恢复后需要重新执行菜单栏扫描、控制项安装、布局恢复和事件监听启动。

## 菜单栏项模型

建议定义 `MenuBarItem` 值对象：

- `tag`：稳定识别标签，由 namespace、title、instanceIndex 组成。
- `windowID`：当前窗口 ID，易变，只用于本轮操作。
- `ownerPID`：窗口当前拥有进程。
- `sourcePID`：实际创建该菜单栏项的进程。
- `bounds`：当前窗口位置。
- `title`：窗口标题。
- `isOnScreen`：是否在屏幕可见列表中。
- `isMovable`：是否允许移动。
- `canBeHidden`：是否允许隐藏。

`windowID` 不能作为长期身份。持久化身份应优先使用：

```text
namespace:title
namespace:title:instanceIndex
```

当同一应用存在多个同名菜单栏项时，按窗口 ID 稳定排序后分配 `instanceIndex`，避免重排后缓存和自定义名称错位。

## 实际来源进程解析

较新的 macOS 版本可能让菜单栏项窗口由系统进程托管，窗口 owner PID 不再等于真实应用 PID。因此需要单独解析 `sourcePID`：

1. 获取当前菜单栏项窗口列表。
2. 遍历运行中应用的辅助功能 `extrasMenuBar`。
3. 读取其 children 的 frame。
4. 用 AX child frame 与 CG window bounds 做空间匹配。
5. 把匹配到的窗口 ID 映射到应用 PID。
6. 批量解析并缓存，避免对每个图标并发执行完整 AX 扫描。

如果部分项解析失败，不应立刻持久化其身份，也不应把它归入系统托管进程的 namespace。下一轮缓存成功解析后再进入重排和保存链路。

## 分区判定

菜单栏从右向左排列。可以根据控制项 bounds 把当前图标划分到不同区域：

- 可见区：位于隐藏区控制项右侧。
- 隐藏区：位于隐藏区控制项左侧、深度隐藏控制项右侧。
- 深度隐藏区：位于深度隐藏控制项左侧。

实际实现中应以实时 Window Server bounds 为准，不只依赖旧缓存。分区控制项即使视觉隐藏，也必须保留窗口和 bounds，因为它们是布局边界。

## 移动事件执行器

移动执行器是系统最关键模块，建议提供如下接口：

```swift
func move(
    item: MenuBarItem,
    to destination: MoveDestination,
    on displayID: CGDirectDisplayID?,
    skipInputPause: Bool,
    maxAttempts: Int
) async throws
```

`MoveDestination` 只需要两类：

- `leftOfItem(anchor)`
- `rightOfItem(anchor)`

执行要点：

- 串行化所有合成事件，避免多个拖拽同时发生。
- 操作前等待用户输入暂停，避免与真实鼠标操作冲突。
- 停止全局 HID 监听，防止自己生成的事件触发业务逻辑。
- 记录鼠标位置，隐藏光标，操作结束后恢复。
- 对每个移动动作执行多次尝试，默认 6 到 8 次。
- 每次发送 mouse-down 后等待 item bounds 变化，再发送 mouse-up。
- 用最终相对位置校验是否到达目标。
- 记录每个图标的自适应超时时间，慢响应应用给更长窗口。

合成事件需要设置：

- Command 修饰键。
- 窗口 ID 字段。
- 鼠标事件目标窗口字段。
- 唯一 userData，便于事件响应匹配。
- 必要时定向 post 到目标 PID。

## 隐藏与展示流程

隐藏某区：

1. 把对应控制项状态设为 `hideSection`。
2. 控制项长度扩展到大宽度，按钮透明并禁用交互。
3. 必要时添加额外 spacer status items，覆盖超宽显示器。
4. 重新扫描菜单栏项，更新缓存。
5. 保存当前分区顺序。

展示某区：

1. 控制项状态设为 `showSection`。
2. 控制项恢复普通宽度或最小分隔宽度。
3. 隐藏区图标回到可见范围。
4. 根据触发方式决定是否自动重隐藏。

临时展示单个图标：

1. 获取该图标原始分区和邻居锚点。
2. 持久化 pending relocation，防止应用在展示期间退出后位置丢失。
3. 把图标移动到主控制项左侧或当前可点击锚点附近。
4. 等待位置稳定后执行点击。
5. 捕获新出现的菜单/弹窗窗口，作为是否可重隐藏的判断依据。
6. 启动重隐藏计时器。

重隐藏：

1. 若弹窗仍显示，延迟重隐藏。
2. 若用户刚输入，延迟重隐藏。
3. 用记录的原始邻居锚点恢复位置。
4. 原邻居不存在时用备用邻居。
5. 仍不存在时回退到原始分区控制项。
6. 成功后删除 pending relocation。
7. 多次失败后写入 `waitForRelaunch:<windowID>:<section>`，本会话暂停重试，待应用重启产生新 windowID 后恢复。

## 缓存与布局协调

菜单栏项管理器应维护一个 `ItemCache`：

- 当前 display ID。
- 每个分区的有序图标列表。
- 当前窗口 ID 快照。
- tag 到分区和索引的反查表。

缓存刷新触发源：

- 应用启动和权限恢复。
- 窗口 ID 列表变化。
- 前台应用变化。
- 用户拖拽结束。
- 显示器/空间变化。
- 隐藏区状态变化。
- 临时展示/重隐藏结束。

启动阶段需要 settling period，避免登录项集中出现时不断保存半成品布局。该阶段只扫描和补充已知身份，不自动保存、不恢复。settling 结束后执行一次最终恢复。

## 布局求解

建议把纯算法和系统操作分离：

- `LayoutSolver`：纯函数，输入当前快照和期望布局，输出下一步移动计划。
- `LayoutReconciler`：把用户配置、已保存顺序、控制项 UID 和当前图标组合成可执行计划。
- `ItemManager`：负责调用 Window Server、执行移动、更新持久化。

期望布局可表示为：

```text
sectionOrder: [section: [itemUID]]
newItemsPlacement: section / anchor / relation
pinnedHiddenBundleIDs
pinnedAlwaysHiddenBundleIDs
```

重排时可用最长公共子序列策略减少移动次数。对缺失应用保留其已保存槽位，应用重新出现后插回原位。对未保存的新图标按用户偏好放入默认分区或锚点旁边。

## 持久化设计

建议使用 UserDefaults 或独立配置文件保存以下状态，键名应使用自有命名空间：

```text
ItemManager.knownItemIdentifiers: [String]
ItemManager.savedSectionOrder: [String: [String]]
ItemManager.pendingRelocations: [String: String]
ItemManager.pendingReturnDestinations: [String: [String: String]]
ItemManager.pinnedHiddenBundleIDs: [String]
ItemManager.pinnedAlwaysHiddenBundleIDs: [String]
Settings.newItemsSection: String
Settings.newItemsPlacement: Data
Settings.autoRehide: Bool
Settings.rehideInterval: Double
Settings.enableAlwaysHiddenSection: Bool
```

保存分区顺序时要过滤：

- 无 sourcePID 的未稳定图标。
- 临时系统图标和动态占位项。
- 隐藏/深度隐藏控制项。
- 正在临时展示、但真实分区由 pending relocation 记录的图标。

可见区主控制项可以持久化，因为其相对位置影响重排恢复。

## 多显示器与刘海屏

所有移动和点击都必须解析到正确 display ID：

- 优先使用图标 bounds 所在显示器。
- 其次使用鼠标所在显示器。
- 最后使用当前拥有菜单栏的显示器。

隐藏图标通常会被推到屏幕外，但仍保持菜单栏 Y 坐标。按显示器过滤时不能只判断是否与显示器 bounds 相交，应允许 X 离屏并用 Y 范围归属显示器。

刘海屏需要额外布局预算：

- 计算应用菜单右边缘到系统状态区左边缘的可用宽度。
- 扣除刘海区域及左右安全间距。
- 可见区超出预算时，把优先级低的图标溢出到隐藏区。
- 合成拖拽到离屏目标时，避免把鼠标 warp 到屏幕边缘导致误触系统菜单；可把 mouse-down hit test 点重定向到刘海不可点击区域，mouse-up 仍使用真实投放坐标。

## 事件触发

HID 事件管理器建议监听：

- leftMouseDown：点击菜单栏空白或控制项时展示隐藏区。
- rightMouseDown：打开二级菜单或上下文操作。
- leftMouseDragged：检测用户正在 Command 拖拽菜单栏项。
- leftMouseUp：拖拽结束后刷新缓存和保存顺序。
- mouseMoved：悬停展示、tooltip、显示器切换检测。
- scrollWheel：滚动展示隐藏项。
- frontmostApplication：智能重隐藏。

监听器应支持 `stopAll/startAll` 计数，合成事件期间暂停业务监听，结束后恢复。

## 异常恢复

需要处理以下系统边界：

- 图标移动后停在 `x == -1`：视为 blocked，尝试移回可见区。
- 目标应用已退出：跳过事件发送，保留 pending relocation。
- 事件 tap 失效：健康检查并重建。
- 控制项缺失：清空当前缓存，短延迟重试。
- 菜单栏项窗口列表临时为空：重试一次，不要立即覆盖缓存。
- sourcePID 未解析：暂缓持久化和新图标重定位。
- 用户正在拖拽：跳过自动缓存和恢复，等 mouse-up 后处理。
- 重隐藏连续失败：写入 wait-for-relaunch sentinel，避免无限占用事件串行器。

## 建议模块划分

```text
AppState
  PermissionsManager
  SettingsStore
  MenuBarCoordinator
    ControlItemController
    ItemDiscoveryService
    SourceProcessResolver
    ItemCache
    LayoutSolver
    LayoutReconciler
    MoveEventExecutor
    TemporaryRevealController
    PersistentRecoveryController
  HIDEventManager
  DisplayManager
  DiagnosticsLogger
```

其中 `ItemDiscoveryService` 只负责采集窗口和 AX 数据，`MoveEventExecutor` 只负责移动和点击事件，`LayoutSolver` 保持纯函数。这样可以用单元测试覆盖布局算法，用集成测试覆盖真实菜单栏操作。

## 测试重点

单元测试：

- tag 稳定性和 instanceIndex 分配。
- 分区顺序保存与缺失应用槽位保留。
- 新图标默认落位和锚点落位。
- pending relocation 的 wait-for-relaunch 状态机。
- 刘海屏溢出策略。
- LCS 重排计划。
- 不可隐藏/不可移动系统项过滤。

集成测试：

- 启动后 settling 结束能恢复布局。
- 临时展示后能按原邻居重隐藏。
- 图标所在应用退出后重启能恢复原分区。
- 多显示器菜单栏切换后仍点击正确图标。
- 用户 Command 拖拽期间不会被自动恢复逻辑打断。

## 开发里程碑

1. 实现权限、控制项创建、菜单栏窗口扫描。
2. 建立 `MenuBarItem`、tag、sourcePID 解析和缓存。
3. 实现基础移动执行器和相对位置校验。
4. 实现 visible/hidden 两分区隐藏与展示。
5. 增加分区顺序保存和启动恢复。
6. 增加临时展示、点击和自动重隐藏。
7. 增加深度隐藏分区。
8. 增加多显示器、刘海屏和溢出策略。
9. 增加异常恢复、诊断日志和布局重置工具。

## Apple 文档参考

- App Sandbox 是 Mac App Store 提交的基础要求：`https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/`
- App Store Connect 对临时例外 entitlement 需要填写 App Sandbox information：`https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information`
- Temporary exception entitlement 的用途与说明要求：`https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html`
- ScreenCaptureKit 首次使用会触发屏幕录制授权：`https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos`
- App Review Guidelines 是动态文档，涉及隐私、用户数据和 entitlement 误用风险：`https://developer.apple.com/app-store/review/guidelines/`

## 细化开发文档

后续实施请以 `docs/menubar-hidden-dev/` 下的分阶段开发规格为准：

- `README.md`：文档导航、双版本路线和实施原则。
- `00-roadmap.md`：P0 到 P5 阶段路线、交付物和验收条件。
- `01-permissions-and-distribution.md`：权限、发布、沙盒和审核说明。
- `02-core-engine-spec.md`：核心模型、发现、source PID、缓存和布局求解。
- `03-hide-and-move-executor.md`：具体隐藏机制和合成拖拽执行器。
- `04-persistence-and-recovery.md`：持久化、启动恢复和异常恢复。
- `05-ui-and-interactions.md`：界面、交互和无截图权限降级。
- `06-testing-and-acceptance.md`：测试矩阵、手工验收和诊断日志。

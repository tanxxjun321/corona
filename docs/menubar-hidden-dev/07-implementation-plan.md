# 工程实施规划

## 当前工程决策

- 语言与 UI：Swift 5.9+，AppKit 负责菜单栏生命周期，SwiftUI 负责设置和权限窗口。
- 最低系统版本：macOS 13。后续如果 ScreenCaptureKit 或新版 System Settings 跳转需要更高版本，再按功能做可用性判断。
- 仓库结构：Swift Package 只保留 `CoronaCore` 核心库和测试；Xcode 原生 `CoronaApp` 是唯一可运行 app target。
- 模块边界：
  - `CoronaCore`：权限模型、设置模型、菜单栏 item 模型、布局纯函数、持久化 schema。
  - `CoronaApp`：`NSApplication` 生命周期、`NSStatusItem`、设置窗口、系统权限跳转、provider/executor 装配。
  - `CoronaCoreTests`：不依赖系统 UI 的单元测试。
- 版本差异：使用 `DistributionChannel` 表达 `appStore` 和 `direct`，provider capability 由运行时对象声明，不在业务层判断私有 API。
- P0 阶段不实现 Window Server 扫描和合成拖拽，只建立权限门禁、UI 外壳、设置持久化和后续装配点。

## 分阶段开发顺序

## 当前实现状态

截至 2026-06-07，工程已经从控制台程序推进为可打包的菜单栏 app：

- 已完成菜单栏 app 外壳、权限状态、设置窗口、扫描窗口、布局编辑器、隐藏项面板。
- 已完成菜单栏项模型、稳定身份、缓存控制器、公开 API fallback 扫描、分区分类和布局持久化。
- 已完成 hidden/always-hidden 控制项、隐藏区 show/hide、宽屏 spacer、基于控制项 bounds 的当前布局分类。
- 已完成保存布局的应用编排、菜单手动应用、启动后自动恢复、Hidden Panel 单项 reveal。
- 已接入 direct 版 `Command + drag` 合成事件执行器；当前实现可执行移动，但仍缺少完整的输入暂停、光标恢复、bounds 轮询校验和复杂失败清理。
- 已通过 SwiftPM 单元测试和 Xcode app 打包验证；真实菜单栏移动仍需要手工验收。

剩余正式化工作：

- 强化 `DirectMoveEventExecutor`：事件串行化、用户输入暂停检测、光标保存/恢复、最终相对位置校验。
- 完成临时 reveal 后的自动重隐藏、pending return destination 和 click executor。
- 补多显示器、刘海屏、blocked item 恢复和诊断导出。
- 补 Screen Recording 缩略图增强和发布签名/notarization 配置。

### P0：菜单栏外壳与权限门禁

目标：应用能作为菜单栏工具启动，显示主状态项、设置入口、权限状态和诊断开关。

开发步骤：

1. 创建 Swift Package 核心库、Xcode app target 和测试 target。
2. 实现 `PermissionStatus`、`PermissionSnapshot`、`PermissionChecking`。
3. 在 app 层实现 Accessibility 和 Screen Recording 检测。
4. 实现 `AppSettings` 与 `UserDefaultsSettingsStore`。
5. 创建 `MenuBarController`：主图标、状态菜单、设置窗口入口、退出入口。
6. 创建 `SettingsWindowController` 和 SwiftUI 设置/权限视图。
7. 单元测试权限聚合逻辑和设置默认值。

验收：

- `swift test` 通过。
- Xcode 运行 `CoronaApp` 能启动菜单栏 app。
- 无 Accessibility 时菜单和设置页清楚显示核心功能不可用。
- Screen Recording 缺失只显示增强功能未启用，不阻塞设置页。

### P1：模型、发现 provider 协议与 mock 快照

目标：建立菜单栏项模型和 cache 流水线，先用 mock provider 验证身份、分区和持久化规则。

开发步骤：

1. 实现 `MenuBarItemTag`、`MenuBarItem`、`ItemCache`。
2. 定义 `MenuBarDiscoveryProvider` 与 capability。
3. 实现 mock provider 和公开 API fallback provider 骨架。
4. 实现 source PID resolver 协议，不在 P1 绑定私有 API。
5. 实现稳定 UID、同名 instanceIndex 分配和不稳定 item 过滤。
6. 增加 P1 单元测试。

### P2：控制项与分区显示

目标：创建 hidden/alwaysHidden 控制项，完成 show/hide 状态切换和分区判定。

开发步骤：

1. 实现 `StatusSectionController` 管理 visible、hidden、alwaysHidden 和 spacer。
2. 实现 `SectionClassifier` 纯函数。
3. 在主菜单中接入隐藏区展示/隐藏开关。
4. 在 UI 中展示 mock/真实快照的 hidden 面板。
5. 增加 spacer 行为和分区判定测试。

### P3：移动执行器与布局恢复

目标：接入真实移动能力和保存顺序恢复。

开发步骤：

1. 实现 `MoveDestination`、`MoveEventExecutor` 协议和 direct 版实现。
2. 加入事件串行器、输入暂停检测和失败清理。
3. 实现 `LayoutPlanner` 纯函数和保存/恢复 orchestration。
4. 增加 move 错误、重试和布局恢复诊断日志。
5. 增加布局规划单元测试和手工验收脚本。

### P4：临时展示与自动重隐藏

目标：隐藏项可临时展示、点击并自动回到原分区。

开发步骤：

1. 实现 `TemporaryRevealController`。
2. 实现 return destination 捕获与 pending relocation。
3. 实现 click executor。
4. 实现 smart/timer/appSwitch 自动重隐藏策略。
5. 增加 pending 和重隐藏测试。

### P5：硬化、缩略图和发布

目标：覆盖多显示器、刘海屏、真实缩略图、诊断导出和发布配置。

开发步骤：

1. 完成 direct 版 Window Server provider。
2. 完成 App Store fallback provider 与 capability 降级 UI。
3. 接入 Screen Recording 缩略图 provider。
4. 补 Xcode app target、Info.plist、entitlements、notarization/App Store 配置。
5. 完成测试矩阵和手工验收。

## 代码质量约束

- provider/executor 之外不直接调用系统 API。
- 布局、分区、持久化迁移必须是纯函数或可注入依赖。
- 没有 Accessibility 时不启动 discovery、move、click、rehide 主链路。
- 文案和 UI 状态必须明确区分“核心不可用”和“增强预览不可用”。
- 每阶段都保持可编译、可测试；复杂系统能力先以协议和 mock 骨架接入。

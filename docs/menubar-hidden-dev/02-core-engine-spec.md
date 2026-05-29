# 核心引擎规格

## 模块边界

核心引擎分为三层：

- Discovery：采集菜单栏窗口、AX 元素、进程信息和显示器信息。
- Model/Cache：把实时窗口快照转换为稳定 `MenuBarItem` 和分区缓存。
- Layout：根据期望布局和当前布局生成移动计划，不直接调用系统 API。

系统 API 调用只允许出现在 provider/executor 层。布局求解器必须是纯函数，便于单元测试。

## 数据模型

`MenuBarItem`：

- `tag: MenuBarItemTag`
- `windowID: CGWindowID`
- `ownerPID: pid_t`
- `sourcePID: pid_t?`
- `bounds: CGRect`
- `title: String?`
- `isOnScreen: Bool`
- `isMovable: Bool`
- `canBeHidden: Bool`

`MenuBarItemTag`：

- `namespace`: bundle id、进程名、系统 namespace 或 null。
- `title`: 状态项窗口标题。
- `instanceIndex`: 同 namespace/title 多实例索引。
- `windowID`: 只用于本轮 disambiguation，不进入长期 UID。

长期 UID：

```text
namespace:title
namespace:title:instanceIndex
```

禁止使用 `windowID` 作为持久化身份，因为应用重启、系统重排和权限恢复都会改变窗口 ID。

## 窗口发现

官网完整版 provider 需要返回：

- 菜单栏项窗口 ID 列表。
- 每个窗口的 bounds、ownerPID、layer、title、ownerName、isOnScreen。
- 当前 active menu bar display。
- 窗口当前 space 和显示器归属。

App Store provider 返回能力较少时，必须显式标记 capability，例如：

```text
canEnumerateOffscreenMenuBarItems = false
canReadActiveMenuBarDisplay = limited
canCaptureStatusItemPixels = false
```

上层根据 capability 决定显示完整功能、降级功能或权限/版本提示。

## source PID 解析

解析流程：

1. 取当前菜单栏项窗口快照。
2. 遍历运行中应用。
3. 读取每个应用的 AX `extrasMenuBar`。
4. 遍历 children，取 enabled 且有 frame 的元素。
5. 用 child frame 与窗口 bounds 做空间匹配。
6. 批量写入 `windowID -> sourcePID` 缓存。

规则：

- 一轮扫描只允许一个批量解析任务在跑，避免 AX 并发放大。
- 若 sourcePID 未解析，item 可以进入临时 UI，但不能写入 `savedSectionOrder`。
- 同 title 多实例必须在 sourcePID 稳定后再分配长期 `instanceIndex`。

## 分区判定

分区控制项：

- visible control：可见区主入口。
- hidden control：隐藏区边界。
- always-hidden control：深度隐藏区边界，可选。

分区规则：

- visible：位于 hidden control 右侧。
- hidden：位于 hidden control 左侧，且位于 always-hidden control 右侧。
- alwaysHidden：位于 always-hidden control 左侧。

多显示器场景下，隐藏图标可能 X 离屏但 Y 仍在菜单栏范围内。显示器归属不能只用 intersects，应允许按 Y 范围判断。

## ItemCache

缓存内容：

- `displayID`
- `visibleItems`
- `hiddenItems`
- `alwaysHiddenItems`
- `windowIDs`
- `addressByTag`
- `sectionByWindowID`

刷新触发：

- 启动和权限恢复。
- 菜单栏窗口 ID 变化。
- 用户拖拽结束。
- 控制项 show/hide 状态变化。
- 前台应用变化。
- 显示器或 active menu bar display 变化。
- 临时展示或重隐藏完成。

刷新保护：

- 用户正在拖拽时跳过自动恢复。
- sourcePID 未稳定时跳过持久化。
- 启动 settling 期间只采集，不恢复、不保存。
- 最近刚发生 move 时延迟刷新，避免读到中间状态。

## 布局求解

输入：

- 当前 flat UID 序列。
- 期望 sectionOrder。
- control item UID。
- 当前分区映射。
- 新图标放置策略。

输出：

- 下一步移动项 UID。
- 抽象目标：leftOfUID、rightOfUID、sectionBoundary。

执行前由 orchestrator 用最新缓存把抽象目标解析为实时 `MoveDestination`。如果锚点消失，回退到分区边界。

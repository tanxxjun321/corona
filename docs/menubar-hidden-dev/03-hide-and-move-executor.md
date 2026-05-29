# 隐藏机制与移动执行器规格

## 控制项隐藏机制

隐藏不是调用系统 hidden flag，而是改变菜单栏物理布局。

控制项状态：

```text
showSection:
  statusItem.length = NSStatusItem.variableLength 或窄分隔宽度
  button.enabled = true
  button.alpha = 1

hideSection:
  statusItem.length = 10000
  button.enabled = false
  button.alpha = 0
```

当 hidden control item 进入 `hideSection`，位于其左侧的图标会被挤出可见菜单栏区域。always-hidden control item 同理。

宽屏处理：

- 如果单个大宽度控制项不足以覆盖当前显示器宽度，添加 spacer status items。
- spacer 不显示图像、不响应点击，只提供额外长度。
- 切回 showSection 时移除或压缩 spacer。

## MoveDestination

只支持两种目标：

```swift
enum MoveDestination {
    case leftOfItem(MenuBarItem)
    case rightOfItem(MenuBarItem)
}
```

目标点：

- `leftOfItem(anchor)`: 使用 `anchor.bounds.minX`。
- `rightOfItem(anchor)`: 使用 `anchor.bounds.maxX`。
- Y 使用 anchor 菜单栏窗口的菜单栏 Y 坐标。

## 移动执行流程

接口：

```swift
func move(
    item: MenuBarItem,
    to destination: MoveDestination,
    on displayID: CGDirectDisplayID?,
    skipInputPause: Bool,
    maxAttempts: Int
) async throws
```

执行步骤：

1. 校验 item 可移动。
2. 解析 displayID：显式参数、item bounds 所在显示器、鼠标显示器、active menu bar display。
3. 如果 `skipInputPause == false`，等待用户鼠标/滚轮输入暂停。
4. 暂停业务 HID event monitors。
5. 获取 item 当前 bounds 和目标 anchor bounds。
6. 保存当前鼠标位置，隐藏光标。
7. 串行化事件发送，确保同一时间只有一个 move/click 操作。
8. 发送 Command + mouseDown。
9. 等待 item origin 变化。
10. 发送 mouseUp，重复 2 次。
11. 等待 item origin 再次变化。
12. 校验最终相对位置。
13. 恢复鼠标位置、光标和 HID monitors。

## CGEvent 字段

mouseDown：

```text
type = leftMouseDown
flags = maskCommand
button = left
location = target insertion point
mouseEventWindowUnderMousePointer = item.windowID
mouseEventWindowUnderMousePointerThatCanHandleThisEvent = item.windowID
windowID = item.windowID
eventTargetUnixProcessID = sourcePID ?? ownerPID
```

mouseUp：

```text
type = leftMouseUp
flags = []
button = left
location = target insertion point
mouseEventWindowUnderMousePointer = destination.targetItem.windowID
mouseEventWindowUnderMousePointerThatCanHandleThisEvent = destination.targetItem.windowID
eventTargetUnixProcessID = sourcePID ?? ownerPID
```

事件源：

- 使用 `.hidSystemState` 创建鼠标事件。
- 使用 `.combinedSessionState` 设置 local event suppression 为 permit all。

## 响应确认

事件发送成功不代表移动成功。必须使用 Window Server 实时 bounds 确认：

```text
leftOfItem:  item.bounds.maxX == anchor.bounds.minX
rightOfItem: item.bounds.minX == anchor.bounds.maxX
```

每次 mouseDown/mouseUp 后轮询 item bounds：

- poll interval：10 到 15 ms。
- 默认单次响应超时：100 到 500 ms，按 item 自适应。
- 最大尝试次数：默认 8。

## 失败处理

- item 不可移动：直接返回 `itemNotMovable`。
- source/owner PID 已退出：跳过事件发送，返回可恢复错误。
- 目标 anchor 消失：调用方重新刷新缓存并解析目标。
- 合成事件超时：发送额外 mouseUp 清理状态后重试。
- item 进入 `x == -1`：仅允许向 visible control 右侧恢复。
- 目标点离屏：不 warp 光标到离屏点，避免误触系统菜单。
- 刘海屏离屏投放：mouseDown hit test 可重定向到刘海不可点击区域，mouseUp 保持真实投放坐标。

## 点击执行器

临时展示后点击使用独立 click executor：

- 支持 left/right/other mouse button。
- 点击前重新读取 item bounds。
- 点击失败时刷新缓存并尝试一次 fallback click。
- 点击后记录新出现的 popup/menu window，用于重隐藏前判断菜单是否仍打开。

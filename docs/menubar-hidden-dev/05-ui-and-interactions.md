# UI 与交互规格

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

## 隐藏区面板

隐藏区面板展示 hidden 或 alwaysHidden 分区。

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

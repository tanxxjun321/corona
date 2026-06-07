# 测试与验收规格

## 单元测试

模型：

- `MenuBarItemTag` 对 system item 忽略 volatile windowID。
- 非 system item 必要时使用 windowID disambiguation。
- `uniqueIdentifier` 不包含 windowID。
- 同 namespace/title 多实例按稳定顺序分配 instanceIndex。

布局：

- 当前分区和 savedSectionOrder 合并时保留已退出应用槽位。
- 新图标按默认分区落位。
- 新图标按锚点 left/right 落位。
- alwaysHidden 禁用时，新图标 fallback 到 hidden。
- LCS 计划减少无意义移动。

pending：

- pending relocation 普通 section 值解析。
- wait-for-relaunch 同 windowID 跳过。
- wait-for-relaunch 新 windowID 后恢复。
- pending return destination 主邻居、备用邻居、分区边界 fallback。
- saved layout 前优先处理 pending relocation。

权限：

- 无 Accessibility 时核心 executor 不启动。
- 无 Screen Recording 时 image provider 返回 bundle icon/占位图。
- 有 Screen Recording 且开启预览时，隐藏列表和扫描列表显示真实缩略图。

## 集成测试

P1：

- 启动后能列出当前菜单栏项。
- sourcePID 批量解析不会并发爆炸。
- 权限恢复后重新 cache。

P2：

- hidden control show/hide 切换能改变隐藏区可见性。
- 控制项视觉隐藏时仍可用于 bounds 分区。
- spacer 在宽屏下被创建并清理。

P3：

- 可移动第三方状态项能移动到 hidden。
- 不可移动系统项被跳过。
- move 失败后光标位置恢复。
- move 失败后 HID monitors 恢复。
- move 后刷新 cache 并校验 left/right 最终相对位置。

P4：

- 临时展示隐藏项后按 timer 自动重隐藏。
- 应用退出后 pending relocation 保留。
- 应用重启后图标回到原分区。

P5：

- 外接显示器上使用正确 displayID。
- active menu bar display 切换后控制项状态刷新。
- 刘海屏离屏投放不误触系统菜单。
- Screen Recording 权限撤销后 UI 降级。

## 手工验收清单

权限：

- 首次启动无 Accessibility。
- 授予 Accessibility 后扫描可用。
- 撤销 Accessibility 后禁用隐藏/移动。
- 无 Screen Recording 时 Hidden Panel 和 Scan Results 使用 fallback 图标/文字。
- 授予 Screen Recording 且开启预览后，Hidden Panel 和 Scan Results 显示真实缩略图。
- 撤销 Screen Recording 后，刷新列表自动降级为 fallback。

布局：

- 用户手动 Command 拖拽菜单栏项后，应用刷新并保存新顺序。
- 应用重启后恢复 visible/hidden 顺序。
- 新安装应用菜单栏项按设置进入 hidden。
- 保存布局后重启，先恢复 pending relocation，再应用 saved layout。

恢复：

- Hidden Panel Reveal 后按 timer 回到隐藏区。
- 临时展示期间退出源应用，重启后恢复原分区。
- 连续失败后不会无限重试。
- 移动失败不会卡住拖拽或鼠标。

多显示器：

- 主屏/副屏都能点击正确隐藏项。
- 断开显示器后不会保存错误布局。
- 刘海屏和非刘海屏切换后布局可恢复。

## 诊断日志

必须记录：

- 权限状态变化。
- cache 开始/结束、item 数量、displayID。
- sourcePID 解析失败数量。
- move 开始/目标/尝试次数/最终结果。
- pending relocation 写入、清除和 sentinel。
- 控制项缺失、窗口列表为空、blocked item 恢复。

日志不得记录：

- 用户键盘输入内容。
- 屏幕截图原始数据。
- 菜单内容文本，除非用户主动导出诊断并确认。

## 发布验收

App Store 版：

- sandbox entitlements 最小化。
- 无私有 API 符号作为核心路径。
- 权限说明和审核说明完整。
- 无 Accessibility 时功能降级清晰。

官网完整版：

- notarization 通过。
- 首次启动权限引导完整。
- 完整隐藏/移动/恢复链路通过手工验收。
- 诊断导出可用于定位权限、窗口扫描和 move 失败。
- `make release` 完成 clean、test、release build、Developer ID signing、zip、notarization、staple 和 verify。
- `codesign --verify --deep --strict` 通过。
- `spctl --assess --type execute` 通过。

# 菜单栏隐藏工具开发规格索引

本目录是基于上层架构文档拆出的可实施开发规格。目标是让后续工程实现按阶段推进：先跑通权限、发现、分区和基础隐藏，再逐步加入移动恢复、临时展示、多显示器、真实缩略图和完整测试。

## 版本路线

采用双版本策略：

- App Store 版：优先公开 API、App Sandbox 和可审核降级体验。没有私有 Window Server/SkyLight 能力时，核心隐藏能力可能只能做有限实现或引导用户使用官网完整版。
- 官网完整版：Developer ID 签名并 notarize，保留完整菜单栏窗口扫描、离屏 bounds、合成拖拽、恢复和真实像素缩略图能力。

权限口径：

- Accessibility 是核心必需权限。没有它，只能做菜单栏外壳、设置、权限引导、bundle icon 列表等降级功能。
- Screen Recording 是可选增强权限。没有它，隐藏和移动仍可做；不能展示真实菜单栏项像素缩略图，只能展示 bundle icon、文字、占位图或用户自定义图标。

## 文档列表

- [00-roadmap.md](00-roadmap.md)：阶段路线、每阶段交付物和验收条件。
- [01-permissions-and-distribution.md](01-permissions-and-distribution.md)：权限、沙盒、双版本、审核说明。
- [02-core-engine-spec.md](02-core-engine-spec.md)：菜单栏项模型、发现、source PID、缓存和分区。
- [03-hide-and-move-executor.md](03-hide-and-move-executor.md)：隐藏机制、控制项、合成拖拽移动执行器。
- [04-persistence-and-recovery.md](04-persistence-and-recovery.md)：持久化、启动 settling、pending relocation 和异常恢复。
- [05-ui-and-interactions.md](05-ui-and-interactions.md)：用户界面、交互、无截图权限降级。
- [06-testing-and-acceptance.md](06-testing-and-acceptance.md)：测试矩阵、手工验收、诊断日志。

## 实施原则

- 先实现可验证的最小链路，再扩展复杂场景。
- 布局求解保持纯函数，系统 API 调用集中在 provider/executor 层。
- 不以 `windowID` 作为长期身份；长期身份使用 `namespace:title[:instanceIndex]`。
- 所有自动移动都必须能被用户触发路径解释，避免后台无感改变用户菜单栏。
- App Store 版和官网完整版共享 UI、设置、模型、布局求解器；差异集中在窗口扫描 provider、截图 provider 和移动 executor 能力。

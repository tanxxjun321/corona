# 权限与发布规格

## 权限决策

| 权限/能力 | 核心必需 | 使用场景 | 无权限降级 |
| --- | --- | --- | --- |
| Accessibility | 是 | 读取 AX extras menu bar、识别第三方菜单栏项、合成/监听输入、移动图标 | 禁用隐藏、移动、临时展示，仅保留设置、权限引导、bundle icon 列表 |
| Screen Recording | 否 | 真实菜单栏项截图缩略图、菜单栏背景取色、真实图标搜索预览 | 使用应用 bundle icon、文字、占位图或用户自定义图标 |
| App Sandbox | App Store 必需 | Mac App Store 提交 | 官网版仍建议保持最小权限，但可按能力放宽 |
| Network Client | 否 | 更新、账户、远程配置、诊断上传 | 不启用网络功能 |
| Apple Events | 否 | 仅在未来加入跨 app 自动化时需要 | 当前架构不申请 |

Accessibility 是产品核心门槛。没有它，不能承诺第三方菜单栏项隐藏、移动、自动重隐藏或真实布局恢复。

Screen Recording 只用于读取像素。隐藏区列表本身不需要它；真实像素缩略图需要它。

## 官网发布命令

环境变量：

```bash
export SIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)"
export NOTARY_PROFILE="corona-notary"
```

发布：

```bash
make release
```

单步调试：

```bash
CONFIGURATION=Release bash scripts/build-app.sh
bash scripts/notarize-app.sh
make verify
```

产物：

- `.build/app/Corona.app`
- `.build/dist/Corona-release.zip`

## 双版本策略

App Store 版：

- 启用 App Sandbox。
- 不把私有 Window Server/SkyLight 符号作为能力基础。
- 隐藏能力以公开 API 可实现范围为准，必要时提供“完整版可用”的说明入口。
- 权限文案强调用户显式操作、只处理菜单栏区域、不上传截图。

官网完整版：

- Developer ID 签名并 notarize。
- 保留完整窗口扫描 provider、离屏 bounds、active menu bar display、合成拖拽和截图 provider。
- 仍然只在用户触发路径下移动图标。
- 诊断日志默认不采集敏感内容，用户主动导出。
- 发布机器需要 Apple Developer Program、Developer ID Application 证书和 `notarytool` keychain profile。

共享部分：

- UI、设置、菜单栏项模型、布局求解器、持久化格式和测试用例。
- provider 协议保持一致，版本差异只替换实现。

## Entitlements

App Store 基础 entitlements：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

如存在网络功能：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

不默认申请：

```xml
com.apple.security.automation.apple-events
com.apple.security.temporary-exception.mach-lookup.global-name
com.apple.security.temporary-exception.files.absolute-path.read-write
```

除非后续功能确实需要，并能在 App Store Connect 的 App Sandbox information 中说明验证方式、必要性、功能入口和具体值。

## 权限提示文案

Accessibility：

```text
需要辅助功能权限来识别和移动菜单栏图标。应用只会在你点击、拖拽或使用快捷键触发时执行与菜单栏相关的操作。
```

Screen Recording：

```text
屏幕录制权限仅用于在本机生成真实菜单栏图标预览和菜单栏外观取色。没有该权限，隐藏与展示仍可使用，但会显示应用图标或占位图。
```

## 审核说明模板

```text
This app helps users organize their macOS menu bar by moving menu bar items
only after explicit user actions such as clicking the app icon, using a
configured hotkey, or arranging items in the layout editor.

Accessibility permission is required to identify menu bar extras and perform
the same Command-drag operation that users can perform manually.

Screen Recording permission is optional and only used to render local icon
previews and menu bar appearance. Captured images are processed locally and
are not uploaded.
```

## 审核风险

- 私有 Window Server/SkyLight API 不适合提交 App Store 版。
- 全局 event tap 需要严格限制用途，只监听菜单栏相关鼠标事件，不记录文本输入。
- Screen Recording 必须是增强功能，不应阻塞核心隐藏能力。
- 权限缺失时不能静默失败，应提供明确降级 UI。

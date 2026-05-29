# 持久化与恢复规格

## 持久化键

建议使用自有命名空间：

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
Settings.rehideStrategy: Int
Settings.rehideInterval: Double
Settings.enableAlwaysHiddenSection: Bool
```

section key：

```text
visible
hidden
alwaysHidden
```

## savedSectionOrder

含义：每个分区的长期 UID 顺序。

保存规则：

- 保存有稳定 sourcePID 的非控制项。
- visible control 可保存，用于判断主图标相对位置。
- hidden/always-hidden control 不保存，它们是隐式边界。
- 不保存动态系统占位项、临时状态项、未解析 sourcePID 项。
- 对已退出应用保留旧槽位，不因本轮缺失而删除。

写入时机：

- 用户拖拽结束后。
- move 执行并稳定后。
- 布局编辑器显式保存后。
- 启动 settling 结束后的最终缓存稳定后。

禁止写入时机：

- 启动 settling 期间。
- 正在恢复布局期间。
- 正在临时展示或重隐藏期间。
- 有 item 处于 `x == -1` blocked 状态时。

## knownItemIdentifiers

用于识别新出现的菜单栏项。

规则：

- 启动 settling 期间只 seed 已稳定 sourcePID 的 identifier。
- sourcePID 未解析时不写入，避免把系统托管进程 namespace 当作真实身份。
- 新图标首次稳定出现后，按用户的新图标策略移动并写入 known set。

## pendingRelocations

用于恢复临时展示期间未能重隐藏的图标。

普通值：

```text
<tagIdentifier> -> hidden
<tagIdentifier> -> alwaysHidden
```

wait-for-relaunch sentinel：

```text
<tagIdentifier> -> waitForRelaunch:<windowID>:<sectionKey>
```

含义：

- 同一 windowID 下连续重隐藏失败，当前会话不再重试。
- 当应用重启导致 windowID 变化，清除 sentinel 并重新按 sectionKey 恢复。

## pendingReturnDestinations

用于尽量恢复临时展示前的相对顺序。

格式：

```text
<tagIdentifier> -> {
  "neighbor": "<neighborTagIdentifier>",
  "position": "left" | "right"
}
```

恢复优先级：

1. 原始主邻居仍存在：按记录的 left/right 恢复。
2. 备用邻居仍存在：反向恢复以保留相对顺序。
3. 邻居都不存在：恢复到原始分区控制项边界。

## 启动恢复

启动步骤：

1. 加载设置和持久化布局。
2. 创建控制项。
3. 启动初始 fast cache，不强制 sourcePID 全解析。
4. 进入 settling period。
5. settling 期间只采集和 seed，跳过保存和恢复。
6. settling 结束后执行一次完整 cache。
7. 执行 pending relocation。
8. 应用 savedSectionOrder。

settling 默认策略：

- 冷启动固定等待窗口，覆盖登录项集中注册状态项的时间。
- 如果权限刚恢复或 display 配置变化，重新进入短 settling。
- settling 结束前不把半成品布局写入持久化。

## 异常恢复

blocked item：

- 如果 item bounds origin.x == -1，视为 blocked。
- 禁止继续向隐藏区移动。
- 尝试移动到 hidden control 右侧可见区。

控制项缺失：

- 清空本轮 cache。
- 短延迟重试。
- 不覆盖 savedSectionOrder。

窗口列表为空：

- 重试一次。
- 仍为空时保留旧缓存并记录诊断。

重隐藏失败：

- 每轮最多 3 次即时重试。
- 总失败达到上限后写入 wait-for-relaunch sentinel。
- 保留 pending relocation，避免图标永久留在 visible 区。

## 配置迁移

迁移策略：

- 新 key 使用默认值可缺省读取。
- 旧 section key 只在迁移层转换一次。
- 迁移失败不删除旧数据，先写诊断并回退到默认布局。
- 对用户布局类数据提供导出入口，便于诊断。

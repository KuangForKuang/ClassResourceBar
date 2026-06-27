# Tasks: ClassResourceBar

> 实现顺序按 Phase 推进，每个 Phase 完成后做一次自测，再进入下一个 Phase。
> Phase 1–2 可在游戏外用纯 Lua 自测；Phase 3+ 需要进游戏验证。

## Phase 1 — 骨架与数据库 (基础)

### [1.1] 创建 TOC 与目录骨架
- [x] [1.1.1] 创建 `ClassResourceBar.toc`：`## Interface: 120007`、`## Title: ClassResourceBar`、`## Notes`、`## Author`、`## Version`、`## SavedVariables: ClassResourceBarDB`，按 design.md §目录结构 列出所有 .lua 文件
- [x] [1.1.2] 创建空文件占位：`Init.lua`、`Core.lua`、`PowerDB.lua`、`Bar.lua`、`BarPool.lua`、`Layout.lua`、`Alert.lua`、`MemoryManager.lua`、`Config.lua`、`API.lua`，每个文件头部加 `local addonName, ns = ...` 与命名空间声明
- [x] [1.1.3] 在 TOC 内确认加载顺序：Init → PowerDB → Bar → BarPool → Alert → Layout → MemoryManager → API → Config → Core

**验证**：游戏内 `/dl ClassResourceBar`（或 `/reload`）能加载，无 Lua 错误（用 BugSack 监控）。⏳ 待游戏内验证

### [1.2] PowerDB.lua — 职业/专精 → PowerType 映射表
- [x] [1.2.1] 实现 `PowerDB.Get(classFile, specID)` 返回 `{ primary = pt, secondary = pt|nil, runeType = "blood"|"frost"|"unholy"|nil }`
- [x] [1.2.2] 写入 design.md §资源映射 表中全部 13 职业 / 22 spec 条目（注意 DK 的 `RuneBlood/Frost/Unholy` 是 20/21/22，不是旧的 `Runes=5`）
- [x] [1.2.3] 提供 `PowerDB.Detect()` —— 调用 `UnitClass("player")` + `GetSpecialization()` + `GetSpecializationInfo()` 自动返回当前资源信息

**验证**：纯 Lua 单测，输入 `("WARRIOR", 1)` 返回 `primary=1(Rage)`；输入 `("DEATHKNIGHT", any)` 返回 `runeType` 字段非 nil。

### [1.3] Init.lua — SavedVariables 初始化
- [x] [1.3.1] 定义 `ClassResourceBarDB` 默认结构（profile + global，见 design.md）
- [x] [1.3.2] 监听 `ADDON_LOADED`，addonName 匹配时合并默认值（不覆盖用户已有键）
- [x] [1.3.3] 提供 `Init.GetProfile()` 返回当前角色 profile 引用
- [x] [1.3.4] 在 `PLAYER_LOGIN` 之前**不**访问任何 API（遵守 cheat-sheet Mistake 10）

**验证**：首次安装时 DB 中所有字段都有默认值；已有 DB 不会丢字段。

---

## Phase 2 — Bar 对象池与单条 Bar (核心 UI)

### [2.1] Bar.lua — 单条资源条
- [x] [2.1.1] `Bar.Create(pool, kind)` 工厂函数：创建一个 Frame，内部含 `StatusBar`（主体）+ 4 个固定 Texture（bg、border、alertOverlay、pulseGlow）+ 1 个 FontString（数值）
- [x] [2.1.2] 一次性创建 `AnimationGroup` + `Alpha`（脉冲）与 `Alpha`（闪烁），保存为 `bar.anim`，**仅创建一次**，之后只 `:Play()`/`:Stop()`
- [x] [2.1.3] `Bar.SetPower(bar, current, max)`：更新 StatusBar 数值 + FontString，并对 `pct >= threshold` 调用 `Alert.Evaluate`
- [x] [2.1.4] `Bar.SetColor(bar, r, g, b)`：调用 `UnitPowerType` 的返回色或 `PowerDB` 内置颜色表
- [x] [2.1.5] `Bar.Hide(bar)`：`:Hide()` + `:StopAnim()` 但**不**销毁字段

**验证**：游戏内手动 `ClassResourceBar._TestBar()` 把条值从 0→100 推进，视觉正确。⏳ 待游戏内验证

### [2.2] BarPool.lua — 对象池
- [x] [2.2.1] `BarPool.Init()` 在 `Init.lua` 之后调用，预创建 8 个 Bar（最大并发数：DK 主+3 符文组 + 辅 = 8）并放入 `freeList`
- [x] [2.2.2] `BarPool.Acquire(kind)`：从 freeList 弹一个，配置 kind 对应的 size/anchor；若 freeList 空，**复用最少使用的活跃 Bar**（绝不在运行时 `CreateFrame`）
- [x] [2.2.3] `BarPool.Release(bar)`：清理 script、hide、放回 freeList；**不清字段**（下次 Acquire 直接覆盖）
- [x] [2.2.4] `BarPool.Stat()`：返回 `{ live=N, free=N, created=N }`，created 永远应等于 8

**验证**：进游戏后 `/crb mem` 输出 `created=8`，无论切换多少次职业都不增长。⏳ 待游戏内验证

---

## Phase 3 — Core 事件分发与刷新

### [3.1] Core.lua — 事件注册
- [x] [3.1.1] 创建 dispatcher frame，用 design.md §事件选择 表注册：
  - `RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "pet")`
  - `RegisterUnitEvent("UNIT_MAXPOWER", "player", "pet")`
  - `RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")`
  - `RegisterEvent("PLAYER_TALENT_UPDATE")`
  - `RegisterEvent("PLAYER_ENTERING_WORLD")`
  - `RegisterEvent("PLAYER_REGEN_DISABLED")` / `PLAYER_REGEN_ENABLED`
  - `RegisterEvent("RUNE_POWER_UPDATE")`（DK）
- [x] [3.1.2] 用 cheat-sheet 推荐的 **table dispatch** 模式，避免 `if/elseif` 链
- [x] [3.1.3] **绝不**注册 `COMBAT_LOG_EVENT_UNFILTERED`（12.0 已移除，注册会报错）

### [3.2] Dirty-flag 合批刷新
- [x] [3.2.1] handler 内仅置 `Core.dirty[powerType] = true`，不直接更新 UI
- [x] [3.2.2] `C_Timer.NewTicker(0.1, Core.Flush)`：遍历 dirty 表，调用 `Bar.SetPower`，然后 `wipe(Core.dirty)`
- [x] [3.2.3] 在 `Core.Flush` 内对每条 Bar 评估 `Alert.Evaluate`

**验证**：在 60 FPS 战斗场景下，用 `/crb mem` 观察 CPU 时间稳定，无逐帧刷新。⏳ 待游戏内验证

---

## Phase 4 — Alert（将满预警）

### [4.1] Alert.lua — 阈值评估
- [x] [4.1.1] `Alert.SetThreshold(pct)`：0.5–0.99 校验，写入 `profile.threshold`
- [x] [4.1.2] `Alert.Evaluate(bar)`：根据资源类型分支
  - 连续值（Mana/Rage/Energy/...）：`current/max >= threshold` → soft；`current == max` → hard
  - 点数型（ComboPoints/HolyPower/SoulShards/Chi/Essence）：`current >= max - 1` → soft；`current == max` → hard
- [x] [4.1.3] 触发 `bar.anim.pulse:Play()`（soft）或 `bar.anim.flash:Play()`（hard），并按 `profile.sound` 与 `profile.alertStyle` 决定是否 `PlaySound`
- [x] [4.1.4] 当资源回落到阈值以下 → `:Stop()` 动画

### [4.2] 战斗中音效抑制
- [x] [4.2.1] `PLAYER_REGEN_DISABLED` → 设 `inCombat = true`，hard 预警音效改用 `Master` 通道且限频（同种资源 5s 内最多响一次）
- [x] [4.2.2] `PLAYER_REGEN_ENABLED` → 恢复 `SFX` 通道

**验证**：战士怒气 80→100 时分别看到 soft/hard 视觉；连击点 4/5→5/5 时同样触发；战斗中音效不刷屏。⏳ 待游戏内验证

---

## Phase 5 — Layout（按职业/专精排版）

### [5.1] Layout.lua — 资源条布局
- [x] [5.1.1] `Layout.Rebuild()`：调用 `PowerDB.Detect()` 得到 primary/secondary/runeType，从 `BarPool.Acquire` 取条并 `:SetPoint` 到 `profile.point`
- [x] [5.1.2] DK 符文组：6 颗符文按 Blood/Frost/Unholy 排成 3 行 2 列，每颗用 `GetRuneCooldown(i)` 查就绪状态
- [x] [5.1.3] 切换专精触发 `Layout.Rebuild()`：先 `BarPool.Release` 旧条，再 `Acquire` 新条（都从池里来，不新建）
- [x] [5.1.4] 主条字号/纹理按资源类型自动选色（来自 `UnitPowerType` 第 3-5 返回值）

**验证**：在战士/潜行者/死亡骑士/唤魔者之间反复切号，条布局正确切换；`BarPool.Stat().created` 始终为 8。⏳ 待游戏内验证

---

## Phase 6 — MemoryManager 与自检

### [6.1] MemoryManager.lua — 周期采样
- [x] [6.1.1] `C_Timer.NewTicker(60, MemoryManager.Sample)`：每分钟一次
- [x] [6.1.2] `UpdateAddOnMemoryUsage()` + `GetAddOnMemoryUsage("ClassResourceBar")`
- [x] [6.1.3] 写入固定长度 256 的 ring buffer（`ring[idx % 256] = mem`，`idx` 单调递增）
- [x] [6.1.4] `DetectLeak(ring)`：比较最近 5 分钟（5 个样本）的线性回归斜率，若 > 4 KB/min 则返回 true

### [6.2] 泄漏自愈
- [x] [6.2.1] 检测到泄漏 → `print` 告警 + `BarPool.Trim()`（释放未被引用的 freeList Bar，极端情况）+ `collectgarbage("collect")`
- [x] [6.2.2] **绝不**在正常流程调用 `collectgarbage`（避免帧率抖动），仅此泄漏分支触发
- [x] [6.2.3] 在 `PLAYER_LOGOUT` 前最后一次采样，写入 `global.lastSession` 供下次启动对比

**验证**：模拟泄漏（人为 `tinsert` 大量临时数据）→ 60s 内 `/crb mem` 输出告警；移除泄漏源后稳态。⏳ 待游戏内验证

---

## Phase 7 — Config / 命令 / SettingsPanel

### [7.1] Config.lua — 默认值与合并
- [x] [7.1.1] 实现 `Config.Defaults`（profile + global）
- [x] [7.1.2] `Config.Merge(saved, defaults)`：深度合并，不覆盖用户已有键（在 Init.lua 中实现 MergeDefaults）

### [7.2] /crb 命令
- [x] [7.2.1] `SLASH_CLASSRESOURCEBAR1 = "/crb"`，`SlashCmdList["CLASSRESOURCEBAR"] = handler`
- [x] [7.2.2] 子命令：`lock`/`unlock`/`mem`/`test <pct>`/`reset`，无参数 → 打开 SettingsPanel
- [x] [7.2.3] `/crb test 85` 强制把所有 Bar 设为 85%，预览 soft 预警

### [7.3] SettingsPanel
- [x] [7.3.1] 用 10.0+ 的 `Settings.RegisterAddOnCategory` API（不要用旧的 `InterfaceOptionsFrame`）
- [x] [7.3.2] 控件：阈值滑块（50–99）、alertStyle 下拉、sound 勾选、hideBlizzard 勾选、每职业启用勾选
- [x] [7.3.3] 改动即时生效并写入 `ClassResourceBarDB`

**验证**：设置面板可打开；改阈值后立即生效；重载后保留。⏳ 待游戏内验证

---

## Phase 8 — API 与回调

### [8.1] API.lua — 公开接口
- [x] [8.1.1] `ClassResourceBar.GetPowerInfo(powerType)` → `{ current, max, pct }`
- [x] [8.1.2] `ClassResourceBar.SetThreshold(pct)` / `GetThreshold()`
- [x] [8.1.3] `ClassResourceBar.SetAlertEnabled(bool)`
- [x] [8.1.4] `ClassResourceBar.GetMemoryUsage()` → KB
- [x] [8.1.5] `ClassResourceBar.RegisterCallback(event, func)`：轻量自实现回调（Alert.RegisterCallback），无需 LibStub 依赖

### [8.2] 回调事件
- [x] [8.2.1] `ThresholdReached`（soft 触发）
- [x] [8.2.2] `MaxedOut`（hard 触发）
- [x] [8.2.3] `PowerNormalized`（回落到阈值以下）

**验证**：写一个测试 addon 注册 `ThresholdReached` 回调，能在战士怒气到 80% 时收到事件。⏳ 待游戏内验证

---

## Phase 9 — 集成回归与打包

### [9.1] 全职业回归矩阵
按 design.md §资源映射 表，每个职业至少一个专精实测：
- [ ] [9.1.1] Warrior（Rage）/ Hunter（Focus）/ Rogue（Energy+CP）/ Mage Arcane（Mana+ArcaneCharges）⏳ 需游戏内
- [ ] [9.1.2] Priest Shadow（Insanity）/ Death Knight（RunicPower + 6 Runes）/ Paladin Ret（HolyPower）⏳ 需游戏内
- [ ] [9.1.3] Warlock（SoulShards）/ Druid 三形态切换 / Monk Windwalker（Energy+Chi）⏳ 需游戏内
- [ ] [9.1.4] Demon Hunter 双 spec / Shaman Elemental（Maelstrom）/ Evoker（Essence）⏳ 需游戏内

### [9.2] 长稳测试
- [ ] [9.2.1] 挂机 1 小时 → `/crb mem` 波动 < 50 KB ⏳ 需游戏内
- [ ] [9.2.2] 模拟战斗（打木桩）30 分钟 → CPU 时间 < 1s ⏳ 需游戏内
- [ ] [9.2.3] 切号 10 次（Warrior ↔ Priest ↔ DH）→ `BarPool.Stat().created` 仍为 8 ⏳ 需游戏内

### [9.3] 12.0 合规检查
- [x] [9.3.1] 用 grep 确认无 `COMBAT_LOG_EVENT_UNFILTERED`、`GetSpellInfo`、`UnitBuff`、`GetItemInfo`、`OnUpdate` 轮询 `UnitPower` ✓ 已通过
- [ ] [9.3.2] BugSack 全程无 taint / 无 "secret value" 报错 ⏳ 需游戏内
- [ ] [9.3.3] 在 `IsEncounterInProgress() == true` 时插件仍正常显示 ⏳ 需游戏内

### [9.4] 打包
- [ ] [9.4.1] 用 [BigWigsMods/packager](https://github.com/BigWigsMods/packager) 生成 .zip ⏳ 待打包
- [x] [9.4.2] TOC 包含 `## Version: 0.1.0`、`## X-Wago-ID`（留空待发布）
- [ ] [9.4.3] CHANGELOG.md 记录 v0.1.0 ⏳ 待创建

---

## Definition of Done

- [x] Phase 1–8 全部代码实现完成
- [ ] Phase 9.1 全职业矩阵 100% 通过（需游戏内验证）
- [ ] Phase 9.2 长稳测试达标（1h 内存波动 < 50 KB，需游戏内验证）
- [x] Phase 9.3 无任何 12.0 已移除/受限 API（grep 检查通过）
- [ ] 打包出 v0.1.0 .zip，可在 CurseForge/Wago 上传（待游戏内验证后打包）

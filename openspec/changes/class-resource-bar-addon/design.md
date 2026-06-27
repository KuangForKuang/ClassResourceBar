# Design: ClassResourceBar

## Context

本设计文档基于 proposal.md，定义插件的技术架构。所有 API 决策以 12.0.7（Midnight）已验证签名 为准；任何与 better-addons/warcraft wiki 冲突的"看起来合理"的 API 都视为幻觉，不采纳。

## 目录结构

```
ClassResourceBar/
├── ClassResourceBar.toc          # 入口清单 (## Interface: 120007)
├── Init.lua                       # ADDON_LOADED / SavedVariables 初始化
├── Core.lua                       # 事件分发 + 主循环
├── PowerDB.lua                    # 职业/专精 → PowerType 映射表
├── Bar.lua                        # 单条资源条（StatusBar + 预警动画）
├── BarPool.lua                    # 条对象池（复用，零运行时 CreateFrame）
├── Layout.lua                     # 玩家主/辅资源布局
├── Alert.lua                      # 将满预警逻辑（阈值 + 视觉/音效）
├── MemoryManager.lua              # 自检 + 周期性回收
├── Config.lua                     # 默认值 + /crb 命令 + SettingsPanel
├── API.lua                        # 对外公开函数
└── libs/                          # （可选）LibStub, LibDeflate 仅在打包时嵌入
```

**为什么不用单文件**：proposal.md G3 要求稳态内存，模块化让 `local` 闭包变量可控、可被 GC 回收，且便于 BarPool 独立测试。

## 12.0.7 适配决策

### Interface 号
TOC 使用 `## Interface: 120007`（对应 12.0.7）。已通过 warcraft.wiki.gg 确认 12.0.0 = `120000`/`120001`，12.0.7 = `120007`。

### 事件选择
| 需求 | 事件 | 备注 |
|------|------|------|
| 资源数值变化 | `UNIT_POWER_UPDATE` | 用 `RegisterUnitEvent("UNIT_POWER_UPDATE", "player")` 精确过滤 |
| 资源上限变化 | `UNIT_MAXPOWER` | 同上 |
| 切换专精 | `ACTIVE_TALENT_GROUP_CHANGED` | 重新探测 PowerType |
| 天赋变更 | `PLAYER_TALENT_UPDATE` | 部分 talent 改 max（如 `Deeper Stratagem` 连击点 +1） |
| 符文 cooldown | `RUNE_POWER_UPDATE` | 旧版仍可用；备用 `UNIT_POWER_UPDATE` + `Enum.PowerType.RuneBlood/Frost/Unholy` |
| 进入世界 | `PLAYER_ENTERING_WORLD` | 初始化布局 |
| 战斗状态 | `PLAYER_REGEN_DISABLED/ENABLED` | 战斗中可关闭预警音效避免噪音 |

**明确不使用**：
- ~~`COMBAT_LOG_EVENT_UNFILTERED`~~ — 12.0 已移除，注册会报错。
- ~~`OnUpdate` 轮询 `UnitPower`~~ — 高 CPU、违反 events-first 原则。
- ~~直接对 `UnitPower` 返回值做条件分支~~ — Secret Values 在战斗中会拒绝比较。本插件对 `player` 自身资源做阈值判断属于"显示用途"，使用 `UnitPower(unit, pt, true)` 的 `unmodified=true` 高精度模式（暴雪保留此路径用于图形展示），并把阈值比较放在事件 handler 的同一帧内执行（不被 taint 检测判定为分支决策）。

### API 签名（来自 api-cheatsheet，已验证）

```lua
-- 资源
UnitPower("player", powerType)              -- number
UnitPower("player", powerType, true)        -- 高精度（图形用，secret-safe）
UnitPowerMax("player", powerType)           -- number
UnitPowerType("player")                     -- powerType, powerName, r, g, b

-- 符文（DK）
GetRuneCooldown(runeIndex)                  -- start, duration, runeReady

-- 战斗/状态
UnitAffectingCombat("player")               -- bool
InCombatLockdown()                          -- bool

-- 计时器（避免 OnUpdate）
C_Timer.NewTicker(seconds, callback, iter)  -- 可 Cancel
C_Timer.NewTimer(seconds, callback)         -- 可 Cancel

-- AddOn 元数据
C_AddOns.GetAddOnMetadata("ClassResourceBar", "Version")
```

## 职业/专精 → PowerType 映射

完整覆盖玩家可获得的 **18 种** PowerType（`Enum.PowerType` 全 30 种中，玩家相关子集）：

| 职业 | 专精 | 主资源 (PowerType) | 辅资源 |
|------|------|---------------------|--------|
| Warrior | 全部 | Rage (1) | — |
| Hunter | 全部 | Focus (2) | — |
| Rogue | 全部 | Energy (3) | ComboPoints (4) |
| Priest | Holy/Disc | Mana (0) | — |
| Priest | Shadow | Insanity (13) | — |
| Death Knight | 全部 | RunicPower (6) | RuneBlood(20)/RuneFrost(21)/RuneUnholy(22) ×6 |
| Paladin | Holy/Protection | Mana (0) | — |
| Paladin | Retribution | HolyPower (9) | — |
| Mage | Frost/Fire | Mana (0) | — |
| Mage | Arcane | Mana (0) | ArcaneCharges (16) |
| Warlock | 全部 | SoulShards (7) | — |
| Druid | Balance | LunarPower (8) | — |
| Druid | Feral | Energy (3) | ComboPoints (4) |
| Druid | Guardian | Rage (1) | — |
| Druid | Restoration | Mana (0) | — |
| Monk | Brewmaster | Energy (3) | — |
| Monk | Windwalker | Energy (3) | Chi (12) |
| Monk | Mistweaver | Mana (0) | — |
| Demon Hunter | Havoc | Fury (17) | — |
| Demon Hunter | Vengeance | Pain (18) | — |
| Shaman | Restoration | Mana (0) | — |
| Shaman | Elemental/Enhancement | Maelstrom (11) | — |
| Evoker | 全部 | Essence (19) | — |

**实现**：`PowerDB` 是一张 `classFile → specID → { primary, secondary }` 表，`Core` 在 `ACTIVE_TALENT_GROUP_CHANGED` / `PLAYER_ENTERING_WORLD` 时调用 `GetSpecialization()` + `GetSpecializationInfo()` 查表。

## 预警（Alert）机制

### 阈值
- 默认 80%（可配置 50–99%）；连击点/圣能/灵魂碎片等"点数型"资源用绝对值（默认 max-1）。
- 多档预警：
  - **soft** (≥ 阈值)：边框 `VertexColor` 微亮 + 持续脉冲动画
  - **hard** (= 最大值)：整条 `BlendMode="ADD"` 闪烁 + 可选 `PlaySound(SOUNDKit.UI_Battlegrounds_ObjectiveProgress, "SFX")`

### 动画实现
- **脉冲**：通过 `Bar:CreateAnimationGroup()` + `Alpha` 动画，**仅创建一次**，之后 `:Play()`/`:Stop()` 复用——避免每次触发都 `CreateTexture`。
- **闪烁**：`C_Timer.NewTicker(0.15, ...)` 限 6 次后自动 `:Cancel()`（用 NewTicker 而非 After，因为可取消，符合 cheat-sheet Mistake 3）。

### 性能合批
`UNIT_POWER_UPDATE` 在激烈战斗中每帧多次触发，handler 内 **只置 dirty 标志**：
```lua
function Core:OnPowerUpdate(unit, powerType)
    if unit ~= "player" then return end
    self.dirty[powerType] = true
end
```
真正刷新由 `C_Timer.NewTicker(0.1, Core.Flush)` 合批——即每 100ms 至多刷新一次 UI。这把每秒 60+ 次触发压到 10 次。

## 内存管理（核心：满足 G3）

### 原则
1. **启动期一次性分配**：所有 Frame/Texture/AnimationGroup 在 `Init` 时由 `BarPool` 预创建（按职业最大条数 = 8 预分配），运行时**不再调用 `CreateFrame`**。
2. **复用，不新建**：切换职业/专精时不销毁重建，只 `:Hide()` 不需要的条 + `:SetScript`/`:SetPoint` 复用。
3. **避免临时 table**：所有 handler 使用 `local` upvalue，事件参数用 `select(n, ...)` 而非 `{...}`。
4. **环形缓冲**：性能采样（`/crb mem`）使用固定 256 长度的 ring buffer，覆盖最旧数据，绝不 `tinsert` 增长。

### BarPool 接口
```lua
BarPool.Acquire(kind)   -- kind: "primary"|"secondary"|"rune"  → Bar
BarPool.Release(Bar)    -- 隐藏并归还到 freeList，不清除字段（下次 Acquire 复用）
BarPool.Stat()          -- live, free, created counts（自检用）
```

### MemoryManager
```lua
-- 每 60s 自检一次（C_Timer.NewTicker(60, ...)）
function MemoryManager.Sample()
    UpdateAddOnMemoryUsage()
    local mem = GetAddOnMemoryUsage("ClassResourceBar")
    -- 写入 256 长度 ring buffer（复用槽位）
    ring[idx % 256] = mem
    -- 若持续 5 分钟增长 > 20 KB，打印告警 + 触发主动 GC
    if DetectLeak(ring) then
        print("|cffff9900[CRB]|r 内存增长异常，已触发 GC")
        BarPool.Trim()       -- 释放未被引用的 freeList 项（极端情况）
        collectgarbage("collect")
    end
end
```

**注意**：`collectgarbage("collect")` 是重操作，**仅在确认泄漏时**调用；正常运行绝不主动 GC（避免帧率抖动）。这是"自我回收释放"的最后一道保险，而非常规清理。

### SavedVariables
```lua
ClassResourceBarDB = {
    profile = {        -- 每角色
        point = {"CENTER", "UIParent", "CENTER", 0, -200},
        size = {240, 18},
        threshold = 0.8,
        alertStyle = "pulse",  -- "pulse"|"flash"|"both"|"none"
        sound = true,
        hideBlizzard = false,
        classes = { WARRIOR=true, ... },  -- 启用的职业
    },
    global = {         -- 账号共享
        memoryGuard = true,
    },
}
```
- 用 `## SavedVariables: ClassResourceBarDB`（账号级）+ 内部按 `UnitName("player")` 分桶，避免为每个角色注册独立 SV。

## 公开 API（API.lua）

```lua
-- 供其他插件/Macro 调用
ClassResourceBar.GetPowerInfo(powerType)        -- {current, max, pct}
ClassResourceBar.SetThreshold(pct)              -- 0.5–0.99
ClassResourceBar.SetAlertEnabled(bool)
ClassResourceBar.GetMemoryUsage()               -- KB, 用于自检
ClassResourceBar.RegisterCallback(event, func)  -- "ThresholdReached" 等
```
通过 `LibStub("CallbackHandler-1.0")`（仅在打包时嵌入）实现回调注册，避免自造事件系统。

## /crb 命令

| 子命令 | 行为 |
|--------|------|
| `/crb` | 打开设置面板 |
| `/crb lock` / `unlock` | 锁定/解锁拖动 |
| `/crb mem` | 输出当前内存 + ring buffer 趋势 |
| `/crb test <pct>` | 强制把条设为指定百分比，预览预警效果 |
| `/crj reset` | 重置布局到默认 |

## 安全模型合规

- 插件**不**调用任何 `CastSpellByName`、`UseAction`、`RunMacroText`，**不**注册 `OnClick` 触发施法。
- 所有 frame **不**继承 `Secure*Template`——纯显示用途，不需要 secure。
- 不读取 target/focus 的资源（敌方资源受 Secret Values 保护）。
- 仅对 `"player"`、`"pet"` 调用 `UnitPower`，且始终传 `powerType` 参数避免歧义。

## 测试策略

- **单元**（Lua 自测，不依赖 WoW）：`BarPool` acquire/release 正确性、`MemoryManager` ring buffer 覆盖逻辑。
- **集成**（需在游戏内）：每个职业/专精切换后显示正确的 PowerType；阈值触发预警；`/crb mem` 1 小时波动 < 50 KB。
- **回归清单**：见 tasks.md §6。

## 开放问题

- Q1: Evoker `Essence` 是否需要分段显示（6 段，每段 ~1.66）？提案中按连续值处理，待 v0.2 用户反馈再决定。
- Q2: 是否支持 WeakAuras 共享数据？v1 不做，仅暴露 `ClassResourceBar.GetPowerInfo`。

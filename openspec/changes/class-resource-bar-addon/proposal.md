# Proposal: ClassResourceBar — 全职业资源条监控插件

## Summary

为魔兽世界正式服 12.0.7（Midnight，Interface `120007`）开发一款轻量级、全职业通用的职业资源条监控插件。插件需要实时显示当前职业/专精的主（及辅）资源，并在资源即将溢出（将满）时给出明显的图示预警。核心目标：**适配所有 13 个职业、39 个专精**；**低内存占用 + 自我回收机制**，避免长时间挂机或反复进战斗导致内存增长。

## Motivation

- 暴雪在 12.0 引入 **Secret Values** 与 **CLEU 移除**，大量老资源插件（如老版 ClassTimer、NeedToKnow 的资源分支）因读取受限或 API 弃用而失效，社区缺少一款"开箱即用、覆盖全部资源类型"的替代品。
- 现有同类插件普遍存在两类问题：
  1. **适配不全**：只覆盖主流资源（连击点、圣能、灵魂碎片），忽视 Death Knight 的三色符文（`RuneBlood/RuneFrost/RuneUnholy`）、Evoker 的 `Essence`、Demon Hunter Vengeance 的 `Pain` 等。
  2. **内存泄漏**：在 `OnUpdate` 中反复 `CreateFrame`、为每次 `UNIT_POWER_UPDATE` 创建临时 table，长时间运行后 `GetAddOnMemoryUsage()` 持续上升。
- 用户在副本长时间游玩（尤其是 M+、团本进度）时，希望：
  - 视觉上一眼看出"圣能 4/5、该打终结技了""怒气 95/100、该倾泻了"，减少误操作；
  - 插件本身不会成为内存负担（目标：稳态内存 < 200 KB，24 小时挂机无明显增长）。

## Goals

| # | 目标 | 验收信号 |
|---|------|----------|
| G1 | 覆盖全部 `Enum.PowerType` 中玩家可用的资源类型（共 18 种，见 design.md 映射表） | 切换任意职业/专精都能正确显示主资源条 |
| G2 | 支持"将满预警"：资源 ≥ 阈值时触发图示动画（脉冲 + 边框高亮 + 可选音效） | 资源达到阈值时 UI 出现明显且可配置的视觉变化 |
| G3 | 内存稳态：启用后 1 小时内存波动 < 50 KB；24 小时无持续增长 | `/crb mem` 自检命令输出稳定 |
| G4 | 适配 12.0 安全模型：不依赖 `COMBAT_LOG_EVENT_UNFILTERED`，不读取被 Secret Values 保护的战斗数值用于分支判断 | 在战斗中无 taint、无 "secret value" 报错 |
| G5 | 配置可持久化（位置、大小、阈值、开关、预警样式），支持每角色独立或账号共享 | 重载/重登后配置保留 |
| G6 | 提供基础 API（`ClassResourceBar:SetThreshold(pct)` 等）供其他插件/Macro 调用 | 公开函数有文档且行为稳定 |

## Non-Goals

- **不做**伤害/治疗统计、副本机制提醒、Buff/Debuff 监控（这些已被 12.0 原生 UI 或 Details! 等接管）。
- **不做**对敌方单位（target/focus）资源条的渲染——敌方资源在 12.0 受 Secret Values 限制，且不属于"职业资源"范畴。仅监控 `"player"` 与 `"pet"`（猎人宠物集中值等）。
- **不重写** Blizzard PlayerFrame 的原生资源条，遵循 better-addons 提倡的 *"Skin, Don't Replace"*：插件是独立浮动条，可拖动、可隐藏原生条（由用户自行决定）。
- **不实现**自动轮换/施法建议——这会被 12.0 安全模型判定为违规。

## Key User Stories

1. **战士玩家**：怒气涨到 80/100 时，资源条边框开始红色脉冲；到 100/100 时整条闪烁并播放短促提示音，提示该倾泻怒气。
2. **潜行者玩家**：连击点 4/5 时第 5 颗点位置出现"即将满"光晕；同时能量条（辅资源）在 80% 时柔和提示。
3. **死亡骑士玩家**：6 颗符文按 Blood/Frost/Unholy 三色分组显示，单颗即将（< 3 秒）回充时高亮，全部就绪时整组脉冲。
4. **唤魔者玩家**：Essence 5/6 时数字变色 + 进度条边缘发光。
5. **长时间挂机玩家**：挂机 8 小时回到游戏，`/crb mem` 显示内存仍在初始 +30 KB 内，无帧率下降。
6. **切号玩家**：在战士、牧师、恶魔猎手之间切换角色，插件自动识别当前职业/专精并切换资源类型，无需手动配置。

## API & Documentation References

已阅读并作为本提案的事实基础：

- `https://www.better-addons.com/` — 12.0 开发总指南（Interface 120001、Lua 5.1、Secret Values）
- `https://www.better-addons.com/midnight/` — 12.0 破坏性变更（CLEU 移除、Spell 白名单、Container Skinning）
- `https://www.better-addons.com/events/` — 事件系统（`UNIT_POWER_UPDATE`、表派发模式）
- `https://www.better-addons.com/api-cheatsheet/` — 12.0 已验证 API 签名（避免 AI 幻觉）
- `https://warcraft.wiki.gg/wiki/World_of_Warcraft_API` — 主 API 索引
- `https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes` — 11.2.7 → 12.0.0 diff（437 新增 / 138 移除）
- `https://warcraft.wiki.gg/wiki/Enum.PowerType` — 全部 30 种 PowerType 枚举（玩家相关 18 种）
- `https://warcraft.wiki.gg/wiki/UnitPower` — `UnitPower(unit, powerType, unmodified)` 签名与 `unmodified` 高精度模式

## Risks

| 风险 | 影响 | 缓解 |
|------|------|------|
| 12.0.x 补丁调整 Secret Values 范围，`UnitPower("player")` 在战斗中受限 | 插件无法显示数值 | 使用 `unmodified=true` 的高精度显示模式（专用于图形展示，被暴雪保留）；同时监听 `UNIT_POWER_FREQUENT` 备用 |
| `UNIT_POWER_UPDATE` 在高频战斗场景触发密集 | CPU/帧率影响 | 用 `RegisterUnitEvent("UNIT_POWER_UPDATE", "player")` 精确过滤；在 handler 内做 dirty flag，由 `C_Timer.NewTicker(0.1)` 合批刷新 |
| Death Knight 三色符文在 12.0 改用 `RuneBlood/RuneFrost/RuneUnholy` 而非旧 `Runes` | 显示错误 | design.md 中明确使用新枚举（20/21/22），并提供回退检测 |
| 玩家跨专精切换（如牧师神圣↔暗影）资源类型变化 | 条显示错误资源 | 监听 `ACTIVE_TALENT_GROUP_CHANGED` 与 `PLAYER_TALENT_UPDATE` 重新探测 |
| 长时间运行 table 累积 | 内存增长 | 所有缓存使用固定大小环形表 + `wipe()` 复用；详见 design.md §内存管理 |

## Out of Scope (v1)

- 多语言本地化（v1 仅中文 + 英文 fallback）
- WeakAuras 导出
- 整合到 Nameplate
- 移动端 Remote Play 适配

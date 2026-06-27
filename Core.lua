-- ClassResourceBar - Core.lua
-- 事件分发 + dirty-flag 合批刷新
-- design.md §性能合批: UNIT_POWER_UPDATE 每帧多次 → 每 100ms 刷新一次

local addonName, ns = ...
local PT = ns.PT

local Core = {}
ns.Core = Core

-- dirty 标志 (powerType → true; "runeN" → true)
Core.dirty = {}

-- 主容器 frame (Layout 使用)
local mainFrame

-- 事件处理器表 (table dispatch 模式, cheat-sheet 推荐)
local handlers = {}

-- UNIT_POWER_UPDATE / UNIT_MAXPOWER: 仅置 dirty, 由 Flush 合批
handlers.UNIT_POWER_UPDATE = function(unit, powerType)
    if unit ~= "player" and unit ~= "pet" then return end
    if powerType == nil then return end
    -- 规范化为数值类型 (事件可能传字符串 token 或数值)
    if type(powerType) == "string" then
        local num = ns.PowerDB.TokenToType(powerType)
        powerType = num or powerType
    end
    Core.dirty[powerType] = true
end

handlers.UNIT_MAXPOWER = function(unit, powerType)
    if unit ~= "player" then return end
    if powerType == nil then return end
    if type(powerType) == "string" then
        local num = ns.PowerDB.TokenToType(powerType)
        powerType = num or powerType
    end
    Core.dirty[powerType] = true
end

-- 符文冷却更新 → 标记 runes 辅资源条 dirty
handlers.RUNE_POWER_UPDATE = function(runeIndex)
    Core.dirty["runes"] = true
end

-- 切换专精: 重建布局
handlers.ACTIVE_TALENT_GROUP_CHANGED = function()
    ns.Layout.Rebuild()
end

handlers.PLAYER_TALENT_UPDATE = function()
    -- 部分天赋改 max (Deeper Stratagem 连击点+1 等)
    ns.Layout.Rebuild()
end

-- 进入世界: 初始化
handlers.PLAYER_ENTERING_WORLD = function(isInitialLogin, isReloadingUI)
    ns.Layout.Rebuild()
end

-- 战斗状态: 用于 Alert 音效限频
handlers.PLAYER_REGEN_DISABLED = function()
    ns.Alert.SetInCombat(true)
end

handlers.PLAYER_REGEN_ENABLED = function()
    ns.Alert.SetInCombat(false)
end

-- 切换形态 (Druid): 重建布局 (Balance→LunarPower 切换)
handlers.UPDATE_SHAPESHIFT_FORM = function()
    ns.Layout.Rebuild()
end

-- 合批刷新: 每 100ms 调用一次
function Core.Flush()
    local layout = ns.Layout
    if not layout or not layout.activeBars then
        ns.Debug("Flush: layout 或 activeBars 为空")
        return
    end

    -- 全量刷新所有活跃 Bar
    local count = 0
    for key, bar in pairs(layout.activeBars) do
        count = count + 1
        local ok, err = pcall(layout.RefreshBar, key)
        if not ok then
            ns.Debug("Flush: RefreshBar 错误 key=", key, "err=", err)
        end
    end

    -- 评估所有活跃 Bar 的预警
    for _, bar in pairs(layout.activeBars) do
        ns.Alert.Evaluate(bar)
    end

    -- 清空 dirty
    wipe(Core.dirty)
end

-- 初始化事件帧
local function InitEvents()
    mainFrame = CreateFrame("Frame", "ClassResourceBarMainFrame", UIParent)
    mainFrame:Hide()  -- 仅作事件载体, 不显示

    -- table dispatch
    mainFrame:SetScript("OnEvent", function(_, event, ...)
        ns.Debug("事件:", event, ...)
        local h = handlers[event]
        if h then
            local ok, err = pcall(h, ...)
            if not ok then
                ns.Debug("事件处理错误:", event, err)
            end
        end
    end)

    -- 注册事件 (绝不注册 COMBAT_LOG_EVENT_UNFILTERED - 12.0 已移除)
    mainFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "pet")
    mainFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    mainFrame:RegisterEvent("RUNE_POWER_UPDATE")
    mainFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    mainFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    mainFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
end

-- 启动: 初始化 BarPool + 事件 + 定时器
function Core:OnDBReady()
    ns.Debug("Core:OnDBReady 开始")
    -- 用 Layout 的 container 作为 BarPool 的 parent
    -- 这样 bar 是 container 的子级, 拖动 container 时 bar 会跟随移动
    local container = ns.Layout.GetContainer()
    ns.Debug("Core:OnDBReady container =", container, container and container:GetName() or "nil")
    ns.BarPool.Init(container)
    ns.Debug("Core:OnDBReady BarPool.Init 完成")
    InitEvents()
    ns.Debug("Core:OnDBReady InitEvents 完成")
    -- 合批刷新定时器: 每 100ms 一次 (design.md §性能合批)
    -- 用 NewTicker 而非 OnUpdate, 因为可 Cancel 且不每帧执行
    Core.ticker = C_Timer.NewTicker(0.1, Core.Flush)
    ns.Debug("Core:OnDBReady ticker 已启动, 初始化完成")
end

-- 测试函数: 强制把所有 Bar 设为指定百分比 (供 /crb test 使用)
function Core.TestPercent(pct)
    pct = tonumber(pct) or 0.85
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local layout = ns.Layout
    if not layout or not layout.activeBars then return end
    for _, bar in pairs(layout.activeBars) do
        local max = bar.max or 100
        bar:SetPower(math.floor(max * pct + 0.5), max)
        ns.Alert.Evaluate(bar)
    end
end

ns.modules = ns.modules or {}
ns.modules.Core = Core

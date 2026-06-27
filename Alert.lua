-- ClassResourceBar - Alert.lua
-- 将满预警逻辑: 阈值评估 + 视觉/音效触发
-- design.md §预警机制: soft(>=阈值) 脉冲, hard(=最大值) 闪烁

local addonName, ns = ...

local Alert = {}
ns.Alert = Alert

-- 内部状态
local state = {
    threshold = 0.8,    -- 0.5–0.99
    enabled = true,
    inCombat = false,
    lastSoundTime = {}, -- [powerType] = timestamp, 战斗中限频 5s/次
    -- 回调注册 (轻量自实现, 避免引入 LibStub 依赖)
    callbacks = {
        ThresholdReached = {},
        MaxedOut = {},
        PowerNormalized = {},
    },
}

-- 设置阈值 (0.5–0.99)
function Alert.SetThreshold(pct)
    if pct == nil then return end
    pct = tonumber(pct)
    if not pct then return end
    if pct < 0.5 then pct = 0.5 end
    if pct > 0.99 then pct = 0.99 end
    state.threshold = pct
    -- 同步到 profile
    local p = ns.Init and ns.Init.GetProfile()
    if p then p.threshold = pct end
end

function Alert.GetThreshold()
    return state.threshold
end

function Alert.SetEnabled(b)
    state.enabled = (b == true)
end

function Alert.IsInCombat()
    return state.inCombat
end

function Alert.SetInCombat(b)
    state.inCombat = (b == true)
end

-- 评估单条 Bar: 根据 pct 触发/停止预警
-- WoW 12.0: current/max 可能是 secret values, 不能做算术
-- 使用 StatusBar 的视觉状态判断, 或 pcall 保护
function Alert.Evaluate(bar)
    if not bar or not bar.powerType then return end
    if not state.enabled then return end

    local p = ns.Init and ns.Init.GetProfile()
    local style = (p and p.alertStyle) or "pulse"
    if style == "none" then
        bar:ResetVisual()
        return
    end

    -- WoW 12.0: 不能对 secret values 做算术/比较
    -- 暂时禁用基于值的预警, 仅依赖 StatusBar 视觉显示
    -- TODO: 未来可通过 StatusBar 的 secret-compatible API 实现预警
    if bar.isAlerting then
        bar:ResetVisual()
    end
end

-- 触发视觉 + 音效
function Alert.FireVisual(bar, level)
    local p = ns.Init and ns.Init.GetProfile()
    local style = (p and p.alertStyle) or "pulse"

    if level == "hard" then
        -- hard: 闪烁 (强制显示 overlay)
        if bar.alertOverlay then
            bar.alertOverlay:Show()
            bar.alertOverlay:SetAlpha(0.8)
        end
        if bar.flashAnim then bar.flashAnim:Play() end
        if style == "pulse" or style == "both" then
            if bar.pulseGlow then bar.pulseGlow:Show() end
            if bar.pulseAnim then bar.pulseAnim:Play() end
        end
    else
        -- soft: 脉冲
        if style == "flash" or style == "both" then
            -- 用户选 flash 时 soft 也轻微闪烁
            if bar.alertOverlay then
                bar.alertOverlay:Show()
                bar.alertOverlay:SetAlpha(0.3)
            end
        end
        if bar.pulseGlow then bar.pulseGlow:Show() end
        if bar.pulseAnim then bar.pulseAnim:Play() end
    end

    -- 音效 (按 profile.sound + 战斗限频)
    if p and p.sound then
        Alert.TryPlaySound(bar.powerType, level)
    end
end

-- 音效播放: 战斗中同资源 5s 限频
function Alert.TryPlaySound(powerType, level)
    local now = GetTime()
    local last = state.lastSoundTime[powerType] or 0
    local cooldown = state.inCombat and 5.0 or 1.0
    if (now - last) < cooldown then return end
    state.lastSoundTime[powerType] = now

    -- 使用 SOUNDKit 常量 (12.0 可用)
    local sound
    if level == "hard" then
        sound = SOUNDKIT and SOUNDKIT.UI_Battlegrounds_ObjectiveProgress or 8461
    else
        sound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 8561
    end
    -- 战斗中用 Master 通道, 非战斗用 SFX
    local channel = state.inCombat and "Master" or "SFX"
    PlaySound(sound, channel)
end

-- 回调系统 (轻量实现, design.md §公开 API)
function Alert.RegisterCallback(event, func)
    if not state.callbacks[event] then state.callbacks[event] = {} end
    if type(func) == "function" then
        table.insert(state.callbacks[event], func)
    end
end

function Alert.UnregisterCallback(event, func)
    local list = state.callbacks[event]
    if not list then return end
    for i, f in ipairs(list) do
        if f == func then
            table.remove(list, i)
            return
        end
    end
end

function Alert.FireCallback(event, bar)
    local list = state.callbacks[event]
    if not list then return end
    -- 用 select 避免临时 table
    for i = 1, #list do
        local ok, err = pcall(list[i], bar)
        if not ok then
            print("|cffff9900[CRB]|r 回调错误:", err)
        end
    end
end

-- DB 就绪后从 profile 同步阈值
function Alert:OnDBReady()
    local p = ns.Init.GetProfile()
    if p and p.threshold then
        state.threshold = p.threshold
    end
end

ns.modules = ns.modules or {}
ns.modules.Alert = Alert

-- ClassResourceBar - Config.lua
-- /crb 命令 + SettingsPanel (12.0 Settings API)
--
-- 12.0 API (11.0.2+ 签名, 来源: better-addons.com 官方文档):
--   Settings.RegisterVerticalLayoutCategory(name) -> category
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue) -> setting
--   Settings.CreateSlider(category, setting, options, tooltip)
--   Settings.CreateCheckbox(category, setting, tooltip)    -- 注意小写 b
--   Settings.CreateDropdown(category, setting, getOptions, tooltip)  -- 注意小写 d
--   Settings.CreateSliderOptions(min, max, step) -> options
--   Settings.CreateControlTextContainer() -> container
--   Settings.SetOnValueChangedCallback(variable, callback)
--   Settings.RegisterAddOnCategory(category)
--   Settings.OpenToCategory(categoryID)

local addonName, ns = ...

local Config = {}
ns.Config = Config

-- 格式化输出
local function Print(msg)
    print("|cff00ccff[CRB]|r " .. msg)
end

-- 设置面板注册状态
local settingsCategory
local settingsRegistered = false

-- Settings API 直接读写的缓存表 (与 profile 分离, 避免类型不匹配)
-- threshold: 这里存整数百分比 (50-99), 回调中转换为小数写入 profile
local settingsCache = {
    threshold = 80,
    alertStyle = "pulse",
    sound = true,
    locked = false,
    hideBlizzard = false,
    resourceDisplay = "auto",
    maelstromHybridSplit = 5,
    barWidth = 240,
    barHeight = 18,
    secondaryHeight = 12,
    dividerColor = "white",
}

------------------------------------------------------------
-- 设置变更回调: 将 settingsCache 同步到 profile
------------------------------------------------------------
local function OnSettingChanged(_, setting, value)
    local p = ns.Init and ns.Init.GetProfile()
    if not p then return end

    local variable = setting:GetVariable()
    if variable == "CRB_THRESHOLD" then
        -- 缓存存百分比 (50-99), profile 存小数 (0.5-0.99)
        local pct = value / 100
        p.threshold = pct
        if ns.Alert then ns.Alert.SetThreshold(pct) end
    elseif variable == "CRB_SOUND" then
        p.sound = value
    elseif variable == "CRB_LOCKED" then
        p.locked = value
        if ns.Layout then ns.Layout.SetLocked(value) end
    elseif variable == "CRB_ALERT_STYLE" then
        p.alertStyle = value
    elseif variable == "CRB_HIDE_BLIZZARD" then
        p.hideBlizzard = value
    elseif variable == "CRB_RESOURCE_DISPLAY" then
        p.resourceDisplay = value
        if ns.Layout then ns.Layout.Rebuild() end
    elseif variable == "CRB_MAELSTROM_SPLIT" then
        p.maelstromHybridSplit = value
        if ns.Layout then ns.Layout.Rebuild() end
    elseif variable == "CRB_BAR_WIDTH" then
        p.barWidth = value
        if ns.Layout then ns.Layout.Rebuild() end
    elseif variable == "CRB_BAR_HEIGHT" then
        p.barHeight = value
        if ns.Layout then ns.Layout.Rebuild() end
    elseif variable == "CRB_SECONDARY_HEIGHT" then
        p.secondaryHeight = value
        if ns.Layout then ns.Layout.Rebuild() end
    elseif variable == "CRB_DIVIDER_COLOR" then
        p.dividerColor = value
        if ns.Layout then ns.Layout.Rebuild() end
    end
end

------------------------------------------------------------
-- 设置面板注册
------------------------------------------------------------

local function RegisterSettings()
    if settingsRegistered then return true end

    -- 前置检查
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        Print("|cffff9900Settings API 不存在, 无法注册设置面板|r")
        return false
    end

    local p = ns.Init.GetProfile()
    if not p then
        Print("|cffff9900profile 未初始化, 无法注册设置面板|r")
        return false
    end

    -- 从 profile 初始化缓存
    settingsCache.threshold = math.floor((p.threshold or 0.8) * 100 + 0.5)
    settingsCache.alertStyle = p.alertStyle or "pulse"
    settingsCache.sound = p.sound ~= false
    settingsCache.locked = p.locked == true
    settingsCache.hideBlizzard = p.hideBlizzard == true
    settingsCache.resourceDisplay = p.resourceDisplay or "auto"
    settingsCache.maelstromHybridSplit = p.maelstromHybridSplit or 5
    settingsCache.barWidth = p.barWidth or 240
    settingsCache.barHeight = p.barHeight or 18
    settingsCache.secondaryHeight = p.secondaryHeight or 12
    settingsCache.dividerColor = p.dividerColor or "white"

    -- 创建分类
    local category = Settings.RegisterVerticalLayoutCategory("ClassResourceBar")
    if not category then
        Print("|cffff9900无法创建设置分类|r")
        return false
    end

    -- 逐个注册控件: 每个独立 pcall
    local controlErrors = 0
    local function SafeRegister(label, func)
        local ok, err = pcall(func)
        if not ok then
            controlErrors = controlErrors + 1
            Print(string.format("|cffff9900注册 [%s] 失败: %s|r", label, tostring(err)))
        end
    end

    -- 1. 阈值滑块 (50-99%)
    SafeRegister("阈值滑块", function()
        local defaultValue = settingsCache.threshold
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_THRESHOLD",       -- variable (唯一名, 供 GetValue/SetValue)
            "threshold",           -- variableKey (settingsCache 中的键)
            settingsCache,         -- variableTbl (直接读写的表)
            type(defaultValue),    -- variableType ("number")
            "预警阈值 (%)",         -- name (显示名)
            defaultValue           -- defaultValue
        )
        local options = Settings.CreateSliderOptions(50, 99, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, "资源达到此百分比时触发将满预警")
        Settings.SetOnValueChangedCallback("CRB_THRESHOLD", OnSettingChanged)
    end)

    -- 2. 预警样式下拉
    SafeRegister("预警样式", function()
        local defaultValue = settingsCache.alertStyle
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("pulse", "脉冲")
            container:Add("flash", "闪烁")
            container:Add("both", "脉冲 + 闪烁")
            container:Add("none", "关闭")
            return container:GetData()
        end
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_ALERT_STYLE", "alertStyle", settingsCache,
            type(defaultValue), "预警样式", defaultValue)
        Settings.CreateDropdown(category, setting, GetOptions, "选择将满预警的视觉效果")
        Settings.SetOnValueChangedCallback("CRB_ALERT_STYLE", OnSettingChanged)
    end)

    -- 3. 启用音效
    SafeRegister("音效开关", function()
        local defaultValue = settingsCache.sound
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_SOUND", "sound", settingsCache,
            type(defaultValue), "启用预警音效", defaultValue)
        Settings.CreateCheckbox(category, setting, "资源将满时播放提示音")
        Settings.SetOnValueChangedCallback("CRB_SOUND", OnSettingChanged)
    end)

    -- 4. 锁定位置
    SafeRegister("锁定位置", function()
        local defaultValue = settingsCache.locked
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_LOCKED", "locked", settingsCache,
            type(defaultValue), "锁定资源条位置", defaultValue)
        Settings.CreateCheckbox(category, setting, "锁定后无法拖动资源条")
        Settings.SetOnValueChangedCallback("CRB_LOCKED", OnSettingChanged)
    end)

    -- 5. 隐藏原生资源条
    SafeRegister("隐藏原生条", function()
        local defaultValue = settingsCache.hideBlizzard
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_HIDE_BLIZZARD", "hideBlizzard", settingsCache,
            type(defaultValue), "隐藏 Blizzard 资源条", defaultValue)
        Settings.CreateCheckbox(category, setting, "隐藏原生的玩家资源条 (需手动重载界面)")
        Settings.SetOnValueChangedCallback("CRB_HIDE_BLIZZARD", OnSettingChanged)
    end)

    -- 6. 资源显示模式
    SafeRegister("资源显示模式", function()
        local defaultValue = settingsCache.resourceDisplay
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("auto", "自动 (推荐)")
            container:Add("segments", "格子 (独立块)")
            container:Add("hybrid", "混合 (前半连续+后半格子)")
            container:Add("continuous", "连续条")
            return container:GetData()
        end
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_RESOURCE_DISPLAY", "resourceDisplay", settingsCache,
            type(defaultValue), "资源显示模式", defaultValue)
        Settings.CreateDropdown(category, setting, GetOptions,
            "点数型资源 (灵魂碎片/圣能/旋涡值等) 的显示方式。混合模式特别适合增强萨满的旋涡值 (前5连续+后5格子)")
        Settings.SetOnValueChangedCallback("CRB_RESOURCE_DISPLAY", OnSettingChanged)
    end)

    -- 7. 旋涡值混合模式分割点
    SafeRegister("混合模式分割", function()
        local defaultValue = settingsCache.maelstromHybridSplit
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_MAELSTROM_SPLIT", "maelstromHybridSplit", settingsCache,
            type(defaultValue), "混合模式前段格数", defaultValue)
        local options = Settings.CreateSliderOptions(1, 9, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options,
            "混合模式下, 前多少格用连续条显示 (增强萨推荐 5: 前5连续+后5格子)")
        Settings.SetOnValueChangedCallback("CRB_MAELSTROM_SPLIT", OnSettingChanged)
    end)

    -- 8. 资源条宽度
    SafeRegister("资源条宽度", function()
        local defaultValue = settingsCache.barWidth
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_BAR_WIDTH", "barWidth", settingsCache,
            type(defaultValue), "资源条宽度", defaultValue)
        local options = Settings.CreateSliderOptions(80, 600, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, "主资源条的像素宽度")
        Settings.SetOnValueChangedCallback("CRB_BAR_WIDTH", OnSettingChanged)
    end)

    -- 9. 主资源条高度
    SafeRegister("主条高度", function()
        local defaultValue = settingsCache.barHeight
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_BAR_HEIGHT", "barHeight", settingsCache,
            type(defaultValue), "主资源条高度", defaultValue)
        local options = Settings.CreateSliderOptions(4, 60, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, "主资源条的像素高度")
        Settings.SetOnValueChangedCallback("CRB_BAR_HEIGHT", OnSettingChanged)
    end)

    -- 10. 辅资源条高度
    SafeRegister("辅条高度", function()
        local defaultValue = settingsCache.secondaryHeight
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_SECONDARY_HEIGHT", "secondaryHeight", settingsCache,
            type(defaultValue), "辅资源条高度", defaultValue)
        local options = Settings.CreateSliderOptions(4, 40, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options,
            "辅资源条 (连击点/真气等) 的像素高度")
        Settings.SetOnValueChangedCallback("CRB_SECONDARY_HEIGHT", OnSettingChanged)
    end)

    -- 11. 分隔线颜色
    SafeRegister("分隔线颜色", function()
        local defaultValue = settingsCache.dividerColor
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("white", "白色")
            container:Add("black", "黑色")
            container:Add("gray", "灰色")
            container:Add("darkgray", "深灰")
            container:Add("gold", "金色")
            return container:GetData()
        end
        local setting = Settings.RegisterAddOnSetting(category,
            "CRB_DIVIDER_COLOR", "dividerColor", settingsCache,
            type(defaultValue), "分隔线颜色", defaultValue)
        Settings.CreateDropdown(category, setting, GetOptions,
            "格子之间的分隔线颜色")
        Settings.SetOnValueChangedCallback("CRB_DIVIDER_COLOR", OnSettingChanged)
    end)

    -- 注册到 AddOn 设置面板
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
    settingsRegistered = true

    if controlErrors > 0 then
        Print(string.format("|cffff9900设置面板已注册, 但 %d 个控件失败|r", controlErrors))
    else
        Print("|cff00ff00设置面板注册成功|r")
    end
    return true
end

-- 打开设置面板
function Config.OpenSettings()
    if settingsCategory and Settings then
        -- 12.0 用 OpenToCategory(categoryID)
        local id = settingsCategory:GetID()
        if id and Settings.OpenToCategory then
            Settings.OpenToCategory(id)
            return true
        end
        -- fallback
        if Settings.OpenAddOnCategory then
            Settings.OpenAddOnCategory(settingsCategory)
            return true
        end
    end
    return false
end

-- 强制重新注册
function Config.ReRegister()
    settingsRegistered = false
    settingsCategory = nil
    return RegisterSettings()
end

------------------------------------------------------------
-- /crb 命令处理
------------------------------------------------------------

local function HandleSlash(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") or ""  -- trim 前后空白
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "config" or cmd == "options" then
        if not Config.OpenSettings() then
            Print("设置面板未注册, 尝试立即注册...")
            if Config.ReRegister() then
                Config.OpenSettings()
            else
                Print("注册失败, 请使用 /crb help 查看可用命令")
            end
        end
    elseif cmd == "register" then
        Print("手动触发设置面板注册...")
        Config.ReRegister()
    elseif cmd == "lock" then
        ns.Layout.SetLocked(true)
        Print("已锁定资源条位置")
    elseif cmd == "unlock" then
        ns.Layout.SetLocked(false)
        Print("已解锁资源条位置, 可拖动调整")
    elseif cmd == "mem" then
        local report = ns.MemoryManager.Report()
        Print(string.format("当前内存: %.1f KB", report.current))
        Print(string.format("采样数: %d, 区间: %.1f - %.1f KB (波动 %.1f KB)",
            report.samples, report.min, report.max, report.delta))
        Print(report.leaking and "|cffff9900检测到内存增长异常|r" or "|cff00ff00内存稳定|r")
        local stat = ns.BarPool.Stat()
        Print(string.format("BarPool: live=%d free=%d created=%d (上限 %d)",
            stat.live, stat.free, stat.created, stat.maxBars))
    elseif cmd == "test" then
        local pct = tonumber(arg) or 85
        ns.Core.TestPercent(pct / 100)
        Print(string.format("测试模式: 所有条设为 %d%%", pct))
    elseif cmd == "reset" then
        local p = ns.Init.GetProfile()
        if p then
            p.point = { "CENTER", "UIParent", "CENTER", 0, -200 }
            p.threshold = 0.8
            p.alertStyle = "pulse"
            p.scale = 1.0
            ns.Layout.Rebuild()
            Print("已重置布局与阈值")
        end
    elseif cmd == "threshold" then
        local v = tonumber(arg)
        if v then
            if v > 1 then v = v / 100 end
            ns.Alert.SetThreshold(v)
            Print(string.format("阈值已设为 %.0f%%", v * 100))
        else
            Print("用法: /crb threshold <50-99>")
        end
    elseif cmd == "debug" then
        ns.debugMode = not ns.debugMode
        if ns.debugMode then
            Print("|cff00ccff[调试模式已开启]|r 将输出详细日志")
            ns.Debug("调试模式测试: 当前 activeBars:")
            if ns.Layout and ns.Layout.activeBars then
                for k, bar in pairs(ns.Layout.activeBars) do
                    ns.Debug("  key =", k, "bar _id =", bar._id, "IsShown =", bar:IsShown())
                end
            end
        else
            Print("|cff666666[调试模式已关闭]|r")
        end
    elseif cmd == "help" then
        Print("命令列表:")
        Print("  /crb - 打开设置面板")
        Print("  /crb register - 手动注册设置面板")
        Print("  /crb lock|unlock - 锁定/解锁位置")
        Print("  /crb mem - 查看内存使用")
        Print("  /crb test <50-99> - 预览预警效果")
        Print("  /crb threshold <50-99> - 设置阈值")
        Print("  /crb reset - 重置布局")
        Print("  /crb debug - 开启/关闭调试模式")
    else
        Print("未知命令: " .. cmd .. " (使用 /crb help 查看)")
    end
end

-- 注册 slash 命令
SLASH_CLASSRESOURCEBAR1 = "/crb"
SLASH_CLASSRESOURCEBAR2 = "/classresourcebar"
SlashCmdList["CLASSRESOURCEBAR"] = HandleSlash

------------------------------------------------------------
-- 模块生命周期
------------------------------------------------------------

function Config:OnDBReady()
    -- 不在此处注册, 等待 PLAYER_LOGIN
end

function Config:OnLogin()
    -- 延迟 0.5 秒确保 Settings UI 完全加载
    C_Timer.After(0.5, function()
        local ok, err = pcall(RegisterSettings)
        if not ok then
            Print("|cffff9900设置面板注册异常: " .. tostring(err) .. "|r")
        end
    end)
end

ns.modules = ns.modules or {}
ns.modules.Config = Config

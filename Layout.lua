-- ClassResourceBar - Layout.lua
-- 按当前职业/专精排版资源条
-- 切换职业/专精时调用 Rebuild, 从 BarPool 取条, 绝不 CreateFrame

local addonName, ns = ...
local PT = ns.PT

local Layout = {}
ns.Layout = Layout

-- 计算表元素个数 (用于调试)
local function CountTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- 容器 frame (所有 Bar 的 parent)
local container
-- 当前活跃的 powerType → Bar 映射 (供 Core.Flush 查找)
Layout.activeBars = {}

-- 分隔线颜色预设表
local DIVIDER_COLORS = {
    white    = { 1.0, 1.0, 1.0, 1.0 },
    black    = { 0.0, 0.0, 0.0, 1.0 },
    gray     = { 0.5, 0.5, 0.5, 1.0 },
    darkgray = { 0.2, 0.2, 0.2, 1.0 },
    gold     = { 0.9, 0.8, 0.2, 1.0 },
}

-- 获取分隔线颜色 (从 profile 读取预设)
local function GetDividerColor()
    local p = ns.Init.GetProfile()
    local preset = p and p.dividerColor or "white"
    return DIVIDER_COLORS[preset] or DIVIDER_COLORS.white
end

-- 创建容器 (仅一次)
local function EnsureContainer()
    if container then return container end
    container = CreateFrame("Frame", "ClassResourceBarContainer", UIParent, "BackdropTemplate")
    container:SetSize(260, 40)  -- 紧凑尺寸, 仅包住主+辅条
    container:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    -- 启用拖动 (由 /crb unlock 控制)
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:EnableMouse(true)
    container:RegisterForDrag("LeftButton")
    -- 解锁时显示半透明边框, 方便用户看到可拖动区域
    container:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    container:SetBackdropColor(0, 1, 0, 0)
    container:SetBackdropBorderColor(0, 1, 0, 0)
    container:SetScript("OnDragStart", function(self)
        local locked = Layout.IsLocked()
        ns.Debug("OnDragStart: locked =", locked)
        if not locked then self:StartMoving() end
    end)
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Layout.SavePosition()
        ns.Debug("OnDragStop: 位置已保存")
    end)
    ns.Debug("EnsureContainer: 容器已创建, size =", container:GetSize(),
             "EnableMouse =", container:IsMouseEnabled())
    return container
end

-- 更新容器拖动提示边框 (解锁时显示绿色边框, 锁定时透明)
function Layout.UpdateDragHint()
    if not container then return end
    if Layout.IsLocked() then
        container:SetBackdropColor(0, 1, 0, 0)
        container:SetBackdropBorderColor(0, 1, 0, 0)
    else
        container:SetBackdropColor(0, 1, 0, 0.08)
        container:SetBackdropBorderColor(0, 1, 0, 0.8)
    end
end

function Layout.IsLocked()
    local p = ns.Init.GetProfile()
    return p and p.locked or false
end

function Layout.SetLocked(b)
    local p = ns.Init.GetProfile()
    if p then p.locked = (b == true) end
    Layout.UpdateDragHint()
end

-- 保存当前位置到 profile
function Layout.SavePosition()
    if not container then return end
    local point, _, relPoint, x, y = container:GetPoint(1)
    local p = ns.Init.GetProfile()
    if p then
        p.point = { point or "CENTER", "UIParent", relPoint or "CENTER", x or 0, y or 0 }
    end
end

-- 从 profile 恢复位置
local function RestorePosition()
    if not container then return end
    local p = ns.Init.GetProfile()
    if not p or not p.point then return end
    container:ClearAllPoints()
    local t = p.point
    container:SetPoint(t[1] or "CENTER", UIParent, t[3] or "CENTER", t[4] or 0, t[5] or 0)
    if p.scale then container:SetScale(p.scale) end
end

-- 获取容器 (供 Core 在 BarPool.Init 时作为 parent)
function Layout.GetContainer()
    return EnsureContainer()
end

-- 根据当前职业/专精重建布局
function Layout.Rebuild()
    ns.Debug("Layout.Rebuild 开始")
    EnsureContainer()
    RestorePosition()

    -- 检查职业是否启用
    local _, classFile = UnitClass("player")
    ns.Debug("Rebuild: classFile =", classFile)
    if classFile and not ns.PowerDB.IsEnabled(classFile) then
        ns.Debug("Rebuild: 职业", classFile, "未启用, 隐藏")
        ns.BarPool.ReleaseAll()
        Layout.activeBars = {}
        container:Hide()
        return
    end

    local info = ns.PowerDB.Detect()
    ns.Debug("Rebuild: Detect =", info and info.classFile or "nil",
             "primary =", info and info.primary or "nil",
             "secondary =", info and info.secondary or "nil",
             "runeType =", info and info.runeType or "nil")
    if not info then return end
    container:Show()
    ns.Debug("Rebuild: container:Show() 完成, container IsShown =", container:IsShown())

    -- 释放旧条
    ns.BarPool.ReleaseAll()
    wipe(Layout.activeBars)

    -- 主条
    if info.primary ~= nil then
        local bar = ns.BarPool.Acquire("primary")
        ns.Debug("Rebuild: Acquire(primary) =", bar and bar._id or "nil")
        if bar then
            -- 应用 profile 的尺寸
            local p = ns.Init.GetProfile()
            local bw = p and p.barWidth or 240
            local bh = p and p.barHeight or 18
            bar:SetSize(bw, bh)
            bar:ClearAllPoints()
            bar:SetPoint("TOP", container, "TOP", 0, 0)
            bar.powerType = info.primary
            local c = ns.PowerDB.GetColor(info.primary)
            bar:SetColor(c[1], c[2], c[3])
            -- 应用分隔线颜色
            local dc = GetDividerColor()
            bar:SetDividerColor(dc[1], dc[2], dc[3], dc[4])
            local displayPref = p and p.resourceDisplay or "auto"
            local isPoint = ns.PowerDB.IsPointType(info.primary)
            if displayPref == "segments" then
                bar:SetDisplayMode("segments")
            elseif displayPref == "hybrid" then
                bar:SetDisplayMode("hybrid", p and p.maelstromHybridSplit or 5)
            elseif displayPref == "continuous" then
                bar:SetDisplayMode("continuous")
            else -- "auto"
                -- WoW 12.0: 不能用 UnitPowerMax 判断 (返回 secret value)
                -- 用 PowerDB 硬编码常量判断资源类型
                if info.primary == PT.Maelstrom then
                    -- 增强萨满旋涡值: 混合模式
                    bar:SetDisplayMode("hybrid", p and p.maelstromHybridSplit or 5)
                elseif isPoint then
                    bar:SetDisplayMode("segments")
                else
                    bar:SetDisplayMode("continuous")
                end
            end

            Layout.activeBars[info.primary] = bar
            -- pcall 保护: 防止 RefreshBar 错误导致后续辅条无法创建
            pcall(Layout.RefreshBar, info.primary)
            ns.Debug("Rebuild: 主条创建完成, bar IsShown =", bar:IsShown(),
                     "size =", bar:GetSize(), "powerType =", info.primary)
        end
    end

    -- 辅资源条 (ComboPoints/Chi/ArcaneCharges 等, 以及 DK 符文)
    local secondaryType = info.secondary
    -- DK: 符文作为辅资源条, 用 6 格分段显示
    if not secondaryType and info.runeType then
        secondaryType = "runes"
    end
    if secondaryType ~= nil then
        ns.Debug("Rebuild: 尝试创建辅条, secondaryType =", secondaryType,
                 "info.secondary =", info.secondary, "info.runeType =", info.runeType)
        local bar = ns.BarPool.Acquire("secondary")
        if not bar then
            ns.Debug("Rebuild: 辅条 Acquire 返回 nil!")
        end
        if bar then
            -- 辅资源条: 宽度同主条, 高度用 secondaryHeight
            local p = ns.Init.GetProfile()
            local bw = p and p.barWidth or 240
            local sh = p and p.secondaryHeight or 12
            bar:SetSize(bw, sh)
            -- 辅条放在主条下方 (间距 = 主条高度 + 4)
            local mainH = p and p.barHeight or 18
            bar:ClearAllPoints()
            bar:SetPoint("TOP", container, "TOP", 0, -(mainH + 4))
            bar.powerType = secondaryType
            -- DK 符文: 蓝/红/绿混合色; 其他用各自资源色
            local c
            if secondaryType == "runes" then
                c = { 0.4, 0.6, 1.0 }  -- 符文用冷蓝色
            else
                c = ns.PowerDB.GetColor(secondaryType)
            end
            bar:SetColor(c[1], c[2], c[3])
            -- 应用分隔线颜色
            local dc = GetDividerColor()
            bar:SetDividerColor(dc[1], dc[2], dc[3], dc[4])
            local displayPref = p and p.resourceDisplay or "auto"
            if displayPref == "continuous" then
                bar:SetDisplayMode("continuous")
            else
                bar:SetDisplayMode("segments")
            end
            Layout.activeBars[secondaryType] = bar
            -- pcall 保护: 防止辅条 RefreshBar 错误
            pcall(Layout.RefreshBar, secondaryType)
            ns.Debug("Rebuild: 辅条创建完成, bar IsShown =", bar:IsShown(),
                     "size =", bar:GetSize(), "secondaryType =", secondaryType)
        end
    end
    ns.Debug("Layout.Rebuild 完成, activeBars 数量 =", CountTable(Layout.activeBars))
    for k, v in pairs(Layout.activeBars) do
        ns.Debug("  activeBar key =", k, "IsShown =", v:IsShown(), "size =", v:GetSize())
    end

    -- 调整容器尺寸, 仅包住主+辅条 (避免多余空白区域影响拖动体验)
    local p = ns.Init.GetProfile()
    local bw = p and p.barWidth or 240
    local mainH = p and p.barHeight or 18
    local secH = (info.secondary or info.runeType) and (p and p.secondaryHeight or 12) or 0
    local totalH = mainH + (secH > 0 and (4 + secH) or 0)
    container:SetSize(bw, totalH)

    Layout.UpdateDragHint()
end

-- 刷新术士灵魂碎片 (原始值 0-50, 每 10 为一颗)
-- 专属函数: 与 DK 符文/其他资源逻辑完全隔离
function Layout.RefreshSoulShards(bar)
    -- WoW 12.0: UnitPower 返回 secret value, 不能做 math.floor(current/10)
    -- 直接传 0-50 原始值给 StatusBar, 分隔线在 5 等分位置, 视觉等同 0-5 颗
    local current = UnitPower("player", PT.SoulShards, true) or 0
    local max = UnitPowerMax("player", PT.SoulShards, true) or 50
    bar:SetPower(current, max)
end

-- 刷新 DK 符文 (统计 6 颗符文中就绪的数量)
-- 专属函数: 与术士灵魂碎片/其他资源逻辑完全隔离
function Layout.RefreshRunes(bar)
    local max = 6
    local current = 0
    for i = 1, 6 do
        local _, _, ready = GetRuneCooldown(i)
        if ready then current = current + 1 end
    end
    ns.Debug("RefreshRunes: 就绪 =", current, "/", max)
    bar:SetPower(current, max)
end

-- 刷新标准资源 (Mana/Rage/Energy/RunicPower 等, 直接读 display value)
-- 专属函数: 不涉及点数换算或符文遍历
function Layout.RefreshStandard(bar, powerType)
    -- WoW 12.0: UnitPower/UnitPowerMax 返回 secret values
    -- 不能做 if max <= 0 等比较, 直接传给 bar:SetPower
    local current = UnitPower("player", powerType, true) or 0
    local max = UnitPowerMax("player", powerType, true) or 0
    bar:SetPower(current, max)
end

-- 刷新单条 Bar 的数值 (根据 powerType 分发到专属函数)
-- 保持各职业资源逻辑完全隔离, 避免互相干扰
function Layout.RefreshBar(powerType)
    local bar = Layout.activeBars[powerType]
    if not bar then
        ns.Debug("RefreshBar: 未找到 bar, powerType =", powerType)
        return
    end

    if powerType == PT.SoulShards then
        -- 术士灵魂碎片
        Layout.RefreshSoulShards(bar)
    elseif powerType == "runes" then
        -- DK 符文
        Layout.RefreshRunes(bar)
    else
        -- 标准资源 (RunicPower/Mana/Rage/Energy 等)
        Layout.RefreshStandard(bar, powerType)
    end
end

-- 注册模块
ns.modules = ns.modules or {}
ns.modules.Layout = Layout

function Layout:OnEnteringWorld()
    Layout.Rebuild()
end

function Layout:OnLogin()
    Layout.Rebuild()
end

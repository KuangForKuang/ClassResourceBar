-- ClassResourceBar - Bar.lua
-- 单条资源条: StatusBar + 预警动画 + 分段块状显示
-- 动画只创建一次, 之后 Play/Stop 复用 (避免每次触发 CreateTexture)

local addonName, ns = ...
local PT = ns.PT

local Bar = {}
ns.Bar = Bar

-- kind → 尺寸/锚点预设 (供 Layout 使用)
local KIND_PRESETS = {
    primary = { w = 240, h = 18 },
    secondary = { w = 240, h = 12 },
    rune = { w = 36, h = 36 },
}

-- 创建单条 Bar (仅在 BarPool.Init 时调用, 运行时绝不 CreateFrame)
-- parent: 容器 frame
-- kind: "primary" | "secondary" | "rune"
function Bar.Create(parent, kind)
    local preset = KIND_PRESETS[kind] or KIND_PRESETS.primary

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(preset.w, preset.h)
    frame.kind = kind

    -- 背景
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.85)
    frame.bg = bg

    if kind == "rune" then
        -- rune: 纯 Texture
        local statusBar = frame:CreateTexture(nil, "ARTWORK")
        statusBar:SetAllPoints()
        statusBar:SetColorTexture(0.4, 0.4, 0.4, 1.0)
        frame.bar = statusBar
    else
        -- StatusBar (连续值模式 / 混合模式的前半段)
        local statusBar = CreateFrame("StatusBar", nil, frame)
        statusBar:SetAllPoints()
        statusBar:SetMinMaxValues(0, 100)
        statusBar:SetValue(0)
        statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        frame.statusBar = statusBar
        frame.bar = statusBar

        -- 分段块 (点数型资源 / 混合模式的后半段)
        -- 预创建 10 个 segment, 运行时只 Show/Hide + SetTexCoord
        frame.segments = {}
        for i = 1, 10 do
            local seg = frame:CreateTexture(nil, "ARTWORK", nil, 2)
            seg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
            seg:Hide()
            frame.segments[i] = seg
        end
        -- 分段间隔线 (独立子 Frame, 提高帧级别确保始终在最上层渲染)
        local divFrame = CreateFrame("Frame", nil, frame)
        divFrame:SetAllPoints()
        divFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
        frame.dividerFrame = divFrame
        frame.dividers = {}
        for i = 1, 9 do
            local div = divFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            div:SetColorTexture(1, 1, 1, 1.0)
            div:SetSize(3, preset.h)
            div:Hide()
            frame.dividers[i] = div
        end
    end

    -- 边框 (用于预警高亮)
    frame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
    })
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1.0)

    -- 预警叠层 (BlendMode ADD, 平时隐藏)
    local alertOverlay = frame:CreateTexture(nil, "OVERLAY")
    alertOverlay:SetAllPoints()
    alertOverlay:SetColorTexture(1.0, 0.85, 0.0, 0.0)
    alertOverlay:SetBlendMode("ADD")
    alertOverlay:Hide()
    frame.alertOverlay = alertOverlay

    -- 脉冲光晕 (边框外发光, 平时隐藏)
    local pulseGlow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    pulseGlow:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    pulseGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
    pulseGlow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    pulseGlow:SetVertexColor(1.0, 0.6, 0.0, 0.0)
    pulseGlow:SetBlendMode("ADD")
    pulseGlow:Hide()
    frame.pulseGlow = pulseGlow

    -- 数值文字 (默认隐藏, 不再显示 x/max 文本)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 1)
    text:SetText("")
    text:Hide()
    frame.text = text

    -- 一次性动画组 (仅创建, 之后 Play/Stop 复用)
    -- 脉冲: 边框 alpha 0→1→0 循环
    local pulseAg = frame:CreateAnimationGroup()
    local pulseAlpha = pulseAg:CreateAnimation("Alpha")
    pulseAlpha:SetTarget(pulseGlow)
    pulseAlpha:SetFromAlpha(0.0)
    pulseAlpha:SetToAlpha(1.0)
    pulseAlpha:SetDuration(0.5)
    pulseAlpha:SetSmoothing("IN_OUT")
    pulseAg:SetLooping("BOUNCE")
    frame.pulseAnim = pulseAg

    -- 闪烁: alertOverlay alpha 0→1→0, 限次播放 (通过 OnLoop 控制)
    local flashAg = frame:CreateAnimationGroup()
    local flashAlpha = flashAg:CreateAnimation("Alpha")
    flashAlpha:SetTarget(alertOverlay)
    flashAlpha:SetFromAlpha(0.0)
    flashAlpha:SetToAlpha(1.0)
    flashAlpha:SetDuration(0.15)
    flashAlpha:SetSmoothing("IN_OUT")
    flashAg:SetLooping("REPEAT")
    -- 限制 8 次后自动停止
    local flashCount = 0
    flashAg:SetScript("OnLoop", function(_, _)
        flashCount = flashCount + 1
        if flashCount >= 8 then
            flashAg:Stop()
            flashCount = 0
            alertOverlay:Hide()
            pulseGlow:Hide()
        end
    end)
    frame.flashAnim = flashAg
    frame._flashCount = function() return flashCount end

    -- 公开字段
    frame.powerType = nil
    frame.current = 0
    frame.max = 100
    frame.isMaxed = false
    frame.isAlerting = false
    frame.lastUseTick = 0  -- 供 BarPool LRU 使用
    -- 显示模式: "continuous"(连续条) | "segments"(独立格子) | "hybrid"(前半连续+后半格子)
    frame.displayMode = "continuous"
    frame.hybridSplit = 5  -- hybrid 模式: 前面 hybridSplit 个用连续条, 后面用格子
    frame.color = { 0.6, 0.6, 0.6 }
    -- 分隔线颜色 (可由用户配置)
    frame.dividerColor = { 0, 0, 0, 1.0 }

    -- 方法绑定
    frame.SetPower = Bar.SetPower
    frame.SetColor = Bar.SetColor
    frame.ResetVisual = Bar.ResetVisual
    frame.SetDisplayMode = Bar.SetDisplayMode
    frame.SetDividerColor = Bar.SetDividerColor
    frame.RenderSegments = Bar.RenderSegments

    return frame
end

-- 设置显示模式
-- mode: "continuous" | "segments" | "hybrid"
-- split: hybrid 模式下前面连续部分的格数 (默认 5)
function Bar:SetDisplayMode(mode, split)
    self.displayMode = mode or "continuous"
    if split then self.hybridSplit = split end
end

-- 设置分隔线颜色 (r, g, b, a)
function Bar:SetDividerColor(r, g, b, a)
    self.dividerColor = { r or 0, g or 0, b or 0, a or 1.0 }
    -- 立即更新已有 dividers
    if self.dividers then
        local dc = self.dividerColor
        for i = 1, 9 do
            self.dividers[i]:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
        end
    end
end

-- 渲染分段块 (独立格子模式)
-- current, max: 点数值 (整数)
function Bar:RenderSegments(current, max)
    if not self.segments then return end
    if self.kind == "rune" then return end

    local w = self:GetWidth()
    local h = self:GetHeight()
    local gap = 4  -- 块间距 (加粗, 视觉上清晰分隔)
    local totalGap = gap * (max - 1)
    local segW = (w - totalGap) / max
    local cr, cg, cb = self.color[1] or 0.6, self.color[2] or 0.6, self.color[3] or 0.6
    local dc = self.dividerColor or { 1, 1, 1, 1 }

    -- 给每个格子加暗背景 (提升对比度)
    if not self.segmentBgs then self.segmentBgs = {} end

    -- 隐藏 statusBar (纯块状模式)
    if self.displayMode == "segments" and self.statusBar then
        self.statusBar:Hide()
    end

    for i = 1, math.min(max, 10) do
        local seg = self.segments[i]
        if seg then
            local xOff = (i - 1) * (segW + gap)
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", self, "LEFT", xOff, 0)
            seg:SetSize(segW, h)
            if i <= current then
                seg:SetVertexColor(cr, cg, cb, 1.0)
            else
                -- 未激活格子: 暗色填充 (而非透明), 视觉上更清晰
                seg:SetVertexColor(0.08, 0.08, 0.10, 1.0)
            end
            seg:Show()
        end
    end
    -- 隐藏多余的 segment
    for i = max + 1, 10 do
        if self.segments[i] then self.segments[i]:Hide() end
    end
    -- 在格子间隙绘制分隔线 (使用用户配置的颜色)
    if self.dividers then
        for i = 1, 9 do
            local div = self.dividers[i]
            if i < max then
                -- 分隔线位置: 第 i 段右边缘到第 i+1 段左边缘的间隙中心
                local xCenter = i * (segW + gap) - gap / 2
                div:ClearAllPoints()
                div:SetPoint("LEFT", self, "LEFT", xCenter - 1, 0)
                div:SetSize(3, h)
                div:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
                div:Show()
            else
                div:Hide()
            end
        end
    end
end

-- 渲染混合模式: 前半段连续条, 后半段独立格子
-- current, max: 点数值
function Bar:RenderHybrid(current, max)
    if not self.segments or not self.statusBar then return end

    local split = self.hybridSplit or 5
    local w = self:GetWidth()
    local h = self:GetHeight()
    local gap = 4  -- 块间距 (与 segments 模式一致)
    local cr, cg, cb = self.color[1] or 0.6, self.color[2] or 0.6, self.color[3] or 0.6

    -- 前半段: 连续条, 占总宽度的 50%
    local frontW = w * 0.5
    local backMax = max - split
    local backTotalGap = gap * math.max(backMax - 1, 0)
    local backW = w * 0.5 - backTotalGap
    local backSegW = backMax > 0 and (backW / backMax) or 0

    -- 调整 statusBar 尺寸为前半部分
    self.statusBar:ClearAllPoints()
    self.statusBar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.statusBar:SetSize(frontW, h)
    self.statusBar:SetMinMaxValues(0, split)
    self.statusBar:SetValue(math.min(current, split))
    self.statusBar:SetStatusBarColor(cr, cg, cb, 1.0)
    self.statusBar:Show()

    -- 后半段: 独立格子
    for i = 1, math.min(backMax, 10) do
        local seg = self.segments[i]
        if seg then
            local xOff = frontW + (i - 1) * (backSegW + gap)
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", self, "LEFT", xOff, 0)
            seg:SetSize(backSegW, h)
            local segValue = i + split
            if segValue <= current then
                seg:SetVertexColor(cr, cg, cb, 1.0)
            else
                seg:SetVertexColor(0.08, 0.08, 0.10, 1.0)
            end
            seg:Show()
        end
    end
    -- 隐藏多余的 segment
    for i = backMax + 1, 10 do
        if self.segments[i] then self.segments[i]:Hide() end
    end
    -- 在格子间隙绘制分隔线 (使用用户配置的颜色)
    if self.dividers then
        local dc = self.dividerColor or { 1, 1, 1, 1 }
        local divIdx = 1
        -- 连续条与第一格之间
        if divIdx <= 9 and backMax > 0 then
            local div = self.dividers[divIdx]
            div:ClearAllPoints()
            div:SetPoint("LEFT", self, "LEFT", frontW - 2, 0)
            div:SetSize(3, h)
            div:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
            div:Show()
            divIdx = divIdx + 1
        end
        -- 格子之间的分隔线
        for i = 1, backMax - 1 do
            if divIdx > 9 then break end
            local div = self.dividers[divIdx]
            local xCenter = frontW + i * (backSegW + gap) - gap / 2
            div:ClearAllPoints()
            div:SetPoint("LEFT", self, "LEFT", xCenter - 1, 0)
            div:SetSize(3, h)
            div:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
            div:Show()
            divIdx = divIdx + 1
        end
        -- 隐藏多余 dividers
        for i = divIdx, 9 do
            if self.dividers[i] then self.dividers[i]:Hide() end
        end
    end
end

-- 设置资源值
-- WoW 12.0: current/max 可能是 secret values
-- secret values: 只能传给 StatusBar:SetValue/SetMinMaxValues, 不能做算术/比较/存入 frame 字段
function Bar:SetPower(current, max)
    -- lastUseTick 用 GetTime() (非 secret), 供 BarPool LRU
    self.lastUseTick = GetTime()

    -- 检测 current/max 是否为 secret values
    -- 对 secret value 做算术会 error, 用 pcall 检测 (不修改任何状态)
    local canDoMath = pcall(function() return current + max end)

    -- 分段模式: 仅对非 secret 值有效 (如 DK 符文 0-6)
    if canDoMath and self.displayMode == "segments" and self.segments then
        if self.statusBar then self.statusBar:Hide() end
        self:RenderSegments(current, max)
        return
    end

    -- StatusBar 模式 (兼容 secret values: Energy/RunicPower/SoulShards 等)
    if self.statusBar then
        self.statusBar:ClearAllPoints()
        self.statusBar:SetAllPoints()
        self.statusBar:Show()
        -- StatusBar API 接受 secret values, 是 Blizzard 设计的安全显示路径
        self.statusBar:SetMinMaxValues(0, max)
        self.statusBar:SetValue(current)
    end

    -- 隐藏分段纹理
    if self.segments then
        for i = 1, 10 do self.segments[i]:Hide() end
    end

    -- 点数型资源显示分隔线 (max 用 PowerDB 硬编码常量, 非 secret)
    if self.dividers then
        local isPoint = self.powerType and ns.PowerDB.IsPointType(self.powerType)
        local dc = self.dividerColor or { 1, 1, 1, 1 }
        if isPoint then
            local maxVal = ns.PowerDB.GetPointMax(self.powerType) or 5
            local barW = self:GetWidth()
            local segW = barW / maxVal
            for i = 1, 9 do
                local div = self.dividers[i]
                if i < maxVal then
                    div:ClearAllPoints()
                    div:SetPoint("LEFT", self, "LEFT", segW * i - 1, 0)
                    div:SetSize(3, self:GetHeight())
                    div:SetColorTexture(dc[1], dc[2], dc[3], dc[4])
                    div:Show()
                else
                    div:Hide()
                end
            end
        else
            for i = 1, 9 do self.dividers[i]:Hide() end
        end
    end
end

-- 设置主色 (r, g, b 来自 PowerDB.GetColor)
function Bar:SetColor(r, g, b)
    self.color = { r or 0.6, g or 0.6, b or 0.6 }
    if self.kind == "rune" then return end
    if self.statusBar then
        self.statusBar:SetStatusBarColor(self.color[1], self.color[2], self.color[3], 1.0)
    end
end

-- 重置视觉 (Release 时调用): 停止动画, 隐藏 overlay
function Bar:ResetVisual()
    if self.pulseAnim then self.pulseAnim:Stop() end
    if self.flashAnim then self.flashAnim:Stop() end
    if self.alertOverlay then self.alertOverlay:Hide() end
    if self.pulseGlow then self.pulseGlow:Hide() end
    if self.segments then
        for i = 1, 10 do self.segments[i]:Hide() end
    end
    if self.dividers then
        for i = 1, 9 do self.dividers[i]:Hide() end
    end
    self.displayMode = "continuous"
    self.isAlerting = false
    self.isMaxed = false
end

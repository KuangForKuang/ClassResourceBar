-- ClassResourceBar - MemoryManager.lua
-- 周期采样 + 泄漏检测 + 自愈
-- design.md §内存管理: 60s 采样一次, 固定 256 ring buffer, 泄漏才触发 GC

local addonName, ns = ...

local MemoryManager = {}
ns.MemoryManager = MemoryManager

-- 战斗状态标记 (战斗中暂停检测, 避免采样/自愈导致卡顿)
local inCombat = false

-- 固定长度 ring buffer (避免 tinsert 增长)
local RING_SIZE = 256
local ring = {}
local ringIdx = 0

-- 写入 ring (覆盖最旧)
local function RingPush(value)
    ringIdx = (ringIdx % RING_SIZE) + 1
    ring[ringIdx] = value
end

-- 读取最近 N 个样本
local function RingRecent(n)
    n = n or 5
    local result = {}
    local count = 0
    -- 从最新往回取
    for i = 0, RING_SIZE - 1 do
        local idx = ((ringIdx - i - 1) % RING_SIZE) + 1
        local v = ring[idx]
        if v ~= nil then
            table.insert(result, 1, v)  -- 按时间正序
            count = count + 1
            if count >= n then break end
        end
    end
    return result
end

-- 泄漏检测: 最近 5 个样本线性回归斜率 > 4 KB/min
function MemoryManager.DetectLeak()
    local recent = RingRecent(5)
    if #recent < 5 then return false end
    -- 简单线性回归 y = a + b*x
    local n = #recent
    local sumX, sumY, sumXY, sumX2 = 0, 0, 0, 0
    for i = 1, n do
        sumX = sumX + i
        sumY = sumY + recent[i]
        sumXY = sumXY + i * recent[i]
        sumX2 = sumX2 + i * i
    end
    local denom = n * sumX2 - sumX * sumX
    if denom == 0 then return false end
    local slope = (n * sumXY - sumX * sumY) / denom
    -- slope 单位: KB/分钟 (每次采样间隔 60s)
    return slope > 4.0
end

-- 采样一次
function MemoryManager.Sample()
    UpdateAddOnMemoryUsage()
    local mem = GetAddOnMemoryUsage("ClassResourceBar") or 0
    RingPush(mem)

    -- 泄漏检测
    local p = ns.Init and ns.Init.GetGlobal()
    if p and p.memoryGuard ~= false then
        if MemoryManager.DetectLeak() then
            MemoryManager.SelfHeal()
        end
    end
    return mem
end

-- 自愈: 仅在确认泄漏时调用
function MemoryManager.SelfHeal()
    print("|cffff9900[CRB]|r 检测到内存增长异常, 触发自愈")
    -- 1. BarPool.Trim: 释放多余 freeList
    if ns.BarPool and ns.BarPool.Trim then
        ns.BarPool.Trim()
    end
    -- 2. 主动 GC (重操作, 仅此分支触发)
    collectgarbage("collect")
    -- 3. 重新采样
    UpdateAddOnMemoryUsage()
    local mem = GetAddOnMemoryUsage("ClassResourceBar") or 0
    RingPush(mem)
    print("|cffff9900[CRB]|r 自愈完成, 当前内存:", string.format("%.1f KB", mem))
end

-- 获取当前内存
function MemoryManager.GetCurrent()
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage("ClassResourceBar") or 0
end

-- 趋势报告 (供 /crb mem 使用)
function MemoryManager.Report()
    local current = MemoryManager.GetCurrent()
    local recent = RingRecent(10)
    local minVal, maxVal = current, current
    for _, v in ipairs(recent) do
        if v < minVal then minVal = v end
        if v > maxVal then maxVal = v end
    end
    return {
        current = current,
        samples = #recent,
        min = minVal,
        max = maxVal,
        delta = maxVal - minVal,
        leaking = MemoryManager.DetectLeak(),
    }
end

-- DB 就绪后启动定时采样
function MemoryManager:OnDBReady()
    -- 首次采样
    MemoryManager.Sample()
    -- 每 60s 采样一次 (design.md §MemoryManager)
    MemoryManager.ticker = C_Timer.NewTicker(60, function()
        -- 战斗中直接不检测 (避免采样开销和自愈卡顿)
        if inCombat then return end
        MemoryManager.Sample()
    end)
    -- 监听战斗状态 (战斗中暂停检测, 战斗结束后等下次 ticker 自然触发)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")  -- 进入战斗
    f:RegisterEvent("PLAYER_REGEN_ENABLED")   -- 脱离战斗
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            -- 不立即采样, 等下次 60s ticker 自然触发
        end
    end)
end

-- 注销前最后一次采样
function MemoryManager:OnLogout()
    local g = ns.Init and ns.Init.GetGlobal()
    if g then
        g.lastSession = {
            mem = MemoryManager.GetCurrent(),
            time = time(),
        }
    end
end

ns.modules = ns.modules or {}
ns.modules.MemoryManager = MemoryManager

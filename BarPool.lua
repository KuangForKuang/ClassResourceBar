-- ClassResourceBar - BarPool.lua
-- 对象池: 启动期一次性预创建 8 条 Bar, 运行时绝不 CreateFrame
-- 满足 design.md §内存管理: 零运行时分配, 复用不新建

local addonName, ns = ...

local BarPool = {}
ns.BarPool = BarPool

-- 池状态
local pool = {
    all = {},         -- 全部创建过的 Bar (用于 Stat 统计, 固定大小)
    freeList = {},    -- 空闲 Bar
    live = {},        -- 活跃 Bar (kind → Bar 引用表)
    container = nil,  -- 容器 frame (所有 Bar 的 parent)
    created = 0,
    acquireCount = 0,
}

-- 最大并发条数 (design.md §内存管理: DK 主+3符文组+辅=8)
local MAX_BARS = 8

-- 初始化 (在 Init.OnDBReady 后由 Core 调用)
function BarPool.Init(parent)
    pool.container = parent or UIParent
    ns.Debug("BarPool.Init: parent =", pool.container, pool.container:GetName() or "nil")
    pool.all = {}
    pool.freeList = {}
    pool.live = {}
    pool.created = 0

    for i = 1, MAX_BARS do
        -- 默认按 primary 创建, Acquire 时可改 kind
        local bar = ns.Bar.Create(pool.container, "primary")
        bar._id = i
        bar:Hide()
        pool.all[i] = bar
        pool.freeList[i] = bar
        pool.created = pool.created + 1
    end
    ns.Debug("BarPool.Init: 创建了", pool.created, "条 Bar, parent =", pool.container:GetName())
end

-- 取一条 Bar
-- kind: "primary" | "secondary" | "rune"
-- 返回 Bar 或 nil (理论不会 nil, 因为有 LRU 兜底)
function BarPool.Acquire(kind)
    kind = kind or "primary"
    pool.acquireCount = pool.acquireCount + 1

    local bar = table.remove(pool.freeList)
    if not bar then
        -- freeList 空: 复用最少使用的活跃 Bar (LRU)
        local oldest, oldestKey, oldestTick = nil, nil, math.huge
        for k, b in pairs(pool.live) do
            if b.lastUseTick < oldestTick then
                oldest, oldestKey, oldestTick = b, k, b.lastUseTick
            end
        end
        if oldest then
            oldest:ResetVisual()
            oldest:Hide()
            pool.live[oldestKey] = nil
            bar = oldest
        end
    end

    if not bar then return nil end

    -- 重新配置 kind (尺寸)
    bar.kind = kind
    local preset
    if kind == "primary" then
        preset = { 240, 18 }
    elseif kind == "secondary" then
        preset = { 240, 12 }
    elseif kind == "rune" then
        preset = { 36, 36 }
    end
    bar:SetSize(preset[1], preset[2])

    -- 注册到 live 表 (用 acquireCount 作为 key 避免冲突)
    pool.live[pool.acquireCount] = bar
    bar._liveKey = pool.acquireCount

    bar:Show()

    -- 确保分隔线始终在最上层 (WoW 可能在战斗中自动调整 frameLevel)
    if bar.dividerFrame then
        bar.dividerFrame:SetFrameLevel(bar:GetFrameLevel() + 5)
    end

    return bar
end

-- 归还 Bar
function BarPool.Release(bar)
    if not bar then return end
    bar:ResetVisual()
    bar:Hide()
    bar.powerType = nil
    -- 从 live 移除
    if bar._liveKey then
        pool.live[bar._liveKey] = nil
        bar._liveKey = nil
    end
    -- 加入 freeList (避免重复入队)
    for _, b in ipairs(pool.freeList) do
        if b == bar then return end
    end
    table.insert(pool.freeList, bar)
end

-- 释放所有 live Bar (切换职业/专精时使用)
function BarPool.ReleaseAll()
    for k, bar in pairs(pool.live) do
        bar:ResetVisual()
        bar:Hide()
        bar.powerType = nil
        bar._liveKey = nil
        table.insert(pool.freeList, bar)
    end
    pool.live = {}
end

-- 返回当前所有 live Bar 的迭代器 (供 Core.Flush 使用)
function BarPool.EachLive()
    return pairs(pool.live)
end

-- 统计 (供 /crb mem 使用)
function BarPool.Stat()
    local live = 0
    for _ in pairs(pool.live) do live = live + 1 end
    local free = 0
    for _ in ipairs(pool.freeList) do free = free + 1 end
    return {
        live = live,
        free = free,
        created = pool.created,
        maxBars = MAX_BARS,
        acquireTotal = pool.acquireCount,
    }
end

-- 极端情况: 释放未被引用的 freeList 项 (MemoryManager 泄漏自愈调用)
-- 正常流程不调用, 仅 design.md §6.2 泄漏分支触发
function BarPool.Trim()
    -- 保留最近 MAX_BARS 个 freeList 项, 其余销毁 (下次需要时会重建)
    while #pool.freeList > MAX_BARS do
        local bar = table.remove(pool.freeList)
        -- 从 all 移除
        for i, b in ipairs(pool.all) do
            if b == bar then
                table.remove(pool.all, i)
                break
            end
        end
        pool.created = pool.created - 1
    end
end

-- 注册到 Init 模块系统
ns.modules = ns.modules or {}
ns.modules.BarPool = BarPool

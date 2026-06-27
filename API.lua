-- ClassResourceBar - API.lua
-- 对外公开接口 (供其他插件/Macro 调用)
-- design.md §公开 API

local addonName, ns = ...

local addonTable = ns
addonTable.API_VERSION = "0.1.0"

-- 获取指定 powerType 的资源信息
-- powerType: Enum.PowerType 值
-- 返回 { current, max, pct } 或 nil
function addonTable.GetPowerInfo(powerType)
    if powerType == nil then return nil end
    -- WoW 12.0: unmodified=true 返回 secret-safe 值
    local current = UnitPower("player", powerType, true) or 0
    local max = UnitPowerMax("player", powerType, true) or 0
    if max <= 0 then return nil end

    -- 灵魂碎片 unmodified 0-50
    if powerType == ns.PT.SoulShards then
        current = math.floor(current / 10)
        max = math.floor(max / 10)
    end

    return {
        current = current,
        max = max,
        pct = current / max,
    }
end

-- 设置预警阈值 (0.5–0.99)
function addonTable.SetThreshold(pct)
    ns.Alert.SetThreshold(pct)
end

function addonTable.GetThreshold()
    return ns.Alert.GetThreshold()
end

-- 启用/禁用预警
function addonTable.SetAlertEnabled(b)
    ns.Alert.SetEnabled(b)
end

-- 获取内存使用 (KB)
function addonTable.GetMemoryUsage()
    return ns.MemoryManager.GetCurrent()
end

-- 获取内存趋势
function addonTable.GetMemoryReport()
    return ns.MemoryManager.Report()
end

-- 注册回调
-- event: "ThresholdReached" | "MaxedOut" | "PowerNormalized"
function addonTable.RegisterCallback(event, func)
    ns.Alert.RegisterCallback(event, func)
end

function addonTable.UnregisterCallback(event, func)
    ns.Alert.UnregisterCallback(event, func)
end

-- 获取 BarPool 统计
function addonTable.GetBarPoolStat()
    return ns.BarPool.Stat()
end

-- 全局命名空间 (供 /run ClassResourceBar.xxx 调用)
_G[addonName] = addonTable

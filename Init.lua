-- ClassResourceBar - Init.lua
-- SavedVariables 初始化与生命周期管理
-- 遵守 cheat-sheet Mistake 10: 在 PLAYER_LOGIN / ADDON_LOADED 之前不访问任何 API

local addonName, ns = ...

-- 命名空间 (所有模块共享)
ns.DB = ns.DB or nil           -- ClassResourceBarDB 引用 (Init 后可用)
ns.profile = ns.profile or nil -- 当前角色 profile
ns.global = ns.global or nil   -- 账号 global
ns.modules = ns.modules or {}  -- 各模块自注册

local Init = {}
ns.Init = Init

-- 调试模式开关 (通过 /crb debug 切换)
ns.debugMode = false

-- 调试输出函数 (所有模块共享)
-- 用法: ns.Debug("消息", value1, value2, ...)
function ns.Debug(msg, ...)
    if not ns.debugMode then return end
    local prefix = "|cff00ccff[CRB-DBG]|r "
    if select('#', ...) > 0 then
        print(prefix .. tostring(msg), ...)
    else
        print(prefix .. tostring(msg))
    end
end

-- 默认配置 (design.md §SavedVariables)
local DEFAULTS = {
    profile = {
        point = { "CENTER", "UIParent", "CENTER", 0, -200 },
        size = { 240, 18 },
        barWidth = 240,       -- 主资源条宽度
        barHeight = 18,       -- 主资源条高度
        secondaryHeight = 12, -- 辅资源条高度
        -- 分隔线颜色预设: "white" | "black" | "gray" | "darkgray" | "gold"
        dividerColor = "white",
        threshold = 0.8,
        alertStyle = "pulse", -- "pulse" | "flash" | "both" | "none"
        sound = true,
        hideBlizzard = false,
        locked = false,
        scale = 1.0,
        -- 资源显示模式: "auto"(按资源类型自动) | "segments"(格子) | "hybrid"(混合) | "continuous"(连续)
        resourceDisplay = "auto",
        -- 增强萨满混合模式: 前段连续显示的格数 (后段独立格子)
        maelstromHybridSplit = 5,
        classes = {
            WARRIOR = true, HUNTER = true, ROGUE = true, PRIEST = true,
            DEATHKNIGHT = true, PALADIN = true, MAGE = true, WARLOCK = true,
            DRUID = true, MONK = true, DEMONHUNTER = true, SHAMAN = true,
            EVOKER = true,
        },
    },
    global = {
        memoryGuard = true,
        lastSession = nil,
    },
}

-- 深度合并: 把 defaults 中缺失的键补到 saved 中, 不覆盖已有值
local function MergeDefaults(saved, defaults)
    if type(saved) ~= "table" then saved = {} end
    if type(defaults) ~= "table" then return saved end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if saved[k] == nil then
                saved[k] = {}
            end
            if type(saved[k]) == "table" then
                MergeDefaults(saved[k], v)
            end
        else
            if saved[k] == nil then
                saved[k] = v
            end
        end
    end
    return saved
end
Init.MergeDefaults = MergeDefaults

-- 返回当前角色 profile (供其他模块调用)
function Init.GetProfile()
    return ns.profile
end

function Init.GetGlobal()
    return ns.global
end

-- 每角色 profile 分桶键 (account-level SV 内部按角色隔离)
local function ProfileKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or "?")
end
Init.ProfileKey = ProfileKey

-- 事件帧
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        -- 此时 ClassResourceBarDB 已从磁盘加载 (可能为 nil)
        ClassResourceBarDB = ClassResourceBarDB or {}
        ns.DB = ClassResourceBarDB

        -- 合并 global
        MergeDefaults(ClassResourceBarDB, DEFAULTS)
        ns.global = ClassResourceBarDB.global

        -- 初始化当前角色 profile 桶
        local key = ProfileKey()
        ClassResourceBarDB.profiles = ClassResourceBarDB.profiles or {}
        if ClassResourceBarDB.profiles[key] == nil then
            ClassResourceBarDB.profiles[key] = {}
        end
        MergeDefaults(ClassResourceBarDB.profiles[key], DEFAULTS.profile)
        ns.profile = ClassResourceBarDB.profiles[key]

        -- 通知所有模块 DB 就绪
        for _, mod in pairs(ns.modules) do
            if mod.OnDBReady then mod:OnDBReady() end
        end
    elseif event == "PLAYER_LOGIN" then
        -- 通知模块玩家登录
        for _, mod in pairs(ns.modules) do
            if mod.OnLogin then mod:OnLogin() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _, mod in pairs(ns.modules) do
            if mod.OnEnteringWorld then mod:OnEnteringWorld() end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- 最后一次内存采样
        for _, mod in pairs(ns.modules) do
            if mod.OnLogout then mod:OnLogout() end
        end
    end
end)

-- ClassResourceBar - PowerDB.lua
-- 职业/专精 → PowerType 映射表
-- 完整覆盖 13 职业 / 18 种玩家可用 PowerType
-- 注意: DK 符文使用新枚举 RuneBlood(20)/RuneFrost(21)/RuneUnholy(22)

local addonName, ns = ...

-- Enum.PowerType 常量 (从 warcraft.wiki.gg 确认)
local PT = {
    Mana           = 0,
    Rage           = 1,
    Focus          = 2,
    Energy         = 3,
    ComboPoints    = 4,
    RunicPower     = 6,
    SoulShards     = 7,
    LunarPower     = 8,
    HolyPower      = 9,
    Maelstrom      = 11,
    Chi            = 12,
    Insanity       = 13,
    ArcaneCharges  = 16,
    Fury           = 17,
    Pain           = 18,
    Essence        = 19,
    RuneBlood      = 20,
    RuneFrost      = 21,
    RuneUnholy     = 22,
}

local PowerDB = {}
ns.PowerDB = PowerDB
ns.PT = PT

-- 点数型资源 (max 小, 阈值用绝对值 max-1)
local POINT_TYPES = {
    [PT.ComboPoints]   = true,
    [PT.SoulShards]    = true,
    [PT.HolyPower]     = true,
    [PT.Chi]           = true,
    [PT.Essence]       = true,
    [PT.ArcaneCharges] = true,
}
PowerDB.IsPointType = function(pt) return POINT_TYPES[pt] == true end

-- 点数型资源的已知最大值 (非 secret, 硬编码常量)
-- 用于分隔线定位, 因为 UnitPowerMax 返回 secret value
local POINT_MAX = {
    [PT.ComboPoints]   = 5,  -- 部分天赋可到 6-8, 但 5 是基础值
    [PT.SoulShards]    = 5,
    [PT.HolyPower]     = 5,
    [PT.Chi]           = 5,
    [PT.Essence]       = 5,
    [PT.ArcaneCharges] = 4,
}
PowerDB.GetPointMax = function(pt) return POINT_MAX[pt] end

-- 资源默认颜色 (design.md §预警; 取自 Power colors wiki)
local POWER_COLORS = {
    [PT.Mana]          = { 0.00, 0.00, 1.00 },
    [PT.Rage]          = { 1.00, 0.00, 0.00 },
    [PT.Focus]         = { 1.00, 0.50, 0.00 },
    [PT.Energy]        = { 1.00, 1.00, 0.00 },
    [PT.ComboPoints]   = { 1.00, 0.50, 0.00 },
    [PT.RunicPower]    = { 0.00, 0.82, 1.00 },
    [PT.SoulShards]    = { 0.50, 0.00, 0.78 },
    [PT.LunarPower]    = { 0.40, 0.60, 0.90 },
    [PT.HolyPower]     = { 1.00, 0.95, 0.30 },
    [PT.Maelstrom]     = { 0.00, 0.50, 1.00 },
    [PT.Chi]           = { 0.30, 1.00, 0.40 },
    [PT.Insanity]      = { 0.55, 0.10, 0.65 },
    [PT.ArcaneCharges] = { 0.50, 0.50, 1.00 },
    [PT.Fury]          = { 0.80, 0.30, 0.30 },
    [PT.Pain]          = { 0.55, 0.20, 0.60 },
    [PT.Essence]       = { 0.40, 0.60, 1.00 },
    [PT.RuneBlood]     = { 1.00, 0.20, 0.20 },
    [PT.RuneFrost]     = { 0.20, 0.60, 1.00 },
    [PT.RuneUnholy]    = { 0.20, 0.90, 0.20 },
}
PowerDB.GetColor = function(pt) return POWER_COLORS[pt] or { 0.6, 0.6, 0.6 } end

-- 字符串 token → 数值 PowerType 转换
-- UNIT_POWER_UPDATE 事件可能传入字符串 (如 "SOUL_SHARDS") 或数值
local TOKEN_TO_TYPE = {
    ["MANA"]           = PT.Mana,
    ["RAGE"]           = PT.Rage,
    ["FOCUS"]          = PT.Focus,
    ["ENERGY"]         = PT.Energy,
    ["COMBO_POINTS"]   = PT.ComboPoints,
    ["RUNIC_POWER"]    = PT.RunicPower,
    ["SOUL_SHARDS"]    = PT.SoulShards,
    ["LUNAR_POWER"]    = PT.LunarPower,
    ["HOLY_POWER"]     = PT.HolyPower,
    ["MAELSTROM"]      = PT.Maelstrom,
    ["CHI"]            = PT.Chi,
    ["INSANITY"]       = PT.Insanity,
    ["ARCANE_CHARGES"] = PT.ArcaneCharges,
    ["FURY"]           = PT.Fury,
    ["PAIN"]           = PT.Pain,
    ["ESSENCE"]        = PT.Essence,
}
PowerDB.TokenToType = function(token) return TOKEN_TO_TYPE[token] end

-- classFile → specID(1..N) → { primary, secondary, runeType }
-- specID 为 nil 表示该职业全部 spec 通用
-- secondary 为 nil 表示无辅资源
-- runeType 仅 DK 使用: "blood"|"frost"|"unholy"
local MAP = {
    WARRIOR = {
        [1] = { primary = PT.Rage },   -- Arms
        [2] = { primary = PT.Rage },   -- Fury
        [3] = { primary = PT.Rage },   -- Protection
    },
    HUNTER = {
        [1] = { primary = PT.Focus },  -- Beast Mastery
        [2] = { primary = PT.Focus },  -- Marksmanship
        [3] = { primary = PT.Focus },  -- Survival
    },
    ROGUE = {
        [1] = { primary = PT.Energy, secondary = PT.ComboPoints }, -- Assassination
        [2] = { primary = PT.Energy, secondary = PT.ComboPoints }, -- Outlaw
        [3] = { primary = PT.Energy, secondary = PT.ComboPoints }, -- Subtlety
    },
    PRIEST = {
        [1] = { primary = PT.Mana },   -- Discipline
        [2] = { primary = PT.Mana },   -- Holy
        [3] = { primary = PT.Insanity }, -- Shadow
    },
    DEATHKNIGHT = {
        [1] = { primary = PT.RunicPower, runeType = "blood"  }, -- Blood
        [2] = { primary = PT.RunicPower, runeType = "frost"  }, -- Frost
        [3] = { primary = PT.RunicPower, runeType = "unholy" }, -- Unholy
    },
    PALADIN = {
        [1] = { primary = PT.Mana },     -- Holy
        [2] = { primary = PT.Mana },     -- Protection
        [3] = { primary = PT.HolyPower }, -- Retribution
    },
    MAGE = {
        [1] = { primary = PT.Mana, secondary = PT.ArcaneCharges }, -- Arcane
        [2] = { primary = PT.Mana }, -- Fire
        [3] = { primary = PT.Mana }, -- Frost
    },
    WARLOCK = {
        [1] = { primary = PT.SoulShards }, -- Affliction
        [2] = { primary = PT.SoulShards }, -- Demonology
        [3] = { primary = PT.SoulShards }, -- Destruction
    },
    DRUID = {
        [1] = { primary = PT.Mana },                              -- Balance → 实际 LunarPower, 在 Detect 中处理形态
        [2] = { primary = PT.Energy, secondary = PT.ComboPoints },-- Feral
        [3] = { primary = PT.Rage },                              -- Guardian
        [4] = { primary = PT.Mana },                              -- Restoration
    },
    MONK = {
        [1] = { primary = PT.Mana },                            -- Brewmaster (实为 Energy+Stagger, 简化)
        [2] = { primary = PT.Energy, secondary = PT.Chi },      -- Windwalker (spec 2)
        [3] = { primary = PT.Mana },                            -- Mistweaver
    },
    DEMONHUNTER = {
        [1] = { primary = PT.Fury },  -- Havoc
        [2] = { primary = PT.Pain },  -- Vengeance
    },
    SHAMAN = {
        [1] = { primary = PT.Maelstrom }, -- Elemental
        [2] = { primary = PT.Maelstrom }, -- Enhancement
        [3] = { primary = PT.Mana },      -- Restoration
    },
    EVOKER = {
        [1] = { primary = PT.Essence }, -- Devastation
        [2] = { primary = PT.Essence }, -- Preservation
        [3] = { primary = PT.Essence }, -- Augmentation
    },
}

-- Druid Balance 实际使用 LunarPower
-- 在 Detect 中处理形态切换, 这里提供静态映射
local DRUID_FORM_OVERRIDE = {
    balance = PT.LunarPower,
}

-- 查表入口: classFile + specID
-- 返回 { primary=, secondary=, runeType= } 或 nil
function PowerDB.Get(classFile, specID)
    local cls = MAP[classFile]
    if not cls then return nil end
    local entry = cls[specID] or cls[1]
    if not entry then return nil end
    -- 返回浅拷贝, 避免外部修改污染
    return {
        primary = entry.primary,
        secondary = entry.secondary,
        runeType = entry.runeType,
    }
end

-- 自动探测当前玩家资源信息
-- 调用 UnitClass / GetSpecialization / GetSpecializationInfo
function PowerDB.Detect()
    local _, classFile = UnitClass("player")
    if not classFile then return nil end

    local specIdx = GetSpecialization()
    if not specIdx then return nil end
    local specID, specName = GetSpecializationInfo(specIdx)
    if not specID then return nil end

    local info = PowerDB.Get(classFile, specIdx)
    if not info then return nil end

    -- Druid Balance 形态覆盖: 实际进入 Moonkin 才显示 LunarPower
    if classFile == "DRUID" and specIdx == 1 then
        local shapeshift = GetShapeshiftFormID()
        -- MOONKIN_FORM = 31
        if shapeshift == 31 then
            info.primary = PT.LunarPower
        end
    end

    info.classFile = classFile
    info.specID = specID
    info.specName = specName
    return info
end

-- 返回当前职业是否启用 (profile.classes 过滤)
function PowerDB.IsEnabled(classFile)
    local p = ns.Init and ns.Init.GetProfile()
    if not p or not p.classes then return true end
    return p.classes[classFile] ~= false
end

-- Pure logic, no game API: tests/logic_test.lua runs this file under plain luajit.
local _, ns = ...

-- Main attack per class, first one known wins. Classic rank-1 IDs; checks go by spell name,
-- so the highest rank known is what the game measures.
ns.CLASS_SPELLS = {
    DRUID = { 5176 },          -- Wrath
    HUNTER = { 75 },           -- Auto Shot
    MAGE = { 133, 116 },       -- Fireball, Frostbolt
    PALADIN = { 6603 },        -- Attack
    PRIEST = { 585, 589 },     -- Smite, Shadow Word: Pain
    ROGUE = { 1752, 6603 },    -- Sinister Strike, Attack
    SHAMAN = { 403 },          -- Lightning Bolt
    WARLOCK = { 686, 172 },    -- Shadow Bolt, Corruption
    WARRIOR = { 78, 6603 },    -- Heroic Strike, Attack
}

-- The unit is somewhere in [minRange, maxRange); maxRange nil means "further than minRange".
-- Returns true (in range), false (out), "edge" (the bracket straddles the limit) or nil (no data).
function ns.Classify(minRange, maxRange, limit)
    if not minRange or not limit then return nil end
    if maxRange and maxRange <= limit then return true end
    if minRange >= limit then return false end
    return "edge"
end

function ns.FormatRange(minRange, maxRange)
    if not minRange then return "--" end
    if not maxRange then return minRange .. "+" end
    return minRange .. "\226\128\147" .. maxRange -- en dash
end

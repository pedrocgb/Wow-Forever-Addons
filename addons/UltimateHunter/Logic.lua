-- Pure swing math, no game API: tests/logic_test.lua runs this file under plain luajit.
local _, ns = ...

ns.modules = {} -- apply functions, one per module; Options calls them all on any setting change

ns.AIM = 0.5 -- Auto Shot needs this long standing still before it fires (Forever beta patch note)

-- 0..1 through the swing.
function ns.Progress(now, start, dur)
	if dur <= 0 then return 1 end
	local p = (now - start) / dur
	return p < 0 and 0 or p > 1 and 1 or p
end

-- Latest moment to be standing still so the next Auto Shot fires right when the swing ends.
function ns.StopAt(start, dur, lead)
	return math.max(start, start + dur - lead)
end

-- go: free to move | still: stand still now | late: moving in the aim window, shot will be delayed
-- held: swing over but moving, the shot waits | ready: swing over and standing, shot is coming
function ns.RangedPhase(now, start, dur, lead, moving)
	if now < ns.StopAt(start, dur, lead) then return "go" end
	if now < start + dur then return moving and "late" or "still" end
	return moving and "held" or "ready"
end

-- Haste changed mid-swing: keep the fraction already done, stretch what is left. Returns start, dur.
function ns.Rescale(now, start, dur, newDur)
	return now - ns.Progress(now, start, dur) * newDur, newDur
end

-- "AARRGGBB" (what the Settings colour swatch stores) -> r, g, b, a in 0..1. Bad input reads as white.
function ns.Hex(hex)
	local a, r, g, b = tostring(hex):match("^(%x%x)(%x%x)(%x%x)(%x%x)$")
	if not a then return 1, 1, 1, 1 end
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, tonumber(a, 16) / 255
end

---------------------------------------------------------------------------
-- Summon Hawk trackers: array of { start, dur, castAt, landed, id }
-- id is the hawk's GUID once we have seen the unit (nameplate, mouseover, target).
---------------------------------------------------------------------------

ns.HAWK_DURATION = 18
ns.HAWK_MAX = 2     -- the game keeps two hawks; a third replaces the oldest
ns.HAWK_WINDOW = 3  -- seconds after a cast in which a new hawk can still show up

local function oldest(hawks, unmatchedOnly)
	local best
	for _, h in ipairs(hawks) do
		if not (unmatchedOnly and h.id) and (not best or h.start < best.start) then best = h end
	end
	return best
end

-- Cast: a new tracker, or the oldest one reused. Timed from the cast until the hawk lands.
function ns.HawkCast(hawks, now)
	local h = oldest(hawks)
	if #hawks < ns.HAWK_MAX then
		local used = {}
		for _, o in ipairs(hawks) do used[o.num] = true end
		local num = 1
		while used[num] do num = num + 1 end
		h = { num = num } -- lowest free number; a replaced hawk keeps the number it replaces
		hawks[#hawks + 1] = h
	end
	h.start, h.dur, h.castAt, h.landed, h.id = now, ns.HAWK_DURATION, now, nil, nil
	return h
end

-- Newest hawk cast in the last HAWK_WINDOW seconds that is still missing `key` ("landed" or "id").
local function recent(hawks, now, key)
	local best
	for _, h in ipairs(hawks) do
		if not h[key] and now - h.castAt <= ns.HAWK_WINDOW and (not best or h.castAt > best.castAt) then best = h end
	end
	return best
end

-- True while a cast is still waiting for its hawk to show up.
function ns.HawkExpected(hawks, now)
	return recent(hawks, now, "id") ~= nil
end

-- The hawk hit its target (the triggered summon spell): its 18 s start now.
function ns.HawkLand(hawks, now)
	local h = recent(hawks, now, "landed")
	if h then h.start, h.landed = now, true end
	return h
end

-- One of our hawk units was seen. A fresh one belongs to the latest cast (and lands it if nothing
-- else did); an older one is matched to the oldest tracker without a unit.
function ns.HawkSeen(hawks, now, id)
	for _, h in ipairs(hawks) do
		if h.id == id then return h end
	end
	local h = recent(hawks, now, "id")
	if h and not h.landed then h.start, h.landed = now, true end
	-- shortcut: a hawk first seen late (mouseover) with two unmatched trackers may pair with the
	-- wrong one; only the removal on death can be off, never the count. Nameplates avoid it.
	h = h or oldest(hawks, true)
	if h then h.id = id end
	return h
end

-- A unit died. Ours by GUID is exact; with `fallback` (a hawk NPC we can't place, nobody else
-- around) the oldest unmatched tracker goes. Returns true when a tracker was removed.
function ns.HawkDied(hawks, id, fallback)
	local h
	for _, o in ipairs(hawks) do
		if o.id == id then h = o end
	end
	h = h or (fallback and oldest(hawks, true))
	if not h then return false end
	for i = #hawks, 1, -1 do
		if hawks[i] == h then table.remove(hawks, i) end
	end
	return true
end

-- Drops finished trackers. Returns true when any was removed.
function ns.HawkExpire(hawks, now)
	local removed
	for i = #hawks, 1, -1 do
		if now >= hawks[i].start + hawks[i].dur then
			table.remove(hawks, i)
			removed = true
		end
	end
	return removed
end

---------------------------------------------------------------------------
-- Ammo
---------------------------------------------------------------------------

-- Low-ammo alert fires once per drop to `warnAt` and re-arms after restocking above it.
-- Returns fire, armed.
function ns.AmmoAlert(armed, total, warnAt)
	if total > warnAt then return false, true end
	return armed, false
end

---------------------------------------------------------------------------
-- Pet training (reads ns.PetData at call time; PetData.lua loads after this file)
---------------------------------------------------------------------------

local function petData() return ns.PetData or {} end

function ns.PetCanLearn(familyID, ability)
	local f = (petData().families or {})[familyID]
	if not f then return false end
	for _, a in ipairs(f.abilities or {}) do
		if a == ability then return true end
	end
	return false
end

-- Returns rank, entry; or nil, "max" (maxed/unknown ability); or nil, "level", rank, entry.
function ns.PetNextRank(ability, knownRank, petLevel)
	local a = (petData().abilities or {})[ability]
	local k = (knownRank or 0) + 1
	local r = a and a.ranks and a.ranks[k]
	if not r then return nil, "max" end
	if petLevel and r.level and petLevel < r.level then return nil, "level", k, r end
	return k, r
end

-- What a beast teaches: recorded in game when tamed (Forever truth) beats the shipped Classic data.
local function teachesList(npcID, beast)
	local rec = ns.db and ns.db.tamed and ns.db.tamed[npcID]
	if rec then return rec, true end
	return beast and beast.teaches, false
end

-- known ranks of a freshly tamed pet -> teaches list; trainer-only skills aren't learned from beasts.
-- shortcut: Forever-only spells missing from PetData (e.g. Faster Attack) are not recorded; add them to the harvest to record them.
function ns.PetTamedTeaches(knownRanks)
	local out, abilities = {}, petData().abilities or {}
	for name, rank in pairs(knownRanks or {}) do
		if abilities[name] and abilities[name].taught ~= "trainer" then out[#out + 1] = { name, rank } end
	end
	table.sort(out, function(x, y) return x[1] < y[1] end)
	return out
end

local function teaches(npcID, beast, ability, rank)
	for _, t in ipairs(teachesList(npcID, beast) or {}) do
		if t[1] == ability and t[2] == rank then return true end
	end
	return false
end

-- filter: { minLvl, maxLvl (level range overlap), zone, family, rareOnly }
function ns.PetBeastsFor(ability, rank, filter)
	local f, out = filter or {}, {}
	for npc, b in pairs(petData().beasts or {}) do
		local lo, hi = b.min or b.max or 0, b.max or b.min or 0
		if teaches(npc, b, ability, rank)
			and (not f.minLvl or hi >= f.minLvl)
			and (not f.maxLvl or lo <= f.maxLvl)
			and (not f.zone or b.zone == f.zone)
			and (not f.family or b.family == f.family)
			and (not f.rareOnly or b.rare) then
			out[#out + 1] = { npc = npc, beast = b }
		end
	end
	table.sort(out, function(x, y)
		local a, b = x.beast.min or 0, y.beast.min or 0
		if a ~= b then return a < b end
		return (x.beast.name or "") < (y.beast.name or "")
	end)
	return out
end

-- Returns lines, confirmed (true when recorded from a tame in game).
function ns.PetTeachesText(npcID, knownRanks, familyID)
	local list, confirmed = teachesList(npcID, (petData().beasts or {})[npcID])
	if not list or #list == 0 then return nil end
	knownRanks = knownRanks or {}
	local out = {}
	for _, t in ipairs(list) do
		local s = t[1] .. " (Rank " .. t[2] .. ")"
		if (knownRanks[t[1]] or 0) >= t[2] then s = s .. " - known" end
		if familyID and not ns.PetCanLearn(familyID, t[1]) then s = s .. " - your pet can't learn" end
		out[#out + 1] = s
	end
	return out, confirmed
end

local spellIndex -- spellID -> { ability, rank }, built on first use

function ns.PetResetIndex() spellIndex = nil end

function ns.PetKnownRanks(spellIDs)
	if not spellIndex then
		spellIndex = {}
		for name, a in pairs(petData().abilities or {}) do
			for i, r in ipairs(a.ranks or {}) do
				if r.spell then spellIndex[r.spell] = { name, i } end
			end
		end
	end
	local known = {}
	for _, id in ipairs(spellIDs or {}) do
		local e = spellIndex[id]
		if e and (known[e[1]] or 0) < e[2] then known[e[1]] = e[2] end
	end
	return known
end

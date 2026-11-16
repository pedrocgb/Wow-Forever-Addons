-- Pure icon filtering (bit ops via the WoW/LuaJIT "bit" library). Data comes from Data/Icons.lua.
local _, ns = ...
local band = bit.band

-- icons: list of fileIDs (or texture path strings). query: free text, every word must appear in the name.
-- classMask / itemMask: 0 = no filter; otherwise the icon must match any selected bit. Filters combine with AND.
function ns.FilterIcons(icons, query, classMask, itemMask)
	local words = {}
	for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
	if #words == 0 and classMask == 0 and itemMask == 0 then return icons end

	local names, classes, items = ns.IconNames, ns.IconClass, ns.IconItem
	local out = {}
	for _, icon in ipairs(icons) do
		local ok = true
		if classMask ~= 0 then ok = band(classes[icon] or 0, classMask) ~= 0 end
		if ok and itemMask ~= 0 then ok = band(items[icon] or 0, itemMask) ~= 0 end
		if ok and #words > 0 then
			local name = names[icon] or (type(icon) == "string" and icon:lower()) or tostring(icon)
			for _, w in ipairs(words) do
				if not name:find(w, 1, true) then ok = false break end
			end
		end
		if ok then out[#out + 1] = icon end
	end
	return out
end

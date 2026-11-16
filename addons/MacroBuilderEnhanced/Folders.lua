-- Folder tree for macros. Pure logic over a saved "store" table, so tests/folders_test.lua can run it.
-- store = { folders = { [id] = { name =, parent = id|nil, open = bool } }, nextId = n, macros = { [macroName] = folderId } }
-- shortcut: macros are keyed by name (the game has no stable macro ID; indexes shift on every rename/create/delete),
-- so two macros with the same name share a folder. Upgrade to name+body keys if that ever matters.
local _, ns = ...
local F = {}
ns.Folders = F

F.MAX_DEPTH = 3

function F.Init(store)
	store.folders = store.folders or {}
	store.macros = store.macros or {}
	store.nextId = store.nextId or 1
	return store
end

-- 1 = top-level folder
function F.Depth(store, id)
	local d = 0
	while id and store.folders[id] do
		d = d + 1
		id = store.folders[id].parent
	end
	return d
end

-- Levels in the subtree rooted at id (1 = no subfolders).
function F.Height(store, id)
	local h = 0
	for cid, f in pairs(store.folders) do
		if f.parent == id then h = math.max(h, F.Height(store, cid)) end
	end
	return h + 1
end

function F.IsWithin(store, id, ancestor)
	while id do
		if id == ancestor then return true end
		id = store.folders[id] and store.folders[id].parent
	end
	return false
end

function F.CanCreate(store, parent)
	return F.Depth(store, parent) < F.MAX_DEPTH
end

function F.CanMoveFolder(store, id, parent)
	if parent and F.IsWithin(store, parent, id) then return false end
	return F.Depth(store, parent) + F.Height(store, id) <= F.MAX_DEPTH
end

function F.Create(store, name, parent)
	if not F.CanCreate(store, parent) then return nil end
	local id = store.nextId
	store.nextId = id + 1
	store.folders[id] = { name = name, parent = parent, open = true }
	if parent then store.folders[parent].open = true end
	return id
end

function F.MoveFolder(store, id, parent)
	if not F.CanMoveFolder(store, id, parent) then return false end
	store.folders[id].parent = parent
	return true
end

-- Subfolders and macros move up to the deleted folder's parent.
function F.Delete(store, id)
	local parent = store.folders[id].parent
	for _, f in pairs(store.folders) do
		if f.parent == id then f.parent = parent end
	end
	for name, fid in pairs(store.macros) do
		if fid == id then store.macros[name] = parent end
	end
	store.folders[id] = nil
end

function F.SetMacroFolder(store, macroName, id)
	store.macros[macroName] = id
end

function F.RenameMacro(store, old, new)
	if old ~= new and store.macros[old] then
		store.macros[new], store.macros[old] = store.macros[old], nil
	end
end

-- Forget macros that no longer exist and folder links that point nowhere.
function F.Prune(store, existing)
	for name, fid in pairs(store.macros) do
		if not existing[name] or not store.folders[fid] then store.macros[name] = nil end
	end
end

local function sortedChildren(store, parent)
	local out = {}
	for id, f in pairs(store.folders) do
		if f.parent == parent then out[#out + 1] = id end
	end
	table.sort(out, function(a, b)
		local na, nb = store.folders[a].name:lower(), store.folders[b].name:lower()
		if na == nb then return a < b end
		return na < nb
	end)
	return out
end

-- macros: list of { index =, name =, icon = } in game order.
-- Returns the visible rows, depth-first: folders then macros at each level. Collapsed folders hide their contents.
function F.Rows(store, macros)
	local byFolder = {}
	for _, m in ipairs(macros) do
		local fid = store.macros[m.name]
		if not store.folders[fid] then fid = false end
		byFolder[fid] = byFolder[fid] or {}
		table.insert(byFolder[fid], m)
	end
	local function count(id)
		local n = #(byFolder[id] or {})
		for _, cid in ipairs(sortedChildren(store, id)) do n = n + count(cid) end
		return n
	end
	local rows = {}
	local function walk(parent, depth)
		for _, id in ipairs(sortedChildren(store, parent)) do
			local f = store.folders[id]
			rows[#rows + 1] = { kind = "folder", id = id, name = f.name, depth = depth, open = f.open, count = count(id) }
			if f.open then walk(id, depth + 1) end
		end
		for _, m in ipairs(byFolder[parent or false] or {}) do
			rows[#rows + 1] = { kind = "macro", index = m.index, name = m.name, icon = m.icon, depth = depth, folder = parent }
		end
	end
	walk(nil, 0)
	return rows
end

-- Flat list of folders for "Move to" menus: { {id, name, depth} } in tree order.
function F.List(store)
	local out = {}
	local function walk(parent, depth)
		for _, id in ipairs(sortedChildren(store, parent)) do
			out[#out + 1] = { id, store.folders[id].name, depth }
			walk(id, depth + 1)
		end
	end
	walk(nil, 1)
	return out
end

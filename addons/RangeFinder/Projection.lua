-- Pure maths, no game API: tests/projection_test.lua runs this file under plain luajit.
local _, ns = ...

-- The WoW camera orbits a focus point `height` yards above the player's feet, at `distance`
-- yards, pitched `pitch` radians above the horizon (positive = looking down), and that focus
-- point sits at the centre of the screen. A ground ring around the feet is rotationally
-- symmetric, so camera yaw does not matter and this is an exact perspective projection.
--
-- Returns the screen offset (x right, y up) from the viewport centre, in the units of
-- `focal`, or nil when the point is behind or too close to the camera.
function ns.ProjectGroundPoint(radius, angle, distance, pitch, height, focal)
    local c, s = math.cos(pitch), math.sin(pitch)
    local forward = radius * math.cos(angle) -- along the camera's view, away from it
    local depth = forward * c + distance + height * s
    if depth < 0.2 then return end
    local up = forward * s - height * c
    return focal * radius * math.sin(angle) / depth, focal * up / depth
end

-- Focal length in screen units for a horizontal field of view in degrees.
function ns.FocalLength(halfWidth, fovDegrees)
    return halfWidth / math.tan(math.rad(fovDegrees) / 2)
end

-- A ring source is one string: "melee", "ranged", "spell:<id>" or "item:<id>".
function ns.ParseSource(key)
    if key == "melee" or key == "ranged" then return key end
    local kind, id = tostring(key):match("^(%a+):(%d+)$")
    if kind == "spell" or kind == "item" then return kind, tonumber(id) end
end

-- Finds a source in typed text: "melee", "ranged", or a shift-clicked spell/item link.
function ns.KeyFromText(text)
    local word = text:lower():match("^%s*(.-)%s*$")
    if word == "melee" or word == "ranged" then return word end
    local kind, id = text:match("(spell):(%d+)")
    if not kind then kind, id = text:match("(item):(%d+)") end
    return kind and (kind .. ":" .. id)
end

function ns.Label(name, minRange, maxRange)
    if minRange and minRange > 0 then
        return ("%s %g-%g yd"):format(name, minRange, maxRange)
    end
    return ("%s %g yd"):format(name, maxRange)
end

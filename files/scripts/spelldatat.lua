-- SpellDatat v2.0
-- A library for passing arbitrary data from a spell action to its projectile
-- via ProjectileComponent.config_action_description.
--
-- Usage:
--   In your action function:
--     SpellDatat.set("myMod:myKey", "myValue")
--
--   In your projectile script:
--     local data = SpellDatat.from_entity(entity_id)
--     local value = SpellDatat.get(data, "myMod:myKey")
--
-- Keys should be namespaced with your mod name to avoid conflicts with other mods.
-- No coordination between mods is required.

local VERSION   = 3.0
local SEP_ENTRY = "\n"
local SEP_KV    = "\255"
local SEP_FIELD = "\254"
local SEP_LIST = "\253"


if VERSION <= (SpellDatat_ver or 0) then return end
SpellDatat_ver = VERSION

local _data = {}

SpellDatat = {}

-- Stores a value under a namespaced key.
-- key   : string, recommended format "modName:keyName"
-- value : string, number, or array table of strings/numbers
function SpellDatat.set(key, value)
    assert(type(key) == "string", "SpellDatat.set: key must be a string")
    assert(not key:find("[\n\255=]"), "SpellDatat.set: key contains reserved characters")
    if type(value) == "table" then
        local parts = {}
        for _, v in ipairs(value) do parts[#parts+1] = tostring(v) end
        _data[key] = table.concat(parts, SEP_FIELD)
    else
        _data[key] = tostring(value)
    end
end

-- Pushes a value to a list stored under key.
function SpellDatat.push(key, value)
    assert(type(key) == "string", "SpellDatat.push: key must be a string")
    assert(not key:find("[\n\255=]"), "SpellDatat.push: key contains reserved characters")
    local current = _data[key]
    if current == nil or current == "" then
        _data[key] = tostring(value)
    else
        _data[key] = current .. SEP_LIST .. tostring(value)
    end
end

-- Pops the first value from a list stored under key.
-- Returns nil if the list is empty or the key does not exist.
function SpellDatat.pop(parsed, key)
    local v = parsed[key]
    if v == nil or v == "" then return nil end
    local head, rest = v:match("^([^\253]*)\253?(.*)")
    parsed[key] = rest or ""
    return head
end

-- Returns all values from a list stored under key as a comma-separated string.
function SpellDatat.pop_all(parsed, key)
    local v = parsed[key]
    if v == nil or v == "" then return "" end
    local result = {}
    for entry in (v .. SEP_LIST):gmatch("([^\253]*)\253") do
        if entry ~= "" then result[#result+1] = entry end
    end
    parsed[key] = ""
    return result
end

-- Clears all stored data. Called automatically after each cast.
function SpellDatat.reset()
    _data = {}
end

-- Serializes stored data for injection into action_description.
-- Internal use only.
function SpellDatat._serialize()
    local parts = {}
    for k, v in pairs(_data) do
        parts[#parts+1] = k .. SEP_KV .. v
    end
    return table.concat(parts, SEP_ENTRY)
end

-- ─── Projectile side ─────────────────────────────────────────────────────────

-- Parses a config_action_description string into a key→value table.
-- Call once per projectile script and reuse the result.
function SpellDatat.parse(desc)
    local result = {}
    for entry in (desc .. SEP_ENTRY):gmatch("([^\n]*)\n") do
        local k, v = entry:match("^([^\255]+)\255(.*)$")
        if k then result[k] = v end
    end
    return result
end

-- Reads a key from a parsed table returned by SpellDatat.parse().
-- If split=true, returns an array table (for values stored as tables).
-- Returns nil if the key does not exist.
function SpellDatat.get(parsed, key, split)
    local v = parsed[key]
    if v == nil then return split and {} or nil end
    if not split then return v end
    local fields = {}
    for f in (v .. SEP_FIELD):gmatch("([^\254]*)\254") do
        fields[#fields+1] = f
    end
    return fields
end

-- Convenience function: fetches and parses the description of a projectile entity.
-- Returns an empty table if the entity has no ProjectileComponent.
function SpellDatat.from_entity(entity_id)
    local comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ProjectileComponent")
    if not comp then return {} end
    local desc = ComponentObjectGetValue2(comp, "config", "action_description")
    if not desc then return {} end
    return SpellDatat.parse(desc)
end

-- ─── Patch ───────────────────────────────────────────────────────────────────

if not SpellDatat_patched then
    local _original = ConfigGunActionInfo_PassToGame
    function ConfigGunActionInfo_PassToGame(...)
        if not reflecting then
            c.action_description = SpellDatat._serialize()
        end
        _original(...)
        SpellDatat.reset()
    end
    SpellDatat_patched = true
end
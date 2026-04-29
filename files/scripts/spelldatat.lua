-- SpellDatat v2.0
-- A library for passing arbitrary data from a spell action to its projectile
-- via ProjectileComponent.config_action_description.
--
-- Backward-compatible with Datat (Copi's positional cast-state library):
--   * If Datat is already patched when SpellDatat loads, SpellDatat hooks
--     into Datat's wrapper chain so both data sets reach the projectile.
--   * If SpellDatat loads first, it claims Datat's patch sentinel and
--     emulates Datat's side effects (positional action_description slots
--     and GLOBAL_CAST_STATE increment) so existing Datat consumers keep
--     working regardless of load order.
--
-- Usage (unchanged):
--   In your action function:
--     SpellDatat.set("myMod:myKey", "myValue")
--
--   In your projectile script:
--     local data  = SpellDatat.from_entity(entity_id)
--     local value = SpellDatat.get(data, "myMod:myKey")
--
-- Keys must be namespaced ("modName:keyName") to avoid collisions.

local VERSION   = 2.0
local SEP_ENTRY = "\n"
local SEP_KV    = "\255"
local SEP_FIELD = "\254"
local SEP_LIST  = "\253"
-- A line containing only this marker separates Datat's positional section
-- from SpellDatat's key=value section inside action_description.
local MARKER    = "__SPELLDATAT__"

if VERSION <= (SpellDatat_ver or 0) then return end
SpellDatat_ver = VERSION

local _data = {}

SpellDatat = {}

-- =============================================================================
-- Producer API
-- =============================================================================

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

-- Clears all stored data. Called automatically after each cast.
function SpellDatat.reset()
    _data = {}
end

-- Serializes pending data prefixed by MARKER. Returns "" if nothing to send.
-- Internal use.
function SpellDatat._serialize()
    local parts = {}
    for k, v in pairs(_data) do
        parts[#parts+1] = k .. SEP_KV .. v
    end
    if #parts == 0 then return "" end
    return MARKER .. SEP_ENTRY .. table.concat(parts, SEP_ENTRY)
end

-- =============================================================================
-- Consumer API
-- =============================================================================

-- Parses a config_action_description string into a key->value table.
-- Tolerates: pure SpellDatat output (legacy, no marker), Datat-only output
-- (no SpellDatat keys found, returns empty), or merged output (Datat slots
-- followed by MARKER followed by SpellDatat keys).
function SpellDatat.parse(desc)
    local result = {}
    if not desc or desc == "" then return result end

    local body
    local m_with_nl = SEP_ENTRY .. MARKER .. SEP_ENTRY
    local pos = desc:find(m_with_nl, 1, true)
    if pos then
        body = desc:sub(pos + #m_with_nl)
    elseif desc:sub(1, #MARKER + #SEP_ENTRY) == MARKER .. SEP_ENTRY then
        body = desc:sub(#MARKER + #SEP_ENTRY + 1)
    else
        -- No marker. Could be legacy SpellDatat data, or Datat-only data.
        -- Parsing the whole desc is safe: lines that don't match key\255value
        -- are dropped, so Datat positional lines are simply ignored.
        body = desc
    end

    for entry in (body .. SEP_ENTRY):gmatch("([^\n]*)\n") do
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

-- Pops the first value from a list stored under key.
-- Returns nil if the list is empty or the key does not exist.
function SpellDatat.pop(parsed, key)
    local v = parsed[key]
    if v == nil or v == "" then return nil end
    local head, rest = v:match("^([^\253]*)\253?(.*)")
    parsed[key] = rest or ""
    return head
end

-- Returns all values from a list stored under key as an array, and clears it.
function SpellDatat.pop_all(parsed, key)
    local v = parsed[key]
    if v == nil or v == "" then return {} end
    local result = {}
    for entry in (v .. SEP_LIST):gmatch("([^\253]*)\253") do
        if entry ~= "" then result[#result+1] = entry end
    end
    parsed[key] = ""
    return result
end

-- Convenience: fetches and parses the description of a projectile entity.
function SpellDatat.from_entity(entity_id)
    local comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ProjectileComponent")
    if not comp then return {} end
    local desc = ComponentObjectGetValue2(comp, "config", "action_description")
    if not desc then return {} end
    return SpellDatat.parse(desc)
end

-- =============================================================================
-- Datat-compat helpers
-- =============================================================================

-- Mirrors Datat's own serialization: pads to max(__maxindx, 13) and joins
-- with "\n". Returns "" only if Datat has never loaded.
local function _serialize_datat_section()
    if not Datat_ver or not Datat or not DontTouch_Data then return "" end
    local maxindx = Datat.__maxindx or -math.huge
    if maxindx < 13 then maxindx = 13 end
    local parts = {}
    for i = 1, maxindx do
        parts[i] = DontTouch_Data[i] or ""
    end
    return table.concat(parts, SEP_ENTRY)
end

-- Reads a Datat positional slot (1-based) from a raw action_description string.
-- Returns the slot's contents or "" if absent. Stops scanning at the MARKER
-- line so it never returns part of the SpellDatat section.
function SpellDatat.get_datat_slot(desc, index)
    if not desc or desc == "" or type(index) ~= "number" or index < 1 then return "" end
    local i = 1
    for line in (desc .. SEP_ENTRY):gmatch("([^\n]*)\n") do
        if line == MARKER then return "" end
        if i == index then return line end
        i = i + 1
    end
    return ""
end

-- =============================================================================
-- Patch
-- =============================================================================

if not SpellDatat_patched then
    if DidWePatchThisShitCopi then
        -- ---------------------------------------------------------------------
        -- Datat is already patched. Insert ourselves between Datat's wrapper
        -- and the real ConfigGunActionInfo_PassToGame.
        --
        -- Datat's wrapper does:
        --   c.action_description = <positional>
        --   ConfigGunActionInfo_PassToGame_old(...)   -- now points to us
        --   GlobalsSetValue("GLOBAL_CAST_STATE", ...)
        --   ResetDatat()
        --
        -- We append SpellDatat's section to whatever Datat wrote, then call
        -- the genuine engine function. Datat's other side effects run after
        -- our hook returns, untouched.
        -- ---------------------------------------------------------------------
        local _real_original = ConfigGunActionInfo_PassToGame_old
        ConfigGunActionInfo_PassToGame_old = function(...)
            if not reflecting then
                local sd = SpellDatat._serialize()
                if sd ~= "" then
                    local existing = c.action_description
                    if existing and existing ~= "" then
                        c.action_description = existing .. SEP_ENTRY .. sd
                    else
                        c.action_description = sd
                    end
                end
            end
            _real_original(...)
            if not reflecting then SpellDatat.reset() end
        end
    else
        -- ---------------------------------------------------------------------
        -- Datat not patched yet (and may never load). Patch normally and
        -- claim Datat's sentinel so that, if Datat loads later, it sees its
        -- patch as already applied and skips it. We then emulate Datat's
        -- runtime behavior: positional serialization, GLOBAL_CAST_STATE
        -- bump, ResetDatat. All gated on Datat_ver so we don't trigger any
        -- of these side effects when Datat is genuinely absent.
        -- ---------------------------------------------------------------------
        DidWePatchThisShitCopi = true
        local _original = ConfigGunActionInfo_PassToGame
        function ConfigGunActionInfo_PassToGame(...)
            if not reflecting then
                local datat_part = _serialize_datat_section()
                local sd_part    = SpellDatat._serialize()
                if datat_part ~= "" and sd_part ~= "" then
                    c.action_description = datat_part .. SEP_ENTRY .. sd_part
                elseif datat_part ~= "" then
                    c.action_description = datat_part
                else
                    c.action_description = sd_part
                end
            end
            _original(...)
            if not reflecting then
                SpellDatat.reset()
                if ResetDatat then ResetDatat() end
                if Datat_ver then
                    GlobalsSetValue(
                        "GLOBAL_CAST_STATE",
                        tostring(tonumber(GlobalsGetValue("GLOBAL_CAST_STATE", "0")) + 1)
                    )
                end
            end
        end
    end
    SpellDatat_patched = true
end
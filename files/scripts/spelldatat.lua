-- ONLY use latest version of this code across mods
-- Copi tech below.
local ver = 1.1
if ver > (Datat_ver or 0) then
	Datat_ver = ver
	-- Add Datat as a place to insert data. Modders should coordinate on what maps to what.
	--[[
		Standardization:
			1: Cast State
			2: C
			...
	]]

	function ResetDatat()
		DontTouch_Data = {}
		Datat = setmetatable(
			{__maxindx = -math.huge},
			{__newindex = function(t, k, v)
				if type(k) == "number" and k > t.__maxindx then t.__maxindx = k end
				DontTouch_Data[k] = v
			end}
		)
	end
	ResetDatat()

	-- Writes the cast state to indx i.
	---@param c table
	function WriteCToDatat(c)
		local a = {
			c.action_id,
			c.action_name,
			c.action_description,
			c.action_sprite_filename,
			c.action_unidentified_sprite_filename,
			c.action_type,
			c.action_spawn_level,
			c.action_spawn_probability,
			c.action_spawn_requires_flag,
			c.action_spawn_manual_unlock,
			c.action_max_uses,
			c.custom_xml_file,
			c.action_mana_drain,
			c.action_is_dangerous_blast,
			c.action_draw_many_count,
			c.action_ai_never_uses,
			c.action_never_unlimited,
			c.state_shuffled,
			c.state_cards_drawn,
			c.state_discarded_action,
			c.state_destroyed_action,
			c.fire_rate_wait,
			c.speed_multiplier,
			c.child_speed_multiplier,
			c.dampening,
			c.explosion_radius,
			c.spread_degrees,
			c.pattern_degrees,
			c.screenshake,
			c.recoil,
			c.damage_melee_add,
			c.damage_projectile_add,
			c.damage_electricity_add,
			c.damage_fire_add,
			c.damage_explosion_add,
			c.damage_ice_add,
			c.damage_slice_add,
			c.damage_healing_add,
			c.damage_curse_add,
			c.damage_drill_add,
			c.damage_null_all,
			c.damage_critical_chance,
			c.damage_critical_multiplier,
			c.explosion_damage_to_materials,
			c.knockback_force,
			c.reload_time,
			c.lightning_count,
			c.material,
			c.material_amount,
			c.trail_material,
			c.trail_material_amount,
			c.bounces,
			c.gravity,
			c.light,
			c.blood_count_multiplier,
			c.gore_particles,
			c.ragdoll_fx,
			c.friendly_fire,
			c.physics_impulse_coeff,
			c.lifetime_add,
			c.sprite,
			c.extra_entities,
			c.game_effect_entities,
			c.sound_loop_tag,
			c.projectile_file,
		}
		for i=1, #a do
			a[i]=tostring(a[i])
		end
		Datat[2] = table.concat(a, string.char(255))
	end

	-- =========================================================================
	-- SpellDatat: namespaced key/value subsystem on top of Datat.
	--
	-- Use when you want to pass data from an action to its projectile without
	-- coordinating slot indices with other mods. Keys are namespaced as
	-- "modname:something" and round-trip through the same action_description
	-- transport. Datat positional slots and SpellDatat key/value entries
	-- coexist in the same string, separated by a marker line.
	--
	-- Producer (action side):
	--   SpellDatat.set("mymod:color", "red")
	--   SpellDatat.set("mymod:items", {"sword", "shield"})  -- table value
	--   SpellDatat.push("mymod:queue", "first")             -- list append
	--
	-- Consumer (projectile side):
	--   local data = SpellDatat.from_entity(entity_id)
	--   local color = SpellDatat.get(data, "mymod:color")
	--   local items = SpellDatat.get(data, "mymod:items", true)  -- as array
	--   local head  = SpellDatat.pop(data, "mymod:queue")
	-- =========================================================================

	local SD_SEP_ENTRY = "\n"   -- between key=value entries
	local SD_SEP_KV    = "\255" -- between key and value
	local SD_SEP_FIELD = "\254" -- between fields of a table value
	local SD_SEP_LIST  = "\253" -- between pushed list items
	local SD_ESCAPE    = "\252" -- escape introducer for reserved bytes
	local SD_MARKER    = "__SPELLDATAT__"

	-- Namespaced key: at least one colon, no reserved bytes anywhere.
	-- This is what lets the consumer-side parser tell SpellDatat lines
	-- apart from Datat's slot-2 payload (which contains \255 internally
	-- but no colon-separated synthetic "key").
	local SD_KEY_PATTERN = "^[^\n\255=:\254\253\252]+:[^\n\255=\254\253\252]+$"

	-- Encoding of reserved bytes inside values. Producers do not need to
	-- escape anything by hand -- set/push do it transparently.
	local SD_ESCAPE_MAP = {
		["\252"] = "\252\252",
		["\n"]   = "\252n",
		["\255"] = "\252a",
		["\254"] = "\252b",
		["\253"] = "\252c",
	}
	local SD_UNESCAPE_MAP = {
		["\252"] = "\252",
		["n"]    = "\n",
		["a"]    = "\255",
		["b"]    = "\254",
		["c"]    = "\253",
	}

	local function sd_escape(s)
		if s == nil then return "" end
		s = tostring(s)
		return (s:gsub("[\252\n\255\254\253]", SD_ESCAPE_MAP))
	end

	local function sd_unescape(s)
		if not s or s == "" then return s end
		return (s:gsub("\252(.)", SD_UNESCAPE_MAP))
	end

	local function sd_check_key(key, fn)
		if type(key) ~= "string" then
			error(fn .. ": key must be a string", 3)
		end
		if not key:match(SD_KEY_PATTERN) then
			error(fn .. ": key must be namespaced as 'modname:keyname' "
			      .. "with no reserved characters (got " .. key .. ")", 3)
		end
	end

	local _sd_data = {}

	SpellDatat = {}

	-- Producer API -------------------------------------------------------------

	function SpellDatat.set(key, value)
		sd_check_key(key, "SpellDatat.set")
		if type(value) == "table" then
			local parts = {}
			for _, v in ipairs(value) do
				parts[#parts+1] = sd_escape(v)
			end
			_sd_data[key] = table.concat(parts, SD_SEP_FIELD)
		else
			_sd_data[key] = sd_escape(value)
		end
	end

	function SpellDatat.push(key, value)
		sd_check_key(key, "SpellDatat.push")
		local current = _sd_data[key]
		local encoded = sd_escape(value)
		if current == nil or current == "" then
			_sd_data[key] = encoded
		else
			_sd_data[key] = current .. SD_SEP_LIST .. encoded
		end
	end

	function SpellDatat.reset()
		_sd_data = {}
	end

	-- Internal: serializes the pending key/value section, including the
	-- leading marker line. Returns "" if there's nothing to send.
	function SpellDatat._serialize()
		local parts = {}
		for k, v in pairs(_sd_data) do
			parts[#parts+1] = k .. SD_SEP_KV .. v
		end
		if #parts == 0 then return "" end
		return SD_MARKER .. SD_SEP_ENTRY .. table.concat(parts, SD_SEP_ENTRY)
	end

	-- Consumer API -------------------------------------------------------------

	function SpellDatat.parse(desc)
		local result = {}
		if not desc or desc == "" then return result end

		local body
		local m_with_nl = SD_SEP_ENTRY .. SD_MARKER .. SD_SEP_ENTRY
		local pos = desc:find(m_with_nl, 1, true)
		if pos then
			body = desc:sub(pos + #m_with_nl)
		elseif desc:sub(1, #SD_MARKER + #SD_SEP_ENTRY) == SD_MARKER .. SD_SEP_ENTRY then
			body = desc:sub(#SD_MARKER + #SD_SEP_ENTRY + 1)
		else
			-- No marker. Filter strictly by the namespaced key pattern so
			-- Datat's slot 2 (which contains \255 internally) cannot be
			-- mis-parsed as a fake key=value line.
			body = desc
		end

		for entry in (body .. SD_SEP_ENTRY):gmatch("([^\n]*)\n") do
			local k, v = entry:match("^([^\255]+)\255(.*)$")
			if k and k:match(SD_KEY_PATTERN) then
				result[k] = v
			end
		end
		return result
	end

	function SpellDatat.get(parsed, key, split)
		local v = parsed[key]
		if v == nil then return split and {} or nil end
		if not split then return sd_unescape(v) end
		local fields = {}
		for f in (v .. SD_SEP_FIELD):gmatch("([^\254]*)\254") do
			fields[#fields+1] = sd_unescape(f)
		end
		return fields
	end

	function SpellDatat.pop(parsed, key)
		local v = parsed[key]
		if v == nil or v == "" then
			if v == "" then parsed[key] = nil end
			return nil
		end
		local head, rest = v:match("^([^\253]*)\253?(.*)")
		if rest == nil or rest == "" then
			parsed[key] = nil
		else
			parsed[key] = rest
		end
		return sd_unescape(head)
	end

	function SpellDatat.pop_all(parsed, key)
		local v = parsed[key]
		if v == nil or v == "" then
			parsed[key] = nil
			return {}
		end
		local result = {}
		for entry in (v .. SD_SEP_LIST):gmatch("([^\253]*)\253") do
			if entry ~= "" then result[#result+1] = sd_unescape(entry) end
		end
		parsed[key] = nil
		return result
	end

	function SpellDatat.from_entity(entity_id)
		local comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ProjectileComponent")
		if not comp then return {} end
		local desc = ComponentObjectGetValue2(comp, "config", "action_description")
		if not desc then return {} end
		return SpellDatat.parse(desc)
	end

	-- Reads a Datat positional slot from a raw action_description. Stops at
	-- the SpellDatat marker so it never returns key/value content.
	function SpellDatat.get_datat_slot(desc, index)
		if not desc or desc == "" or type(index) ~= "number" or index < 1 then
			return ""
		end
		local i = 1
		for line in (desc .. SD_SEP_ENTRY):gmatch("([^\n]*)\n") do
			if line == SD_MARKER then return "" end
			if i == index then return line end
			i = i + 1
		end
		return ""
	end

	if not DidWePatchThisShitCopi then
		-- Patch ConfigGunActionInfo_PassToGame to inject data last minute
		local ConfigGunActionInfo_PassToGame_old = ConfigGunActionInfo_PassToGame
		function ConfigGunActionInfo_PassToGame(...)
			if not reflecting then
				-- Inject SpellDatat's payload as a Datat slot just past the
				-- last used one. Datat's table.concat below will fold it
				-- into action_description with the same "\n" separator.
				local sd = SpellDatat._serialize()
				if sd ~= "" then
					local n = Datat.__maxindx
					if n < 13 then n = 13 end
					Datat[n + 1] = sd
				end
				for i=1, math.max(Datat.__maxindx,13) do if not DontTouch_Data[i] then DontTouch_Data[i]="" end end
				c.action_description = table.concat(DontTouch_Data, "\n")
			end
			ConfigGunActionInfo_PassToGame_old(...)
			if not reflecting then GlobalsSetValue("GLOBAL_CAST_STATE", tostring(tonumber(GlobalsGetValue("GLOBAL_CAST_STATE", "0"))+1)) end
			ResetDatat()
			SpellDatat.reset()
		end
		DidWePatchThisShitCopi = true
	end
end
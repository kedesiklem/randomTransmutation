local MOD_ID   = "randomTransmutation"
local MOD_ROOT =  "mods/" .. MOD_ID .. "/files/"

local rt = dofile_once(MOD_ROOT .. "scripts/utils.lua")
local log = dofile_once("mods/randomTransmutation/logger.lua")

local rt_spellappends = {
        {
        id          = "RANDOMTRANSMUTATION_RT",
        name 		= "$spell_randomTransmutation_name",
        description = "$spell_randomTransmutation_desc",
		sprite 		= rt.default_sprite,
		sprite_unidentified = "data/ui_gfx/gun_actions/explosive_projectile_unidentified.png",
		related_extra_entities = { MOD_ROOT .. "/entities/misc/random_transmutation.xml", "data/entities/particles/tinyspark_red.xml" },
		type 		= ACTION_TYPE_MODIFIER,
		spawn_level                       = "1,2,3,4,5,6,7,8,9,10",
		spawn_probability                 = "3,3,3,3,3,3,3,3,3,3",
		price = 80,
		mana = 30,
		--max_uses = 50,
		action = function(recursion_level, iteration)
			local card_id = rt.get_card_id(recursion_level, iteration)
			if card_id then

				local mat_from = rt.get_card_var(card_id, "rt_from")
				local mat_to   = rt.get_card_var(card_id, "rt_to")

				if (mat_from ~= nil) and (mat_to ~= nil) then

					SpellDatat.push(MOD_ID .. ":from", mat_from)
					SpellDatat.push(MOD_ID .. ":to",   mat_to)
					log.debug("SET : " .. mat_from .. " -> " .. mat_to)

					c.extra_entities = c.extra_entities .. MOD_ROOT .. "/entities/misc/random_transmutation.xml,data/entities/particles/tinyspark_red.xml,"
				else
					log.debug("Invalid : " .. tostring(mat_from) .. " -> " .. tostring(mat_to))
				end
			end
			draw_actions( 1, true )
		end
    },

}

-- Credit to Conga Lyne (almost exact copy-past for mod insertion (without the organized icon part))
local function append_rt_spells()
    for k=1,#rt_spellappends
    do local v = rt_spellappends[k]
        v.author    = v.author  or "Kedesiklem"
        v.mod       = v.mod     or MOD_ID
        table.insert(actions,v)
    end
end

if actions ~= nil then
    append_rt_spells()
end

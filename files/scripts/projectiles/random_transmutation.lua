local MOD_ID   = "randomTransmutation"
local MOD_ROOT =  "mods/" .. MOD_ID .. "/files/"

dofile_once("data/scripts/lib/utilities.lua")
dofile_once(MOD_ROOT .. "/scripts/spelldatat.lua")

local entity_id    = GetUpdatedEntityID()
local pos_x, pos_y = EntityGetTransform(entity_id)

local MCMC = EntityGetFirstComponent(entity_id, "MagicConvertMaterialComponent", "random_transmutation")

if (MCMC == nil) or (MCMC == 0)  then

    -- Lire les données du projectile
    -- Plusieurs sorts peuvent tourner en parallèle → pop_all retourne un tableau par sort
    local data   = SpellDatat.from_entity(entity_id)
    local froms  = SpellDatat.pop_all(data, MOD_ID .. ":from")  -- noms de groupes
    local tos    = SpellDatat.pop_all(data, MOD_ID .. ":to")    -- matériaux cibles

    -- Charger les groupes (une seule fois)
    local groups = dofile_once(MOD_ROOT .. "/scripts/materials_parser.lua").load().GROUPS

    -- Pour chaque sort : expand le groupe source en autant de paires input→output
    for i = 1, #froms do
        local group   = groups[froms[i]]
        local members = group and group.members or { froms[i] }
        local to_id   = CellFactory_GetType(tos[i])

        for _, from_mat in ipairs(members) do
            EntityAddComponent2(entity_id, "MagicConvertMaterialComponent", {
                from_material      = CellFactory_GetType(from_mat),
                to_material        = to_id,
                kill_when_finished = false,
                steps_per_frame    = 48,
                clean_stains       = false,
                is_circle          = true,
                radius             = 32,
                loop               = true,
                _tags              = "random_transmutation",
            })
        end
    end

    -- Activer tous les composants de transmutation
    EntitySetComponentsWithTagEnabled(entity_id, "random_transmutation", true)

    edit_component(entity_id, "LuaComponent", function(comp, vars)
        EntitySetComponentIsEnabled(entity_id, comp, false)
    end)
end
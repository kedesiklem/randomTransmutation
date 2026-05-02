local MOD_ID   = "randomTransmutation"
local MOD_ROOT =  "mods/" .. MOD_ID .. "/files/"

local gen_sprites_path = "mods/" .. MOD_ID .. "/generated/sprites/"


local rt  = dofile_once(MOD_ROOT .. "scripts/utils.lua")
local log = dofile_once("mods/" .. MOD_ID .. "/logger.lua")

local _original_CreateItemActionEntity = CreateItemActionEntity

-- ── Chargement des groupes (une seule fois) ───────────────────────────────────

local _groups = nil
local function get_groups()
    if not _groups then
        _groups = dofile_once(MOD_ROOT .. "scripts/materials_parser.lua")
                    .load().GROUPS
    end
    return _groups
end

-- ── Sélection pondérée ────────────────────────────────────────────────────────

-- Retourne (group_name, group_data) en respectant les weights.
-- `exclude` permet d'éviter de retirer le même groupe deux fois.
local function pick_weighted(groups, exclude)
    local entries = {}
    local total   = 0
    for name, group in pairs(groups) do
        if name ~= exclude then
            local w = group.weight or 1
            total   = total + w
            entries[#entries + 1] = { name = name, group = group, cum = total }
        end
    end

    if total == 0 then return nil, nil end

    local roll = Random(1, total)
    for _, e in ipairs(entries) do
        if roll <= e.cum then
            return e.name, e.group
        end
    end

    -- Fallback (ne devrait pas arriver)
    local last = entries[#entries]
    return last.name, last.group
end

-- Retourne un membre aléatoire du groupe (output).
-- Si out_max_index est défini et > 0, seuls les membres jusqu'à cet index
-- peuvent être tirés. Sinon, tous les membres sont éligibles.
local function pick_output_member(group)
    local members  = group.members
    local max      = group.out_max_index
    local eligible = (max and max > 0) and max or #members
    eligible = math.min(eligible, #members)  -- sécurité si out_max_index > taille réelle
    return members[Random(1, eligible)]
end

-- ── Hook ─────────────────────────────────────────────────────────────────────

function CreateItemActionEntity(action_id, x,y)
    local card_id = _original_CreateItemActionEntity(action_id, x,y)

    if action_id == "RANDOMTRANSMUTATION_RT" and card_id ~= 0 and card_id ~= nil then
        
        local groups = get_groups()

        local from_group_name, from_group = pick_weighted(groups)
        local to_group_name,   to_group   = pick_weighted(groups)

        if not from_group or not to_group then
            log.warn("Impossible de sélectionner deux groupes distincts.")
            return card_id
        end

        -- Input  : le groupe entier (l'action lira rt_from_group pour en déduire
        --          tous les matériaux déclencheurs via MagicConvertMaterialComponent)
        -- Output : un seul membre tiré au hasard dans le groupe cible
        local to_material = pick_output_member(to_group)

        local sprite_path = gen_sprites_path .. from_group_name .. "_to_" .. to_group_name .. ".png"
        -- Identité visuelle : on utilise les representatives pour le nom et le sprite

        local to_material_name = CellFactory_GetUIName(CellFactory_GetType(to_material))

        rt.set_card_identity(card_id,
            from_group.representative,
            to_material_name,
            sprite_path)

        -- Écrase rt_from / rt_to avec les valeurs réelles pour l'action :
        --   rt_from       = nom du groupe source  (l'action charge tous les membres)
        --   rt_to         = matériau cible précis  (un seul, choisi ci-dessus)
        rt.set_card_var(card_id, "rt_from", from_group_name)
        rt.set_card_var(card_id, "rt_to",   to_material)

        log.info(from_group_name .. " -> " .. to_material
                 .. "  (groupe cible : " .. to_group_name .. ")")
    end

    return card_id
end
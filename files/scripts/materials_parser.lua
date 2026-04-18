-- materials_parser.lua
-- Parse materials.xml (+ matériaux moddés) au runtime via nxml.
-- Adapté de l'approche lamas_stats.
--
-- Retourne { MATERIALS, GROUPS, MATERIAL_TO_GROUP }
-- GROUPS est chargé depuis groups.lua (table statique, éditée manuellement).
-- MATERIALS est construit dynamiquement → supporte les mods qui ajoutent des matériaux.

local MOD_ID   = "randomTransmutation"
local MOD_ROOT = "mods/" .. MOD_ID .. "/files/"

-- ── Couleur ───────────────────────────────────────────────────────────────────

-- AARRGGBB ou RRGGBB (hex string) → { R, G, B }
local function parse_color(hex)
    if not hex then return nil end
    hex = hex:gsub("^#", "")
    local r, g, b
    if #hex == 8 then
        r = tonumber(hex:sub(3, 4), 16)
        g = tonumber(hex:sub(5, 6), 16)
        b = tonumber(hex:sub(7, 8), 16)
    elseif #hex == 6 then
        r = tonumber(hex:sub(1, 2), 16)
        g = tonumber(hex:sub(3, 4), 16)
        b = tonumber(hex:sub(5, 6), 16)
    end
    return (r and g and b) and { r, g, b } or nil
end

-- Même logique que lamas_stats : Graphics.color en priorité, sinon wang_color
local function get_color(elem)
    local graphics = elem:first_of("Graphics")
    local hex
    if graphics ~= nil then
        hex = graphics.attr["color"] or elem.attr["wang_color"]
    else
        hex = elem.attr["wang_color"]
    end
    return parse_color(hex)
end

-- ── Classification du type ────────────────────────────────────────────────────

-- Reproduit la logique de xml_to_materials.py :
--   cell_type="liquid" + liquid_sand="1" + liquid_static="1" → solid
--   cell_type="liquid" + liquid_sand="1"                     → powder
--   cell_type="liquid"                                        → liquid
--   cell_type="solid"                                         → solid
--   cell_type="gas"                                           → gas
--   cell_type="fire"                                          → fire
local function classify(elem)
    local ct = elem.attr["cell_type"]
    if ct == "liquid" then
        if elem.attr["liquid_sand"] == "1" then
            return elem.attr["liquid_static"] == "1" and "solid" or "powder"
        end
        return "liquid"
    elseif ct == "solid" then return "solid"
    elseif ct == "gas"   then return "gas"
    elseif ct == "fire"  then return "fire"
    end
    return nil  -- type inconnu ou absent (air, etc.)
end

-- ── Parser principal ──────────────────────────────────────────────────────────

local _materials_cache = nil

local function gather_materials()
    if _materials_cache then return _materials_cache end

    local nxml      = dofile_once("mods/lamas_stats/files/lib/nxml.lua")
    local base_file = "data/materials.xml"
    local xml       = nxml.parse(ModTextFileGetContent(base_file))

    -- Ajout des matériaux moddés (même pattern que lamas_stats)
    for _, file in ipairs(ModMaterialFilesGet()) do
        if file ~= base_file then
            for _, child in ipairs(nxml.parse(ModTextFileGetContent(file)).children) do
                xml.children[#xml.children + 1] = child
            end
        end
    end

    -- 1re passe : type de chaque CellData (racines)
    local base_types = {}   -- name → type
    for elem in xml:each_of("CellData") do
        local name = elem.attr["name"]
        local t    = classify(elem)
        if name and t then
            base_types[name] = t
        end
    end

    -- 2e passe : résolution itérative de l'héritage (gère N niveaux)
    -- resolved_types contient aussi les CellDataChild au fur et à mesure
    local resolved_types = {}
    for k, v in pairs(base_types) do resolved_types[k] = v end

    local child_parent = {}
    for elem in xml:each_of("CellDataChild") do
        local name   = elem.attr["name"]
        local parent = elem.attr["_parent"]
        if name and parent then
            child_parent[name] = parent
        end
    end

    -- Jusqu'à 10 passes (couvre les chaînes d'héritage profondes)
    for _ = 1, 10 do
        local progress = false
        for name, parent in pairs(child_parent) do
            if not resolved_types[name] and resolved_types[parent] then
                resolved_types[name] = resolved_types[parent]
                progress = true
            end
        end
        if not progress then break end
    end

    -- 3e passe : construction de la table MATERIALS
    local materials = {}

    for elem in xml:each_of("CellData") do
        local name  = elem.attr["name"]
        local color = get_color(elem)
        local t     = resolved_types[name]
        if name and color and t then
            materials[name] = { color = color, type = t }
        end
    end

    for elem in xml:each_of("CellDataChild") do
        local name  = elem.attr["name"]
        local color = get_color(elem)
        local t     = resolved_types[name]
        if name and color and t then
            materials[name] = { color = color, type = t }
        end
    end

    _materials_cache = materials
    return materials
end

-- ── Chargement des groupes ────────────────────────────────────────────────────

local _data_cache = nil

local function load()
    if _data_cache then return _data_cache end

    local MATERIALS = gather_materials()
    local GROUPS    = dofile_once(MOD_ROOT .. "/scripts/groups.lua")

    -- Filtrer les membres sans entrée dans MATERIALS (matériau retiré ou renommé)
    for _, group in pairs(GROUPS) do
        local valid = {}
        for _, mat in ipairs(group.members) do
            if MATERIALS[mat] then
                valid[#valid + 1] = mat
            end
        end
        group.members = valid
    end

    -- Lookup inverse : nom_matériau → nom_groupe
    local MATERIAL_TO_GROUP = {}
    for group_name, group in pairs(GROUPS) do
        for _, mat in ipairs(group.members) do
            MATERIAL_TO_GROUP[mat] = group_name
        end
    end

    _data_cache = {
        MATERIALS         = MATERIALS,
        GROUPS            = GROUPS,
        MATERIAL_TO_GROUP = MATERIAL_TO_GROUP,
    }
    return _data_cache
end

return { load = load }
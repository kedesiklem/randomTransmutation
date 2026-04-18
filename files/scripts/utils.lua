local MOD_ID   = "randomTransmutation"
local MOD_ROOT =  "mods/" .. MOD_ID .. "/"

local default_sprite = MOD_ROOT.. "files/ui_gfx/gun_actions/random_transmutation.png"
local log = dofile_once("mods/randomTransmutation/logger.lua")

-- ── Variables de carte ────────────────────────────────────────────────────────

local function get_card_var(card_id, var_name, default)
	local comps = EntityGetComponentIncludingDisabled(card_id, "VariableStorageComponent") or {}
	for _, comp in ipairs(comps) do
		if ComponentGetValue2(comp, "name") == var_name then
			return ComponentGetValue2(comp, "value_string")
		end
	end
	return default
end

local function set_card_var(card_id, var_name, value)
	local comps = EntityGetComponentIncludingDisabled(card_id, "VariableStorageComponent") or {}
	for _, comp in ipairs(comps) do
		if ComponentGetValue2(comp, "name") == var_name then
			ComponentSetValue2(comp, "value_string", value)
			return
		end
	end
	EntityAddComponent2(card_id, "VariableStorageComponent", {
		name = var_name,
		value_string = value
	})
end

-- ── Sprite ────────────────────────────────────────────────────────────────────

--- Met à jour le SpriteComponent de la carte pour afficher mat_from → mat_to.
---
--- On cherche d'abord un SpriteComponent tagué "rt_card_sprite" pour le réutiliser ;
--- s'il n'existe pas on en ajoute un nouveau avec ce tag.
---
--- @param card_id  number  entité de la carte de sort
--- @param sprite_path string
local function update_card_sprite(card_id, sprite_path)
	local comps = EntityGetComponentIncludingDisabled(card_id, "SpriteComponent") or {}

	-- Chercher le composant déjà tagué (appels suivants)
	local target
	for _, comp in ipairs(comps) do
		
		if ComponentHasTag(comp, "rt_card_sprite") then
			target = comp
			break
		end
	end

	-- Premier appel : prendre le sprite par défaut et lui poser le tag
	if not target then
		for _, comp in ipairs(comps) do
			if ComponentGetValue2(comp, "image_file") == default_sprite then
				target = comp
				ComponentAddTag(comp, "rt_card_sprite")
				break
			end
		end
	end

	if not target then return end

	ComponentSetValue2(target, "image_file", sprite_path)

	-- Mettre à jour ui_sprite sur l'ItemComponent (inventaire / tooltip)
	local item_comp = EntityGetFirstComponentIncludingDisabled(card_id, "ItemComponent")
	if item_comp then
		ComponentSetValue2(item_comp, "ui_sprite", sprite_path)
	end
end

-- ── Identité complète de la carte ─────────────────────────────────────────────

--- Initialise ou met à jour l'identité complète d'une carte de transmutation :
---   - stocke mat_from / mat_to dans des VariableStorageComponent
---   - met à jour le nom affiché dans l'inventaire
---   - met à jour le sprite de la carte
---
--- @param card_id  number  entité de la carte de sort
--- @param mat_from string  nom du matériau source
--- @param mat_to   string  nom du matériau cible
local function set_card_identity(card_id, mat_from, mat_to, sprite_path)
	-- Variables persistantes (lues par l'action au lancer)
	set_card_var(card_id, "rt_from", mat_from)
	set_card_var(card_id, "rt_to",   mat_to)

	-- Nom dans l'UI inventaire
	local item_comp = EntityGetFirstComponentIncludingDisabled(card_id, "ItemComponent")
	if item_comp then
		local from_name = GameTextGetTranslatedOrNot(mat_from)
		local to_name   = GameTextGetTranslatedOrNot(mat_to)

		ComponentSetValue2(item_comp, "item_name", from_name .. " -> " .. to_name)
		ComponentSetValue2(item_comp, "always_use_item_name_in_ui", true)
	end

	-- Sprite de la carte
	update_card_sprite(card_id, sprite_path)
end

-- ── Résolution de l'entité carte ──────────────────────────────────────────────

local function get_card_id(recursion_level, iteration)	

	local entity_id = GetUpdatedEntityID()
	local inventory = EntityGetFirstComponent(entity_id, "Inventory2Component")
	if inventory then
		local active_wand = ComponentGetValue2(inventory, "mActiveItem")

		local idx = (current_action.deck_index or 0) + 1
		local count = 0
		local children = EntityGetAllChildren(active_wand) or {}
		for _, child in ipairs(children) do
			local iac = EntityGetComponentIncludingDisabled(child, "ItemActionComponent")
			if iac ~= nil then
				count = count + 1
				if count == idx then
					return child
				end
			end
		end
		return nil
	end
end
-- ── Exports ───────────────────────────────────────────────────────────────────

return {
	get_card_var       = get_card_var,
	set_card_var       = set_card_var,
	update_card_sprite = update_card_sprite,
	set_card_identity  = set_card_identity,
	get_card_id        = get_card_id,
	default_sprite = default_sprite

}

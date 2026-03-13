-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local lovely = require("lovely")
local nativefs = require("nativefs")

GreenNeedle.SearchTagList = {
	["Any"]="",
	["Uncommon Tag"]="tag_uncommon",
	["Rare Tag"]="tag_rare",
	["Holographic Tag"]="tag_holo",
	["Foil Tag"]="tag_foil",
	["Polychrome Tag"]="tag_polychrome",
	["Investment Tag"]="tag_investment",
	["Voucher Tag"]="tag_voucher",
	["Boss Tag"]="tag_boss",
	["Charm Tag"]="tag_charm",
	["Juggle Tag"]="tag_juggle",
	["Double Tag"]="tag_double",
	["Coupon Tag"]="tag_coupon",
	["Economy Tag"]="tag_economy",
	["Speed Tag"]="tag_skip",
	["D6 Tag"]="tag_d_six",
}

GreenNeedle.SearchPackList = {
	["Any"] = {},
	["Normal Arcana"] = {"p_arcana_normal_1","p_arcana_normal_2","p_arcana_normal_3","p_arcana_normal_4"},
	["Jumbo Arcana"] = {"p_arcana_jumbo_1","p_arcana_jumbo_2"},
	["Mega Arcana"] = {"p_arcana_mega_1","p_arcana_mega_2"},
	["Normal Celestial"] = {"p_celestial_normal_1","p_celestial_normal_2","p_celestial_normal_3","p_celestial_normal_4"},
	["Jumbo Celestial"] = {"p_celestial_jumbo_1","p_celestial_jumbo_2"},
	["Mega Celestial"] = {"p_celestial_mega_1","p_celestial_mega_2"},
	["Normal Standard"] = {"p_standard_normal_1","p_standard_normal_2","p_standard_normal_3","p_standard_normal_4"},
	["Jumbo Standard"] = {"p_standard_jumbo_1","p_standard_jumbo_2"},
	["Mega Standard"] = {"p_standard_mega_1","p_standard_mega_2"},
	["Normal Buffoon"] = {"p_buffoon_normal_1","p_buffoon_normal_2"},
	["Jumbo Buffoon"] = {"p_buffoon_jumbo_1"},
	["Mega Buffoon"] = {"p_buffoon_mega_1"},
	["Normal Spectral"] = {"p_spectral_normal_1","p_spectral_normal_2"},
	["Jumbo Spectral"] = {"p_spectral_jumbo_1"},
	["Mega Spectral"] = {"p_spectral_mega_1"},
}

-- Base-tier vouchers (ante 1)
GreenNeedle.SearchVoucherList = {
	["Any"] = "",
	["Overstock"] = "v_overstock_norm",
	["Clearance Sale"] = "v_clearance_sale",
	["Hone"] = "v_hone",
	["Reroll Surplus"] = "v_reroll_surplus",
	["Crystal Ball"] = "v_crystal_ball",
	["Telescope"] = "v_telescope",
	["Grabber"] = "v_grabber",
	["Wasteful"] = "v_wasteful",
	["Tarot Merchant"] = "v_tarot_merchant",
	["Planet Merchant"] = "v_planet_merchant",
	["Seed Money"] = "v_seed_money",
	["Blank"] = "v_blank",
	["Magic Trick"] = "v_magic_trick",
	["Hieroglyph"] = "v_hieroglyph",
	["Director's Cut"] = "v_directors_cut",
	["Paint Brush"] = "v_paint_brush",
}

-- Base voucher -> upgrade voucher mapping
local voucherUpgrades = {
	["Overstock"]      = {label = "Overstock Plus", key = "v_overstock_plus"},
	["Clearance Sale"] = {label = "Liquidation",    key = "v_liquidation"},
	["Hone"]           = {label = "Glow Up",        key = "v_glow_up"},
	["Reroll Surplus"] = {label = "Reroll Glut",    key = "v_reroll_glut"},
	["Crystal Ball"]   = {label = "Omen Globe",     key = "v_omen_globe"},
	["Telescope"]      = {label = "Observatory",    key = "v_observatory"},
	["Grabber"]        = {label = "Nacho Tong",     key = "v_nacho_tong"},
	["Wasteful"]       = {label = "Recyclomancy",   key = "v_recyclomancy"},
	["Tarot Merchant"] = {label = "Tarot Tycoon",   key = "v_tarot_tycoon"},
	["Planet Merchant"]= {label = "Planet Tycoon",  key = "v_planet_tycoon"},
	["Seed Money"]     = {label = "Money Tree",     key = "v_money_tree"},
	["Blank"]          = {label = "Antimatter",     key = "v_antimatter"},
	["Magic Trick"]    = {label = "Illusion",       key = "v_illusion"},
	["Hieroglyph"]     = {label = "Petroglyph",     key = "v_petroglyph"},
	["Director's Cut"] = {label = "Retcon",         key = "v_retcon"},
	["Paint Brush"]    = {label = "Palette",        key = "v_palette"},
}

-- Build the voucher 2 options list and lookup table based on the voucher 1 selection
-- When v1 = "Any": v2 list = same base vouchers (we don't know which was purchased)
-- When v1 = specific: v2 list = base vouchers minus v1, plus v1's upgrade
function GreenNeedle.build_voucher2_options(v1_label)
	local keys = {"Any"}
	local lookup = {["Any"] = ""}
	local vkeys = GreenNeedle.searchVoucherKeys
	if not v1_label or v1_label == "Any" then
		-- Same as base list
		for i = 2, #vkeys do
			local label = vkeys[i]
			keys[#keys + 1] = label
			lookup[label] = GreenNeedle.SearchVoucherList[label]
		end
	else
		-- Collect remaining base vouchers (excluding v1) and v1's upgrade
		local items = {}
		local upgrade = voucherUpgrades[v1_label]
		if upgrade then
			items[#items + 1] = upgrade.label
			lookup[upgrade.label] = upgrade.key
		end
		for i = 2, #vkeys do
			local label = vkeys[i]
			if label ~= v1_label then
				items[#items + 1] = label
				lookup[label] = GreenNeedle.SearchVoucherList[label]
			end
		end
		table.sort(items, function(a, b) return a:lower() < b:lower() end)
		for _, label in ipairs(items) do
			keys[#keys + 1] = label
		end
	end
	return keys, lookup
end

GreenNeedle.SearchLegendaryList = {
	["Any"] = "",
	["Canio"] = "j_caino",
	["Triboulet"] = "j_triboulet",
	["Yorick"] = "j_yorick",
	["Chicot"] = "j_chicot",
	["Perkeo"] = "j_perkeo",
}

GreenNeedle.SearchSpectralCardList = {
	["Any"]         = "",
	["Familiar"]    = "c_familiar",
	["Grim"]        = "c_grim",
	["Incantation"] = "c_incantation",
	["Talisman"]    = "c_talisman",
	["Aura"]        = "c_aura",
	["Wraith"]      = "c_wraith",
	["Sigil"]       = "c_sigil",
	["Ouija"]       = "c_ouija",
	["Ectoplasm"]   = "c_ectoplasm",
	["Immolate"]    = "c_immolate",
	["Ankh"]        = "c_ankh",
	["Deja Vu"]     = "c_deja_vu",
	["Hex"]         = "c_hex",
	["Trance"]      = "c_trance",
	["Medium"]      = "c_medium",
	["Cryptid"]     = "c_cryptid",
	["Soul"]    = "c_soul",
	["Black Hole"]  = "c_black_hole",
}

GreenNeedle.SearchTarotCardList = {
	["Any"]              = "",
	["The Fool"]         = "c_fool",
	["The Magician"]     = "c_magician",
	["The High Priestess"] = "c_high_priestess",
	["The Empress"]      = "c_empress",
	["The Emperor"]      = "c_emperor",
	["The Hierophant"]   = "c_heirophant",
	["The Lovers"]       = "c_lovers",
	["The Chariot"]      = "c_chariot",
	["Justice"]          = "c_justice",
	["The Hermit"]       = "c_hermit",
	["Wheel of Fortune"] = "c_wheel_of_fortune",
	["Strength"]         = "c_strength",
	["The Hanged Man"]   = "c_hanged_man",
	["Death"]            = "c_death",
	["Temperance"]       = "c_temperance",
	["The Devil"]        = "c_devil",
	["The Tower"]        = "c_tower",
	["The Star"]         = "c_star",
	["The Moon"]         = "c_moon",
	["The Sun"]          = "c_sun",
	["Judgement"]        = "c_judgement",
	["The World"]        = "c_world",
	["Soul"]         = "c_soul",
}

GreenNeedle.SearchPlanetCardList = {
	["Any"]        = "",
	["Mercury"]    = "c_mercury",
	["Venus"]      = "c_venus",
	["Earth"]      = "c_earth",
	["Mars"]       = "c_mars",
	["Jupiter"]    = "c_jupiter",
	["Saturn"]     = "c_saturn",
	["Uranus"]     = "c_uranus",
	["Neptune"]    = "c_neptune",
	["Pluto"]      = "c_pluto",
	["Planet X"]   = "c_planet_x",
	["Ceres"]      = "c_ceres",
	["Eris"]       = "c_eris",
	["Black Hole"] = "c_black_hole",
}

GreenNeedle.SearchRareJokerList = {
	["Any"]              = "",
	["DNA"]              = "j_dna",
	["Vagabond"]         = "j_vagabond",
	["Baron"]            = "j_baron",
	["Obelisk"]          = "j_obelisk",
	["Baseball Card"]    = "j_baseball",
	["Ancient Joker"]    = "j_ancient",
	["Campfire"]         = "j_campfire",
	["Blueprint"]        = "j_blueprint",
	["Wee Joker"]        = "j_wee",
	["Hit the Road"]     = "j_hit_the_road",
	["The Duo"]          = "j_duo",
	["The Trio"]         = "j_trio",
	["The Family"]       = "j_family",
	["The Order"]        = "j_order",
	["The Tribe"]        = "j_tribe",
	["Stuntman"]         = "j_stuntman",
	["Invisible Joker"]  = "j_invisible",
	["Brainstorm"]       = "j_brainstorm",
	["Driver's License"] = "j_drivers_license",
	["Burnt Joker"]      = "j_burnt",
}

GreenNeedle.SearchWraithEditionList = {
	["Any"]          = "",
	["Negative"]     = "e_negative",
	["Polychrome"]   = "e_polychrome",
	["Holographic"]  = "e_holographic",
	["Foil"]         = "e_foil",
}

GreenNeedle.seedsPerFrame = {
	["1K"] = 1000,
	["10K"] = 10000,
	["100K"] = 100000,
	["500K"] = 500000,
	["1M"] = 1000000,
}

local searchTagKeys = {"Any", "Charm Tag", "Double Tag", "Uncommon Tag", "Rare Tag", "Holographic Tag", "Foil Tag", "Polychrome Tag", "Investment Tag", "Voucher Tag", "Boss Tag", "Juggle Tag", "Coupon Tag", "Economy Tag", "Speed Tag", "D6 Tag"}
local searchPackKeys = {"Any", "Normal Arcana", "Jumbo Arcana", "Mega Arcana", "Normal Celestial", "Jumbo Celestial", "Mega Celestial", "Normal Standard", "Jumbo Standard", "Mega Standard", "Normal Buffoon", "Jumbo Buffoon", "Mega Buffoon", "Normal Spectral", "Jumbo Spectral", "Mega Spectral"}
GreenNeedle.searchVoucherKeys = {"Any", "Blank", "Clearance Sale", "Crystal Ball", "Director's Cut", "Grabber", "Hieroglyph", "Hone", "Magic Trick", "Overstock", "Paint Brush", "Planet Merchant", "Reroll Surplus", "Seed Money", "Tarot Merchant", "Telescope", "Wasteful"}
local searchVoucherKeys = GreenNeedle.searchVoucherKeys
local searchLegendaryKeys = {"Any", "Canio", "Triboulet", "Yorick", "Chicot", "Perkeo"}
GreenNeedle.searchSpectralCardKeys = {"Any", "Ankh", "Aura", "Black Hole", "Cryptid", "Deja Vu", "Ectoplasm", "Familiar", "Grim", "Hex", "Immolate", "Incantation", "Medium", "Ouija", "Sigil", "Talisman", "Soul", "Trance", "Wraith"}
local searchSpectralCardKeys = GreenNeedle.searchSpectralCardKeys
GreenNeedle.searchTarotCardKeys = {"Any", "The Chariot", "Death", "The Devil", "The Emperor", "The Empress", "The Fool", "The Hanged Man", "The Hermit", "The High Priestess", "Judgement", "Justice", "The Lovers", "The Magician", "The Moon", "Soul", "The Star", "Strength", "The Sun", "Temperance", "The Tower", "Wheel of Fortune", "The World"}
local searchTarotCardKeys = GreenNeedle.searchTarotCardKeys
GreenNeedle.searchPlanetCardKeys = {"Any", "Black Hole", "Ceres", "Earth", "Eris", "Jupiter", "Mars", "Mercury", "Neptune", "Planet X", "Pluto", "Saturn", "Uranus", "Venus"}
local searchPlanetCardKeys = GreenNeedle.searchPlanetCardKeys
local searchRareJokerKeys = {"Any", "Ancient Joker", "Baron", "Baseball Card", "Blueprint", "Brainstorm", "Burnt Joker", "Campfire", "DNA", "Driver's License", "The Duo", "The Family", "Hit the Road", "Invisible Joker", "Obelisk", "The Order", "Stuntman", "The Tribe", "The Trio", "Vagabond", "Wee Joker"}
local searchWraithEditionKeys = {"Any", "Foil", "Holographic", "Polychrome", "Negative"}
local seedsPerFrame = {"1K", "10K", "100K", "500K", "1M"}

-- Build a card key list excluding a specific key (for card 2 exclusion)
local function build_excluded_keys(base_keys, exclude_label)
	if not exclude_label or exclude_label == "" or exclude_label == "Any" then
		return base_keys
	end
	local result = {}
	for _, k in ipairs(base_keys) do
		if k ~= exclude_label then
			result[#result + 1] = k
		end
	end
	return result
end

-- Buffoon packs use paginated selectors (same joker list as Judgement)
-- built directly in settings_panel; see build_buffoon_card_selectors below.

-- Determine which card list a given tag triggers
local function tag_card_type(tag_id)
	if tag_id == "tag_charm" then return "tarot" end
	if tag_id == "tag_uncommon" then return "tag_joker_uncommon" end
	if tag_id == "tag_rare" then return "tag_joker_rare" end
	return nil
end

-- Determine which card list a given pack selection triggers
local function pack_card_type(pack_keys_list)
	if not pack_keys_list or #pack_keys_list == 0 then return nil end
	local first = pack_keys_list[1]
	if first:find("arcana") then return "tarot" end
	if first:find("spectral") then return "spectral" end
	if first:find("celestial") then return "planet" end
	if first:find("buffoon") then return "joker" end
	return nil
end

-- Get the correct base key list for a card type
local function card_keys_for_type(card_type)
	if card_type == "tarot" then return searchTarotCardKeys end
	if card_type == "spectral" then return searchSpectralCardKeys end
	if card_type == "planet" then return searchPlanetCardKeys end
	-- joker type uses paginated selectors, handled separately
	return {}
end

-- How many card selectors to show for a pack type
-- Non-mega packs only let the player choose 1 card, so only mega needs 2 selectors
local function max_card_selectors_for_pack(pack_label)
	if pack_label:find("^Mega") then return 2 end
	return 1
end

-- Build dynamic card selector rows
-- Reverse-lookup: find the display label for a card key value in a lookup table
local function find_card_display_label(lookup_table, card_key)
	if not card_key or card_key == "" then return nil end
	for label, key in pairs(lookup_table) do
		if key == card_key then return label end
	end
	return nil
end

local function build_card_selectors(prefix, card_type, card1_id, card2_id, max_selectors, callback1, callback2, card1_key, card2_key)
	local base_keys = card_keys_for_type(card_type)
	if #base_keys == 0 then return {} end

	local lookup
	if card_type == "tarot" then lookup = GreenNeedle.SearchTarotCardList
	elseif card_type == "spectral" then lookup = GreenNeedle.SearchSpectralCardList
	elseif card_type == "planet" then lookup = GreenNeedle.SearchPlanetCardList
	else lookup = {}
	end

	local nodes = {}
	if max_selectors >= 2 then
		-- Bidirectional exclusion: card 1 excludes card 2's selection, and vice versa
		local card2_label = find_card_display_label(lookup, card2_key)
		local card1_label = find_card_display_label(lookup, card1_key)
		local keys1 = build_excluded_keys(base_keys, card2_label)
		local keys2 = build_excluded_keys(base_keys, card1_label)
		nodes[#nodes + 1] = create_option_cycle({
			label = prefix .. " Card 1",
			scale = 0.8,
			w = 4,
			options = keys1,
			opt_callback = callback1,
			current_option = card1_id or 1,
		})
		nodes[#nodes + 1] = create_option_cycle({
			label = prefix .. " Card 2",
			scale = 0.8,
			w = 4,
			options = keys2,
			opt_callback = callback2,
			current_option = card2_id or 1,
		})
	else
		nodes[#nodes + 1] = create_option_cycle({
			label = prefix .. " Card 1",
			scale = 0.8,
			w = 4,
			options = base_keys,
			opt_callback = callback1,
			current_option = card1_id or 1,
		})
	end
	return nodes
end

-- Build paginated joker card selectors for buffoon packs + edition selector.
-- Returns a list of UI nodes (similar to build_card_selectors but paginated).
local function build_buffoon_card_selectors(s, max_selectors)
	local nodes = {}
	local page1 = s.searchBuffoonCard1Page or 1
	local opts1 = GreenNeedle.build_judgement_selector(page1)
	nodes[#nodes + 1] = create_option_cycle({
		label = "Pack Card 1",
		scale = 0.8,
		w = 4,
		options = opts1,
		opt_callback = "gn_change_search_buffoon_card1",
		current_option = s.searchPackCard1ID or 2,
	})
	if max_selectors >= 2 then
		local page2 = s.searchBuffoonCard2Page or 1
		local opts2 = GreenNeedle.build_judgement_selector(page2)
		nodes[#nodes + 1] = create_option_cycle({
			label = "Pack Card 2",
			scale = 0.8,
			w = 4,
			options = opts2,
			opt_callback = "gn_change_search_buffoon_card2",
			current_option = s.searchPackCard2ID or 2,
		})
	end
	nodes[#nodes + 1] = create_option_cycle({
		label = "Buffoon Edition",
		scale = 0.8,
		w = 4,
		options = searchWraithEditionKeys,
		opt_callback = "gn_change_search_buffoon_edition",
		current_option = s.searchBuffoonEditionID or 1,
	})
	return nodes
end

-- Refresh the Green Needle tab content without leaving it.
-- Suppresses DynaText pop-in animations so the rebuild isn't flashy.
GreenNeedle._suppress_pop_in = false
local _orig_DynaText_init = DynaText.init
function DynaText:init(config, ...)
	if GreenNeedle._suppress_pop_in and config then
		config.pop_in = nil
		config.reset_pop_in = nil
	end
	return _orig_DynaText_init(self, config, ...)
end

function GreenNeedle.refresh_settings_tab()
	if G.OVERLAY_MENU then
		local container = G.OVERLAY_MENU:get_UIE_by_ID('tab_contents')
		if container then
			GreenNeedle._suppress_pop_in = true
			container.config.object:remove()
			container.config.object = UIBox{
				definition = GreenNeedle.tag_shop_panel(),
				config = {offset = {x = 0, y = 0}, parent = container, type = 'cm'},
			}
			container.UIBox:recalculate()
			GreenNeedle._suppress_pop_in = false
		end
	end
end

-- Compute the colour for the estimate text based on seed count
local function estimate_colour(est)
	if est <= 0 then
		return G.C.WHITE
	elseif est >= 1000000000000 then
		return {1, 0, 0, 1}
	elseif est <= 1000000000 then
		local t = est / 1000000000
		return {1, 1, 1 - t, 1}
	else
		local t = (est - 1000000000) / (1000000000000 - 1000000000)
		return {1, 1 - t, 0, 1}
	end
end

-- Green Needle "Tag & Shop" tab definition
function GreenNeedle.tag_shop_panel()
				local s = GreenNeedle.SETTINGS.autoreroll

				-- Dynamic card selectors for tag
				local tag_ct = tag_card_type(s.searchTag or "")
				local tag_card_nodes = {}
				if tag_ct == "tag_joker_uncommon" or tag_ct == "tag_joker_rare" then
					-- Uncommon/Rare tag: paginated joker selector filtered by rarity
					local rarity = tag_ct == "tag_joker_rare" and 3 or 2
					local page = s.searchTagJokerPage or 1
					local opts = GreenNeedle.build_rarity_selector(page, rarity)
					local label = rarity == 3 and "Rare Tag Joker" or "Uncommon Tag Joker"
					tag_card_nodes[#tag_card_nodes + 1] = create_option_cycle({
						label = label,
						scale = 0.8,
						w = 4,
						options = opts,
						opt_callback = "gn_change_search_tag_joker",
						current_option = s.searchTagJokerID or 2,
					})
				elseif tag_ct then
					tag_card_nodes = build_card_selectors(
						"Tag Pack", tag_ct,
						s.searchTagCard1ID, s.searchTagCard2ID,
						2, "gn_change_search_tag_card1", "gn_change_search_tag_card2",
						s.searchTagCard1, s.searchTagCard2
					)
				end

				-- Dynamic card selectors for shop pack
				local pack_label = ""
				for _, k in ipairs(searchPackKeys) do
					local pk = GreenNeedle.SearchPackList[k]
					if pk and s.searchPack and #s.searchPack > 0 and #pk > 0 and pk[1] == s.searchPack[1] then
						pack_label = k
						break
					end
				end
				local pack_ct = pack_card_type(s.searchPack or {})
				local pack_card_nodes = {}
				if pack_ct == "joker" then
					local max_sel = max_card_selectors_for_pack(pack_label)
					pack_card_nodes = build_buffoon_card_selectors(s, max_sel)
				elseif pack_ct then
					local max_sel = max_card_selectors_for_pack(pack_label)
					pack_card_nodes = build_card_selectors(
						"Shop Pack", pack_ct,
						s.searchPackCard1ID, s.searchPackCard2ID,
						max_sel, "gn_change_search_pack_card1", "gn_change_search_pack_card2",
						s.searchPackCard1, s.searchPackCard2
					)
				end

				-- Check if Judgement is selected as a tag card (for judgement joker selector)
				local has_judgement_tag_card = false
				if tag_ct == "tarot" then
					if (s.searchTagCard1 or "") == "c_judgement" or (s.searchTagCard2 or "") == "c_judgement" then
						has_judgement_tag_card = true
					end
				end

				-- Column 1: Skip Tag + tag pack card selectors
				local col1_nodes = {
					create_option_cycle({
						label = "Skip Tag",
						scale = 0.8,
						w = 4,
						options = searchTagKeys,
						opt_callback = "gn_change_search_tag",
						current_option = s.searchTagID or 1,
					}),
				}
				for _, node in ipairs(tag_card_nodes) do
					col1_nodes[#col1_nodes + 1] = node
				end
				if has_judgement_tag_card then
					local jud_page = s.searchJudgementPage or 1
					local jud_options = GreenNeedle.build_judgement_selector(jud_page)
					col1_nodes[#col1_nodes + 1] = create_option_cycle({
						label = "Judgement Joker",
						scale = 0.8,
						w = 4,
						options = jud_options,
						opt_callback = "gn_change_search_judgement_joker",
						current_option = s.searchJudgementJokerID or 2,
					})
					col1_nodes[#col1_nodes + 1] = create_option_cycle({
						label = "Judgement Edition",
						scale = 0.8,
						w = 4,
						options = searchWraithEditionKeys,
						opt_callback = "gn_change_search_judgement_edition",
						current_option = s.searchJudgementEditionID or 1,
					})
				end

				-- Check if Wraith is selected as a pack card (for wraith joker selector)
				local has_wraith_selected = false
				if pack_ct == "spectral" then
					if (s.searchPackCard1 or "") == "c_wraith" or (s.searchPackCard2 or "") == "c_wraith" then
						has_wraith_selected = true
					end
				end

				-- Check if Judgement is selected as a shop pack card (for shop judgement joker selector)
				local has_judgement_pack_card = false
				if pack_ct == "tarot" then
					if (s.searchPackCard1 or "") == "c_judgement" or (s.searchPackCard2 or "") == "c_judgement" then
						has_judgement_pack_card = true
					end
				end

				-- Column 2: Shop Pack + shop pack card selectors + wraith joker
				local col2_nodes = {
					create_option_cycle({
						label = "Shop Pack",
						scale = 0.8,
						w = 4,
						options = searchPackKeys,
						opt_callback = "gn_change_search_pack",
						current_option = s.searchPackID or 1,
					}),
				}
				for _, node in ipairs(pack_card_nodes) do
					col2_nodes[#col2_nodes + 1] = node
				end
				if has_wraith_selected then
					col2_nodes[#col2_nodes + 1] = create_option_cycle({
						label = "Wraith Joker",
						scale = 0.8,
						w = 4,
						options = searchRareJokerKeys,
						opt_callback = "gn_change_search_wraith_joker",
						current_option = s.searchWraithJokerID or 1,
					})
					col2_nodes[#col2_nodes + 1] = create_option_cycle({
						label = "Wraith Edition",
						scale = 0.8,
						w = 4,
						options = searchWraithEditionKeys,
						opt_callback = "gn_change_search_wraith_edition",
						current_option = s.searchWraithEditionID or 1,
					})
				end
				if has_judgement_pack_card then
					local jud_page = s.searchShopJudgementPage or 1
					local jud_options = GreenNeedle.build_judgement_selector(jud_page)
					col2_nodes[#col2_nodes + 1] = create_option_cycle({
						label = "Judgement Joker",
						scale = 0.8,
						w = 4,
						options = jud_options,
						opt_callback = "gn_change_search_shop_judgement_joker",
						current_option = s.searchShopJudgementJokerID or 2,
					})
					col2_nodes[#col2_nodes + 1] = create_option_cycle({
						label = "Judgement Edition",
						scale = 0.8,
						w = 4,
						options = searchWraithEditionKeys,
						opt_callback = "gn_change_search_shop_judgement_edition",
						current_option = s.searchShopJudgementEditionID or 1,
					})
				end

				-- Determine voucher 1 display label for dynamic voucher 2 list
				local v1_label = "Any"
				for _, k in ipairs(searchVoucherKeys) do
					if GreenNeedle.SearchVoucherList[k] == (s.searchVoucher or "") then
						v1_label = k
						break
					end
				end
				local v2_keys, v2_lookup = GreenNeedle.build_voucher2_options(v1_label)

				-- Compute search estimate for display
				local est = GreenNeedle.estimate_search_seeds()

				-- Check if Soul is selected in any card slot
				local has_soul_selected = (s.searchTagCard1 or "") == "c_soul"
					or (s.searchTagCard2 or "") == "c_soul"
					or (s.searchPackCard1 or "") == "c_soul"
					or (s.searchPackCard2 or "") == "c_soul"

				-- Column 3: Vouchers, Legendary, Seeds per Frame, native status
				local col3_nodes = {
					create_option_cycle({
						label = "Voucher Ante 1",
						scale = 0.8,
						w = 4,
						options = searchVoucherKeys,
						opt_callback = "gn_change_search_voucher",
						current_option = s.searchVoucherID or 1,
					}),
					create_option_cycle({
						label = "Voucher Ante 2",
						scale = 0.8,
						w = 4,
						options = v2_keys,
						opt_callback = "gn_change_search_voucher2",
						current_option = s.searchVoucher2ID or 1,
					}),
					}
				col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm", minh=0.3}, nodes={}}
				if has_soul_selected then
					col3_nodes[#col3_nodes + 1] = create_option_cycle({
						label = "Legendary",
						scale = 0.8,
						w = 4,
						options = searchLegendaryKeys,
						opt_callback = "gn_change_search_legendary",
						current_option = s.searchLegendaryID or 1,
					})
					col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm", minh=0.53}, nodes={}}
				else
					col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm", minh=2}, nodes={}}
				end
				col3_nodes[#col3_nodes + 1] = create_option_cycle({
						label = "Seeds per Frame",
						scale = 0.8,
						w = 4,
						options = seedsPerFrame,
						opt_callback = "gn_change_seeds_per_frame",
						current_option = s.seedsPerFrameID or 1,
					})
				col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm"}, nodes={
						{n=G.UIT.T, config={
							text = GreenNeedle.native and "Native search: enabled" or "Native search: unavailable (Lua fallback)",
							scale = 0.3,
							colour = GreenNeedle.native and G.C.GREEN or G.C.RED,
						}},
					}}
				GreenNeedle._estimateDisplayText = GreenNeedle._estimateDisplayText or {}
				local max_seeds = 2251875390625 -- 35^8
				if est > max_seeds then
					GreenNeedle._estimateDisplayText.value = "Est. 1 in " .. GreenNeedle.format_seed_count(est) .. " (unlikely)"
				elseif est > 0 then
					GreenNeedle._estimateDisplayText.value = "Est. 1 in " .. GreenNeedle.format_seed_count(est)
				else
					GreenNeedle._estimateDisplayText.value = "Est. 1 in 1"
				end
				local est_colour = estimate_colour(est)
				GreenNeedle._estimateColour = GreenNeedle._estimateColour or {1, 1, 1, 1}
				GreenNeedle._estimateColour[1] = est_colour[1]
				GreenNeedle._estimateColour[2] = est_colour[2]
				GreenNeedle._estimateColour[3] = est_colour[3]
				GreenNeedle._estimateColour[4] = est_colour[4]
				col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm"}, nodes={
						{n=G.UIT.T, config={
							ref_table = GreenNeedle._estimateDisplayText,
							ref_value = "value",
							scale = 0.3,
							colour = GreenNeedle._estimateColour,
						}},
					}}

				local col1 = {n=G.UIT.C, config={align="tm", padding=0.05, minw=3.5}, nodes=col1_nodes}
				local col2 = {n=G.UIT.C, config={align="tm", padding=0.05, minw=3.5}, nodes=col2_nodes}
				local col3 = {n=G.UIT.C, config={align="tm", padding=0.05, minw=3.5}, nodes=col3_nodes}

				local row = {n=G.UIT.R, config={align="cm"}, nodes={col1, col2, col3}}

				return {
					n = G.UIT.ROOT,
					config = {
						align = "cm",
						padding = 0.05,
						colour = G.C.CLEAR,
					},
					nodes = {row},
				}, row
end


-- Erratic deck search selectors
local erraticRankKeys = {"Any", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace"}

-- Helper: wrap a bare slider (no label) with a dynamic label above it
local function labeled_slider(label_ref, slider_node)
	return {n=G.UIT.R, config={align = "cm", minh = 1, minw = 1, padding = 0.035, colour = G.C.CLEAR}, nodes={
		{n=G.UIT.R, config={align = "cm", padding = 0}, nodes={
			{n=G.UIT.T, config={ref_table = label_ref, ref_value = "value", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
		}},
		{n=G.UIT.R, config={align = "cm", padding = 0}, nodes={
			slider_node,
		}},
	}}
end

-- Helper: build a slider pair (min + max) for an erratic count filter.
-- If the user drags one past the other, the two swap roles.
local function erratic_slider_pair(label, ref_table, min_key, max_key, callback)
	local top_args = {
		w = 3, h = 0.3,
		ref_table = ref_table, ref_value = min_key,
		min = 0, max = 52, decimal_places = 0,
	}
	local bot_args = {
		w = 3, h = 0.3,
		ref_table = ref_table, ref_value = max_key,
		min = 0, max = 52, decimal_places = 0,
	}
	local top_label = {value = "Min " .. label}
	local bot_label = {value = "Max " .. label}
	local function maybe_swap()
		local mn = math.floor((ref_table[min_key] or 0) + 0.5)
		local mx = math.floor((ref_table[max_key] or 52) + 0.5)
		-- Swap if min > max, or if equal and top slider is currently the max
		if mn > mx or (mn == mx and top_args.ref_value == max_key) then
			ref_table[min_key] = mx
			ref_table[max_key] = mn
			-- Swap which key each slider writes to
			top_args.ref_value, bot_args.ref_value = bot_args.ref_value, top_args.ref_value
			-- Update displayed number text
			top_args.text = string.format("%.0f", ref_table[top_args.ref_value])
			bot_args.text = string.format("%.0f", ref_table[bot_args.ref_value])
			-- Swap labels
			top_label.value, bot_label.value = bot_label.value, top_label.value
		end
	end
	local cb_top = "gn_erratic_" .. min_key
	local cb_bot = "gn_erratic_" .. max_key
	G.FUNCS[cb_top] = function(rt)
		maybe_swap()
		G.FUNCS[callback](rt)
	end
	G.FUNCS[cb_bot] = function(rt)
		maybe_swap()
		G.FUNCS[callback](rt)
	end
	top_args.callback = cb_top
	bot_args.callback = cb_bot
	return {
		labeled_slider(top_label, create_slider(top_args)),
		labeled_slider(bot_label, create_slider(bot_args)),
	}
end

-- Build rank option keys excluding ranks already selected by other rank slots
local function erratic_rank_options(s, slot_index)
	local used = {}
	for i = 1, 4 do
		if i ~= slot_index and (s["rank" .. i .. "ID"] or 1) > 1 then
			used[s["rank" .. i]] = true
		end
	end
	local opts = {}
	for _, r in ipairs(erraticRankKeys) do
		if r == "Any" or not used[r] then
			opts[#opts + 1] = r
		end
	end
	return opts
end

-- Find the current_option index in a filtered options list
local function erratic_rank_current(opts, rank_val)
	if not rank_val or rank_val == "Any" then return 1 end
	for i, v in ipairs(opts) do
		if v == rank_val then return i end
	end
	return 1 -- fell out (rank was removed), reset to Any
end

-- Spacer matching the height of two sliders (min + max)
local function erratic_slider_spacer()
	return {n=G.UIT.R, config={align = "cm", minh = 2.06, colour = G.C.CLEAR}, nodes={}}
end

-- Build a rank selector block: cycle + sliders or spacer
local function erratic_rank_block(s, i)
	local nodes = {}
	local opts = erratic_rank_options(s, i)
	local cur = erratic_rank_current(opts, s["rank" .. i])
	nodes[#nodes + 1] = create_option_cycle({
		label = "Rank " .. i,
		scale = 0.8,
		w = 4,
		options = opts,
		opt_callback = "gn_erratic_rank" .. i,
		current_option = cur,
	})
	if (s["rank" .. i] or "Any") ~= "Any" then
		local rank_name = s["rank" .. i]
		local plural = rank_name .. "s"
		local sliders = erratic_slider_pair(
			plural, s,
			"rank" .. i .. "Min", "rank" .. i .. "Max",
			"gn_erratic_save"
		)
		for _, sl in ipairs(sliders) do
			nodes[#nodes + 1] = sl
		end
	else
		nodes[#nodes + 1] = erratic_slider_spacer()
	end
	return nodes
end

-- Helper: format an estimate value into text and colour
local function format_estimate(est)
	local max_seeds = 2251875390625 -- 35^8
	local text
	if est > max_seeds then
		text = "Est. 1 in " .. GreenNeedle.format_seed_count(est) .. " (unlikely)"
	elseif est > 0 then
		text = "Est. 1 in " .. GreenNeedle.format_seed_count(est)
	else
		text = "Est. 1 in 1"
	end
	return text, estimate_colour(est)
end

-- Helper: update a text/colour ref pair in-place
local function update_estimate_ref(text_ref, colour_ref, est)
	if not text_ref then return end
	local text, colour = format_estimate(est)
	text_ref.value = text
	if colour_ref then
		colour_ref[1] = colour[1]
		colour_ref[2] = colour[2]
		colour_ref[3] = colour[3]
		colour_ref[4] = colour[4]
	end
end

-- Green Needle "Erratic" tab definition
function GreenNeedle.erratic_panel()
	local s = GreenNeedle.SETTINGS.erratic
	if not s then
		GreenNeedle.SETTINGS.erratic = {}
		s = GreenNeedle.SETTINGS.erratic
	end

	-- Ensure defaults
	for i = 1, 4 do
		if not s["rank" .. i] then s["rank" .. i] = "Any" end
		if not s["rank" .. i .. "ID"] then s["rank" .. i .. "ID"] = 1 end
		if not s["rank" .. i .. "Min"] then s["rank" .. i .. "Min"] = 0 end
		if not s["rank" .. i .. "Max"] then s["rank" .. i .. "Max"] = 52 end
	end
	for _, suit in ipairs({"clubs", "diamonds", "hearts", "spades"}) do
		if not s[suit .. "Min"] then s[suit .. "Min"] = 0 end
		if not s[suit .. "Max"] then s[suit .. "Max"] = 52 end
	end

	-- Column 1: All four suits
	local col1_nodes = {}
	local suits = {"clubs", "diamonds", "hearts", "spades"}
	for si, suit in ipairs(suits) do
		local label = suit:sub(1,1):upper() .. suit:sub(2)
		local sliders = erratic_slider_pair(label, s, suit .. "Min", suit .. "Max", "gn_erratic_save")
		for _, sl in ipairs(sliders) do
			col1_nodes[#col1_nodes + 1] = sl
		end
		if si < #suits then
			col1_nodes[#col1_nodes + 1] = {n=G.UIT.R, config={align = "cm", minh = 0.25, colour = G.C.CLEAR}, nodes={}}
		end
	end

	-- Column 2: Rank 1 + spacer + Rank 3 + erratic-only estimate
	local col2_nodes = {}
	local r1 = erratic_rank_block(s, 1)
	for _, n in ipairs(r1) do col2_nodes[#col2_nodes + 1] = n end
	col2_nodes[#col2_nodes + 1] = {n=G.UIT.R, config={align = "cm", minh = 1.0, colour = G.C.CLEAR}, nodes={}}
	local r3 = erratic_rank_block(s, 3)
	for _, n in ipairs(r3) do col2_nodes[#col2_nodes + 1] = n end

	-- Erratic-only estimate at bottom of col 2
	local erratic_est = GreenNeedle.estimate_erratic_seeds()
	GreenNeedle._erraticEstText = GreenNeedle._erraticEstText or {}
	GreenNeedle._erraticEstColour = GreenNeedle._erraticEstColour or {1, 1, 1, 1}
	local e_text, e_colour = format_estimate(erratic_est)
	GreenNeedle._erraticEstText.value = e_text
	GreenNeedle._erraticEstColour[1] = e_colour[1]
	GreenNeedle._erraticEstColour[2] = e_colour[2]
	GreenNeedle._erraticEstColour[3] = e_colour[3]
	GreenNeedle._erraticEstColour[4] = e_colour[4]
	col2_nodes[#col2_nodes + 1] = {n=G.UIT.R, config={align = "cm", minh = 0.5, colour = G.C.CLEAR}, nodes={}}
	col2_nodes[#col2_nodes + 1] = {n=G.UIT.R, config={align="cm"}, nodes={
		{n=G.UIT.T, config={text = "Erratic only", scale = 0.25, colour = G.C.WHITE}},
	}}
	col2_nodes[#col2_nodes + 1] = {n=G.UIT.R, config={align="cm"}, nodes={
		{n=G.UIT.T, config={
			ref_table = GreenNeedle._erraticEstText,
			ref_value = "value",
			scale = 0.3,
			colour = GreenNeedle._erraticEstColour,
		}},
	}}

	-- Column 3: Rank 2 + spacer + Rank 4 + combined estimate
	local col3_nodes = {}
	local r2 = erratic_rank_block(s, 2)
	for _, n in ipairs(r2) do col3_nodes[#col3_nodes + 1] = n end
	col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align = "cm", minh = 1.0, colour = G.C.CLEAR}, nodes={}}
	local r4 = erratic_rank_block(s, 4)
	for _, n in ipairs(r4) do col3_nodes[#col3_nodes + 1] = n end

	-- Combined estimate at bottom of col 3 (always includes erratic)
	local combined_est = GreenNeedle.estimate_combined_seeds()
	GreenNeedle._combinedEstText = GreenNeedle._combinedEstText or {}
	GreenNeedle._combinedEstColour = GreenNeedle._combinedEstColour or {1, 1, 1, 1}
	local c_text, c_colour = format_estimate(combined_est)
	GreenNeedle._combinedEstText.value = c_text
	GreenNeedle._combinedEstColour[1] = c_colour[1]
	GreenNeedle._combinedEstColour[2] = c_colour[2]
	GreenNeedle._combinedEstColour[3] = c_colour[3]
	GreenNeedle._combinedEstColour[4] = c_colour[4]
	col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align = "cm", minh = 0.5, colour = G.C.CLEAR}, nodes={}}
	col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm"}, nodes={
		{n=G.UIT.T, config={text = "Combined", scale = 0.25, colour = G.C.WHITE}},
	}}
	col3_nodes[#col3_nodes + 1] = {n=G.UIT.R, config={align="cm"}, nodes={
		{n=G.UIT.T, config={
			ref_table = GreenNeedle._combinedEstText,
			ref_value = "value",
			scale = 0.3,
			colour = GreenNeedle._combinedEstColour,
		}},
	}}

	return {n=G.UIT.ROOT, config={align = "cm", padding = 0.05, colour = G.C.CLEAR}, nodes={
		{n=G.UIT.R, config={align = "tm", padding = 0.08}, nodes={
			{n=G.UIT.C, config={align = "tm", padding = 0.05, minw = 4.5}, nodes=col1_nodes},
			{n=G.UIT.C, config={align = "tm", padding = 0.05, minw = 4.5}, nodes=col2_nodes},
			{n=G.UIT.C, config={align = "tm", padding = 0.05, minw = 4.5}, nodes=col3_nodes},
		}},
	}}
end

-- Update all estimate texts in-place without rebuilding the UI
function GreenNeedle.update_estimate_text()
	-- Tag & Shop panel estimate
	update_estimate_ref(GreenNeedle._estimateDisplayText, GreenNeedle._estimateColour,
		GreenNeedle.estimate_search_seeds())
	-- Erratic panel: erratic-only estimate
	update_estimate_ref(GreenNeedle._erraticEstText, GreenNeedle._erraticEstColour,
		GreenNeedle.estimate_erratic_seeds())
	-- Erratic panel: combined estimate (always includes erratic)
	update_estimate_ref(GreenNeedle._combinedEstText, GreenNeedle._combinedEstColour,
		GreenNeedle.estimate_combined_seeds())
end

-- Main menu button callback: open Green Needle settings as an overlay
G.FUNCS.greenneedle_config = function(e)
	G.SETTINGS.paused = true
	GreenNeedle._suppress_pop_in = true
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			back_func = "options",
			contents = {create_tabs({
				tabs = {
					{
						label = "Tag & Shop",
						chosen = true,
						tab_definition_function = GreenNeedle.tag_shop_panel,
					},
					{
						label = "Erratic",
						tab_definition_function = GreenNeedle.erratic_panel,
					},
				},
				scale = 1.3,
				tab_h = 7.05,
				tab_alignment = "tm",
				snap_to_nav = true,
			})},
		}),
		config = {offset = {x = 0, y = 0}},
	})
	GreenNeedle._suppress_pop_in = false
end

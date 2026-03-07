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
		-- Add the upgrade of v1 first (most likely reason to filter ante 2)
		local upgrade = voucherUpgrades[v1_label]
		if upgrade then
			keys[#keys + 1] = upgrade.label
			lookup[upgrade.label] = upgrade.key
		end
		-- Add remaining base vouchers (excluding v1, which was already purchased)
		for i = 2, #vkeys do
			local label = vkeys[i]
			if label ~= v1_label then
				keys[#keys + 1] = label
				lookup[label] = GreenNeedle.SearchVoucherList[label]
			end
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
	["The Soul"]    = "c_soul",
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
	["The Wheel of Fortune"] = "c_wheel_of_fortune",
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
	["The Soul"]         = "c_soul",
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
GreenNeedle.searchVoucherKeys = {"Any", "Overstock", "Clearance Sale", "Hone", "Reroll Surplus", "Crystal Ball", "Telescope", "Grabber", "Wasteful", "Tarot Merchant", "Planet Merchant", "Seed Money", "Blank", "Magic Trick", "Hieroglyph", "Director's Cut", "Paint Brush"}
local searchVoucherKeys = GreenNeedle.searchVoucherKeys
local searchLegendaryKeys = {"Any", "Canio", "Triboulet", "Yorick", "Chicot", "Perkeo"}
local searchSpectralCardKeys = {"Any", "Familiar", "Grim", "Incantation", "Talisman", "Aura", "Wraith", "Sigil", "Ouija", "Ectoplasm", "Immolate", "Ankh", "Deja Vu", "Hex", "Trance", "Medium", "Cryptid", "The Soul", "Black Hole"}
local searchTarotCardKeys = {"Any", "The Fool", "The Magician", "The High Priestess", "The Empress", "The Emperor", "The Hierophant", "The Lovers", "The Chariot", "Justice", "The Hermit", "The Wheel of Fortune", "Strength", "The Hanged Man", "Death", "Temperance", "The Devil", "The Tower", "The Star", "The Moon", "The Sun", "Judgement", "The World", "The Soul"}
local searchRareJokerKeys = {"Any", "DNA", "Vagabond", "Baron", "Obelisk", "Baseball Card", "Ancient Joker", "Campfire", "Blueprint", "Wee Joker", "Hit the Road", "The Duo", "The Trio", "The Family", "The Order", "The Tribe", "Stuntman", "Invisible Joker", "Brainstorm", "Driver's License", "Burnt Joker"}
local searchWraithEditionKeys = {"Any", "Negative", "Polychrome", "Holographic", "Foil"}
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

-- Determine which card list a given tag triggers
local function tag_card_type(tag_id)
	if tag_id == "tag_charm" then return "tarot" end
	return nil
end

-- Determine which card list a given pack selection triggers
local function pack_card_type(pack_keys_list)
	if not pack_keys_list or #pack_keys_list == 0 then return nil end
	local first = pack_keys_list[1]
	if first:find("arcana") then return "tarot" end
	if first:find("spectral") then return "spectral" end
	return nil
end

-- Get the correct base key list for a card type
local function card_keys_for_type(card_type)
	if card_type == "tarot" then return searchTarotCardKeys end
	if card_type == "spectral" then return searchSpectralCardKeys end
	return {}
end

-- How many card selectors to show for a pack type
-- Non-mega packs only let the player choose 1 card, so only mega needs 2 selectors
local function max_card_selectors_for_pack(pack_label)
	if pack_label:find("^Mega") then return 2 end
	return 1
end

-- Build dynamic card selector rows
local function build_card_selectors(prefix, card_type, card1_id, card2_id, max_selectors, callback1, callback2)
	local base_keys = card_keys_for_type(card_type)
	if #base_keys == 0 then return {} end

	local nodes = {}
	nodes[#nodes + 1] = create_option_cycle({
		label = prefix .. " Card 1",
		scale = 0.8,
		w = 4,
		options = base_keys,
		opt_callback = callback1,
		current_option = card1_id or 1,
	})
	if max_selectors >= 2 then
		local card1_display = (card1_id and card1_id > 1) and base_keys[card1_id] or nil
		local keys2 = build_excluded_keys(base_keys, card1_display)
		nodes[#nodes + 1] = create_option_cycle({
			label = prefix .. " Card 2",
			scale = 0.8,
			w = 4,
			options = keys2,
			opt_callback = callback2,
			current_option = card2_id or 1,
		})
	end
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
		local tab_but = G.OVERLAY_MENU:get_UIE_by_ID('tab_but_Green Needle')
		if tab_but then
			GreenNeedle._suppress_pop_in = true
			G.FUNCS.change_tab(tab_but)
			GreenNeedle._suppress_pop_in = false
		end
	end
end

local ct = create_tabs
function create_tabs(args)
	if args and args.tab_h == 7.05 then
		args.tabs[#args.tabs + 1] = {
			label = "Green Needle",
			tab_definition_function = function()
				local s = GreenNeedle.SETTINGS.autoreroll

				-- Dynamic card selectors for tag
				local tag_ct = tag_card_type(s.searchTag or "")
				local tag_card_nodes = {}
				if tag_ct then
					tag_card_nodes = build_card_selectors(
						"Tag Pack", tag_ct,
						s.searchTagCard1ID, s.searchTagCard2ID,
						2, "gn_change_search_tag_card1", "gn_change_search_tag_card2"
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
				if pack_ct then
					local max_sel = max_card_selectors_for_pack(pack_label)
					pack_card_nodes = build_card_selectors(
						"Shop Pack", pack_ct,
						s.searchPackCard1ID, s.searchPackCard2ID,
						max_sel, "gn_change_search_pack_card1", "gn_change_search_pack_card2"
					)
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

				-- Check if Wraith is selected as a pack card (for wraith joker selector)
				local has_wraith_selected = false
				if pack_ct == "spectral" then
					if (s.searchPackCard1 or "") == "c_wraith" or (s.searchPackCard2 or "") == "c_wraith" then
						has_wraith_selected = true
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
					{n=G.UIT.R, config={align="cm", minh=0.3}, nodes={}},
					create_option_cycle({
						label = "Legendary",
						scale = 0.8,
						w = 4,
						options = searchLegendaryKeys,
						opt_callback = "gn_change_search_legendary",
						current_option = s.searchLegendaryID or 1,
					}),
					{n=G.UIT.R, config={align="cm", minh=0.3}, nodes={}},
					create_option_cycle({
						label = "Seeds per Frame",
						scale = 0.8,
						w = 4,
						options = seedsPerFrame,
						opt_callback = "gn_change_seeds_per_frame",
						current_option = s.seedsPerFrameID or 1,
					}),
					{n=G.UIT.R, config={align="cm"}, nodes={
						{n=G.UIT.T, config={
							text = GreenNeedle.native and "Native search: enabled" or "Native search: unavailable (Lua fallback)",
							scale = 0.3,
							colour = GreenNeedle.native and G.C.GREEN or G.C.RED,
						}},
					}},
					{n=G.UIT.R, config={align="cm"}, nodes={
						{n=G.UIT.T, config={
							id = "gn_estimate_text",
							text = est > 0 and ("Est. ~" .. GreenNeedle.format_seed_count(est) .. " seeds") or "",
							scale = 0.3,
							colour = G.C.WHITE,
						}},
					}},
				}

				local col1 = {n=G.UIT.C, config={align="tm", padding=0.05, minw=3.5}, nodes=col1_nodes}
				local col2 = {n=G.UIT.C, config={align="tm", padding=0.05, minw=3.5}, nodes=col2_nodes}
				local col3 = {n=G.UIT.C, config={align="tm", padding=0.05, minw=3.5}, nodes=col3_nodes}

				return {
					n = G.UIT.ROOT,
					config = {
						align = "cm",
						padding = 0.05,
						colour = G.C.CLEAR,
					},
					nodes = {
						{n=G.UIT.R, config={align="cm"}, nodes={col1, col2, col3}},
					},
				}
			end,
			tab_definition_function_args = "GreenNeedle",
		}
	end
	return ct(args)
end

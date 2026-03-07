-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local lovely = require("lovely")
local nativefs = require("nativefs")

GreenNeedle.AUTOREROLL = {}
GreenNeedle.AUTOREROLL.autoRerollActive = false
GreenNeedle.AUTOREROLL.rerollInterval = 0.01
GreenNeedle.AUTOREROLL.rerollTimer = 0

-- ---------------------------------------------------------------------------
-- Native C library (optional, macOS dylib for fast seed searching)
-- Falls back to pure-Lua implementation if unavailable.
-- ---------------------------------------------------------------------------
GreenNeedle.native = nil
GreenNeedle.ffi = nil
do
    local ok, ffi = pcall(require, "ffi")
    if ok and ffi then
        ffi.cdef[[
            const char *greenneedle_search(
                const char *start_seed,
                int         max_seeds,
                const char *tag,
                const char *pack_list,
                const char *voucher,
                const char *legendary,
                const char *spectral_card,
                uint32_t    tag_avail_mask,
                const char *tarot_card,
                const char *tarot_key_append,
                int         tarot_pack_size,
                const char *voucher2,
                const char *tarot_card2,
                const char *spectral_card2,
                const char *wraith_joker,
                uint32_t    rare_joker_mask,
                const char *wraith_edition,
                int         spectral_pack_size
            );
        ]]
        local dylib_path = lovely.mod_dir .. "/GreenNeedle/greenneedle.dylib"
        if nativefs.getInfo(dylib_path) then
            local lib_ok, lib = pcall(ffi.load, dylib_path)
            if lib_ok and lib then
                GreenNeedle.native = lib
                GreenNeedle.ffi = ffi
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Settings change callbacks
-- ---------------------------------------------------------------------------

G.FUNCS.gn_change_search_tag = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchTagID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchTag = GreenNeedle.SearchTagList[x.to_val]
	-- Reset tag card filters when tag changes
	GreenNeedle.SETTINGS.autoreroll.searchTagCard1 = ""
	GreenNeedle.SETTINGS.autoreroll.searchTagCard1ID = 1
	GreenNeedle.SETTINGS.autoreroll.searchTagCard2 = ""
	GreenNeedle.SETTINGS.autoreroll.searchTagCard2ID = 1
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_pack = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchPackID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchPack = GreenNeedle.SearchPackList[x.to_val]
	-- Reset pack card filters when pack changes
	GreenNeedle.SETTINGS.autoreroll.searchPackCard1 = ""
	GreenNeedle.SETTINGS.autoreroll.searchPackCard1ID = 1
	GreenNeedle.SETTINGS.autoreroll.searchPackCard2 = ""
	GreenNeedle.SETTINGS.autoreroll.searchPackCard2ID = 1
	GreenNeedle.SETTINGS.autoreroll.searchWraithJoker = ""
	GreenNeedle.SETTINGS.autoreroll.searchWraithJokerID = 1
	GreenNeedle.SETTINGS.autoreroll.searchWraithEdition = ""
	GreenNeedle.SETTINGS.autoreroll.searchWraithEditionID = 1
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_seeds_per_frame = function(x)
	GreenNeedle.SETTINGS.autoreroll.seedsPerFrameID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.seedsPerFrame = GreenNeedle.seedsPerFrame[x.to_val]
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
end

G.FUNCS.gn_change_search_voucher = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchVoucherID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchVoucher = GreenNeedle.SearchVoucherList[x.to_val]
	-- Reset voucher 2 when voucher 1 changes (list depends on v1)
	GreenNeedle.SETTINGS.autoreroll.searchVoucher2 = ""
	GreenNeedle.SETTINGS.autoreroll.searchVoucher2ID = 1
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_voucher2 = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchVoucher2ID = x.to_key
	-- Look up the key using the dynamic list built for the current v1 selection
	local v1_label = "Any"
	for _, k in ipairs(GreenNeedle.searchVoucherKeys) do
		if GreenNeedle.SearchVoucherList[k] == (GreenNeedle.SETTINGS.autoreroll.searchVoucher or "") then
			v1_label = k
			break
		end
	end
	local _, v2_lookup = GreenNeedle.build_voucher2_options(v1_label)
	GreenNeedle.SETTINGS.autoreroll.searchVoucher2 = v2_lookup[x.to_val] or ""
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_legendary = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchLegendaryID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchLegendary = GreenNeedle.SearchLegendaryList[x.to_val]
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_tag_card1 = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchTagCard1ID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchTagCard1 = GreenNeedle.SearchTarotCardList[x.to_val]
	-- Reset card 2 when card 1 changes (excluded list shifts)
	GreenNeedle.SETTINGS.autoreroll.searchTagCard2 = ""
	GreenNeedle.SETTINGS.autoreroll.searchTagCard2ID = 1
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_tag_card2 = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchTagCard2ID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchTagCard2 = GreenNeedle.SearchTarotCardList[x.to_val]
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_pack_card1 = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchPackCard1ID = x.to_key
	local pack_type = GreenNeedle.get_pack_card_type()
	if pack_type == "spectral" then
		GreenNeedle.SETTINGS.autoreroll.searchPackCard1 = GreenNeedle.SearchSpectralCardList[x.to_val]
	else
		GreenNeedle.SETTINGS.autoreroll.searchPackCard1 = GreenNeedle.SearchTarotCardList[x.to_val]
	end
	-- Reset card 2 when card 1 changes (excluded list shifts)
	local s = GreenNeedle.SETTINGS.autoreroll
	s.searchPackCard2 = ""
	s.searchPackCard2ID = 1
	-- Only reset wraith if wraith is no longer selected in either card slot
	if s.searchPackCard1 ~= "c_wraith" then
		s.searchWraithJoker = ""
		s.searchWraithJokerID = 1
		s.searchWraithEdition = ""
		s.searchWraithEditionID = 1
	end
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_wraith_joker = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchWraithJokerID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchWraithJoker = GreenNeedle.SearchRareJokerList[x.to_val]
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_wraith_edition = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchWraithEditionID = x.to_key
	GreenNeedle.SETTINGS.autoreroll.searchWraithEdition = GreenNeedle.SearchWraithEditionList[x.to_val]
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

G.FUNCS.gn_change_search_pack_card2 = function(x)
	GreenNeedle.SETTINGS.autoreroll.searchPackCard2ID = x.to_key
	local pack_type = GreenNeedle.get_pack_card_type()
	if pack_type == "spectral" then
		GreenNeedle.SETTINGS.autoreroll.searchPackCard2 = GreenNeedle.SearchSpectralCardList[x.to_val]
	else
		GreenNeedle.SETTINGS.autoreroll.searchPackCard2 = GreenNeedle.SearchTarotCardList[x.to_val]
	end
	-- Only reset wraith if wraith is no longer selected in either card slot
	local s = GreenNeedle.SETTINGS.autoreroll
	if (s.searchPackCard1 or "") ~= "c_wraith" and s.searchPackCard2 ~= "c_wraith" then
		s.searchWraithJoker = ""
		s.searchWraithJokerID = 1
		s.searchWraithEdition = ""
		s.searchWraithEditionID = 1
	end
	nativefs.write(lovely.mod_dir .. "/GreenNeedle/settings.lua", STR_PACK(GreenNeedle.SETTINGS))
	GreenNeedle.refresh_settings_tab()
end

-- Helper: determine the number of card slots for the currently selected shop pack variant
function GreenNeedle.get_pack_slot_count()
	local s = GreenNeedle.SETTINGS.autoreroll
	if not s.searchPack or #s.searchPack == 0 then return 0 end
	local first = s.searchPack[1]
	if first:find("normal") then
		if first:find("arcana") then return 3 end
		if first:find("spectral") then return 2 end
	end
	if first:find("arcana") then return 5 end
	if first:find("spectral") then return 4 end
	return 0
end

-- Helper: determine what card type the currently selected shop pack uses
function GreenNeedle.get_pack_card_type()
	local s = GreenNeedle.SETTINGS.autoreroll
	if s.searchPack and #s.searchPack > 0 then
		local first = s.searchPack[1]
		if first:find("spectral") then return "spectral"
		elseif first:find("arcana") then return "tarot"
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Prediction functions
-- ---------------------------------------------------------------------------

-- pseudoseed: replicates Balatro's pseudoseed(key, predict_seed) predict path
function GreenNeedle.pseudoseed(key, predict_seed)
	if key == "seed" then
		return math.random()
	end

	if predict_seed then
		local _pseed = pseudohash(key .. (predict_seed or ""))
		_pseed = math.abs(tonumber(string.format("%.13f", (2.134453429141 + _pseed * 1.72431234) % 1)))
		return (_pseed + (pseudohash(predict_seed) or 0)) / 2
	end

	if not GreenNeedle.random_state[key] then
		GreenNeedle.random_state[key] = pseudohash(key .. (GreenNeedle.random_state.seed or ""))
	end

	GreenNeedle.random_state[key] =
		math.abs(tonumber(string.format("%.13f", (2.134453429141 + GreenNeedle.random_state[key] * 1.72431234) % 1)))
	return (GreenNeedle.random_state[key] + (GreenNeedle.random_state.hashed_seed or 0)) / 2
end

-- pseudoseed with N advances (replicates stateful pseudoseed called N times)
function GreenNeedle.pseudoseed_advance(key, seed, advances)
	local state = pseudohash(key .. seed)
	for i = 1, advances do
		state = math.abs(tonumber(string.format("%.13f", (2.134453429141 + state * 1.72431234) % 1)))
	end
	return (state + pseudohash(seed)) / 2
end

-- Build voucher pool for prediction
function GreenNeedle.build_voucher_pool(used_vouchers)
	used_vouchers = used_vouchers or {}
	local pool = {}
	for k, v in ipairs(G.P_CENTER_POOLS['Voucher']) do
		local add = false
		if v.set == 'Voucher' and not used_vouchers[v.key] then
			local include = true
			if v.requires then
				for _, req in pairs(v.requires) do
					if not used_vouchers[req] then
						include = false
					end
				end
			end
			if include then add = true end
		end
		if add then
			pool[#pool + 1] = v.key
		else
			pool[#pool + 1] = 'UNAVAILABLE'
		end
	end
	return pool
end

-- Predict which voucher key appears for a given seed and ante
function GreenNeedle.predict_voucher(seed, ante, used_vouchers)
	ante = ante or 1
	used_vouchers = used_vouchers or {}
	local state = pseudohash('Voucher' .. seed)
	for i = 1, ante - 1 do
		state = math.abs(tonumber(string.format("%.13f", (2.134453429141 + state * 1.72431234) % 1)))
	end
	local hashed = pseudohash(seed)
	local pseed = (state + hashed) / 2

	local pool = GreenNeedle.build_voucher_pool(used_vouchers)
	local _, key = pseudorandom_element(pool, pseed)
	local resample = 1
	while pool[key] == 'UNAVAILABLE' do
		_, key = pseudorandom_element(pool, GreenNeedle.pseudoseed('Voucher' .. ante .. '_resample' .. (resample + 1), seed))
		resample = resample + 1
	end
	return pool[key]
end

-- Build legendary joker pool
function GreenNeedle.build_legendary_pool()
	local pool = {}
	for k, v in ipairs(G.P_JOKER_RARITY_POOLS[4]) do
		pool[#pool + 1] = v.key
	end
	return pool
end

-- Predict which legendary joker appears for a given seed
function GreenNeedle.predict_legendary(seed)
	local pool = GreenNeedle.build_legendary_pool()
	local pseed = GreenNeedle.pseudoseed('Joker4', seed)
	local _, key = pseudorandom_element(pool, pseed)
	return pool[key]
end

-- Build a 24-bit bitmask of tag availability for the current profile/ante
function GreenNeedle.build_tag_avail_mask(ante)
	ante = ante or 1
	local mask = 0
	for i, v in ipairs(G.P_CENTER_POOLS["Tag"]) do
		local available = true
		if v.min_ante and v.min_ante > ante then
			available = false
		end
		if v.requires and available then
			local req_center = G.P_CENTERS[v.requires]
			if not req_center or not req_center.discovered then
				available = false
			end
		end
		if available then
			mask = mask + (2 ^ (i - 1))
		end
	end
	return mask
end

-- Build the tag pool with availability flags
function GreenNeedle.build_tag_pool(ante)
	ante = ante or 1
	local pool = {}
	for k, v in ipairs(G.P_CENTER_POOLS["Tag"]) do
		local available = true
		if v.min_ante and v.min_ante > ante then
			available = false
		end
		if v.requires and available then
			local req_center = G.P_CENTERS[v.requires]
			if not req_center or not req_center.discovered then
				available = false
			end
		end
		pool[#pool + 1] = {key = v.key, available = available}
	end
	return pool
end

-- Predict the ante-1 skip tag for a given seed
function GreenNeedle.predict_tag(seed, ante)
	ante = ante or 1
	local pool = GreenNeedle.build_tag_pool(ante)
	local pool_key = "Tag" .. ante
	local pseed = GreenNeedle.pseudoseed(pool_key, seed)
	math.randomseed(pseed)
	local idx = math.random(#pool)
	local it = 1
	while not pool[idx].available and it < 100 do
		it = it + 1
		local reskey = pool_key .. "_resample" .. it
		local rpseed = GreenNeedle.pseudoseed(reskey, seed)
		math.randomseed(rpseed)
		idx = math.random(#pool)
	end
	return pool[idx].key
end

-- Predict which booster pack appears in a given shop slot
function GreenNeedle.predict_pack(seed, slot)
	if slot == 1 then return "p_buffoon_normal_1" end
	local pseed = GreenNeedle.pseudoseed("shop_pack1", seed)
	math.randomseed(pseed)
	local total_weight = 0
	for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
		total_weight = total_weight + (v.weight or 1)
	end
	local poll = math.random() * total_weight
	local cumulative = 0
	for k, v in ipairs(G.P_CENTER_POOLS['Booster']) do
		cumulative = cumulative + (v.weight or 1)
		if cumulative >= poll then return v.key end
	end
	return G.P_CENTER_POOLS['Booster'][#G.P_CENTER_POOLS['Booster']].key
end

-- Check if any slot in a tarot pack triggers a soul (>0.997 roll)
function GreenNeedle.check_soul(seed, soul_type, ante, pack_size)
	ante = ante or 1
	pack_size = pack_size or 5
	local key = "soul_" .. soul_type .. ante
	for i = 1, pack_size do
		local pseed = GreenNeedle.pseudoseed_advance(key, seed, i)
		math.randomseed(pseed)
		if math.random() > 0.997 then return true end
	end
	return false
end

-- Check if a specific spectral card appears in a spectral pack
function GreenNeedle.check_spectral_card(seed, key_append, ante, pack_size, extra_excluded, target_card)
	ante = ante or 1
	pack_size = pack_size or 4
	local tarot_soul_key = "soul_Tarot" .. ante
	local spectral_soul_key = "soul_Spectral" .. ante
	local card_key = "Spectral" .. key_append .. ante

	local pool = {}
	for k, v in ipairs(G.P_CENTER_POOLS["Spectral"]) do
		pool[#pool + 1] = v.key
	end
	while #pool < 18 do
		pool[#pool + 1] = nil
	end

	local unavailable = {}
	for i = 1, #pool do
		unavailable[i] = (pool[i] == nil)
	end
	if extra_excluded and extra_excluded ~= "" then
		for i = 1, #pool do
			if pool[i] == extra_excluded then
				unavailable[i] = true
				break
			end
		end
	end

	local card_advance = 0
	for slot = 1, pack_size do
		local soul_pseed = GreenNeedle.pseudoseed_advance(tarot_soul_key, seed, slot)
		math.randomseed(soul_pseed)
		if math.random() > 0.997 then
			if target_card == "c_soul" then return true end
		else
			local bh_pseed = GreenNeedle.pseudoseed_advance(spectral_soul_key, seed, slot)
			math.randomseed(bh_pseed)
			if math.random() > 0.997 then
				if target_card == "c_black_hole" then return true end
			else
				card_advance = card_advance + 1
				local pseed = GreenNeedle.pseudoseed_advance(card_key, seed, card_advance)
				math.randomseed(pseed)
				local idx = math.random(#pool)
				local resample = 1
				while unavailable[idx] and resample < 100 do
					resample = resample + 1
					local reskey = "Spectral" .. key_append .. ante .. "_resample" .. resample
					local rpseed = GreenNeedle.pseudoseed(reskey, seed)
					math.randomseed(rpseed)
					idx = math.random(#pool)
				end
				if pool[idx] == target_card then return true end
			end
		end
	end
	return false
end

-- Check if a specific tarot card appears in an arcana pack
function GreenNeedle.check_tarot_card(seed, key_append, ante, pack_size, target_card)
	ante = ante or 1
	pack_size = pack_size or 5
	local soul_key = "soul_Tarot" .. ante
	local card_key = "Tarot" .. key_append .. ante

	local pool = {}
	for k, v in ipairs(G.P_CENTER_POOLS["Tarot"]) do
		pool[#pool + 1] = v.key
	end

	local card_advance = 0
	for slot = 1, pack_size do
		local soul_pseed = GreenNeedle.pseudoseed_advance(soul_key, seed, slot)
		math.randomseed(soul_pseed)
		if math.random() > 0.997 then
			if target_card == "c_soul" then return true end
		else
			card_advance = card_advance + 1
			local pseed = GreenNeedle.pseudoseed_advance(card_key, seed, card_advance)
			math.randomseed(pseed)
			local idx = math.random(#pool)
			if pool[idx] == target_card then return true end
		end
	end
	return false
end

-- Rare joker pool (order-sorted, must match RARE_JOKER_POOL in greenneedle.c)
GreenNeedle.RARE_JOKER_POOL = {
	"j_dna", "j_vagabond", "j_baron", "j_obelisk", "j_baseball",
	"j_ancient", "j_campfire", "j_blueprint", "j_wee", "j_hit_the_road",
	"j_duo", "j_trio", "j_family", "j_order", "j_tribe",
	"j_stuntman", "j_invisible", "j_brainstorm", "j_drivers_license", "j_burnt",
}

-- Build a 20-bit bitmask of unlocked rare jokers from the game's collection state.
-- Bit i = 1 means RARE_JOKER_POOL[i+1] is unlocked (available).
-- Falls back to all-available (0xFFFFF) if game state is unavailable.
function GreenNeedle.build_rare_joker_mask()
	if not G.P_JOKER_RARITY_POOLS or not G.P_JOKER_RARITY_POOLS[3] then
		return 0xFFFFF -- all 20 bits set = all available
	end
	-- Build a lookup of unlocked rare joker keys
	local unlocked = {}
	for _, v in ipairs(G.P_JOKER_RARITY_POOLS[3]) do
		if v.key then
			unlocked[v.key] = true
		end
	end
	local mask = 0
	for i, key in ipairs(GreenNeedle.RARE_JOKER_POOL) do
		if unlocked[key] then
			mask = mask + (2 ^ (i - 1))
		end
	end
	return mask
end

-- Predict which rare joker Wraith creates for a given seed
function GreenNeedle.predict_wraith_joker(seed, ante, rare_avail_mask)
	ante = ante or 1
	rare_avail_mask = rare_avail_mask or 0xFFFFF
	local pool = GreenNeedle.RARE_JOKER_POOL
	local pool_size = #pool

	local pool_key = "Joker3wra" .. ante
	local pseed = GreenNeedle.pseudoseed(pool_key, seed)
	math.randomseed(pseed)
	local idx = math.random(pool_size)

	-- Check availability via bitmask
	local avail = (math.floor(rare_avail_mask / (2 ^ (idx - 1))) % 2) == 1
	local resample = 1
	while not avail and resample < 100 do
		resample = resample + 1
		local reskey = "Joker3wra" .. ante .. "_resample" .. resample
		local rpseed = GreenNeedle.pseudoseed(reskey, seed)
		math.randomseed(rpseed)
		idx = math.random(pool_size)
		avail = (math.floor(rare_avail_mask / (2 ^ (idx - 1))) % 2) == 1
	end
	return pool[idx]
end

-- Predict the edition of the joker Wraith creates
-- Uses pseudoseed key "ediwra" + ante with poll_edition base rates
function GreenNeedle.predict_wraith_edition(seed, ante)
	ante = ante or 1
	local pseed = GreenNeedle.pseudoseed("ediwra" .. ante, seed)
	math.randomseed(pseed)
	local poll = math.random()
	if poll > 0.997 then return "e_negative" end
	if poll > 1.0 - 0.006 then return "e_polychrome" end
	if poll > 1.0 - 0.02 then return "e_holographic" end
	if poll > 1.0 - 0.04 then return "e_foil" end
	return ""
end

-- ---------------------------------------------------------------------------
-- Pack weights (mirrors PACK_DEFS in greenneedle.c)
-- ---------------------------------------------------------------------------
GreenNeedle.PACK_WEIGHTS = {
	["p_arcana_normal_1"]    = 4.00, ["p_arcana_normal_2"]    = 4.00,
	["p_arcana_normal_3"]    = 4.00, ["p_arcana_normal_4"]    = 4.00,
	["p_arcana_jumbo_1"]     = 2.00, ["p_arcana_jumbo_2"]     = 2.00,
	["p_arcana_mega_1"]      = 0.50, ["p_arcana_mega_2"]      = 0.50,
	["p_celestial_normal_1"] = 4.00, ["p_celestial_normal_2"] = 4.00,
	["p_celestial_normal_3"] = 4.00, ["p_celestial_normal_4"] = 4.00,
	["p_celestial_jumbo_1"]  = 2.00, ["p_celestial_jumbo_2"]  = 2.00,
	["p_celestial_mega_1"]   = 0.50, ["p_celestial_mega_2"]   = 0.50,
	["p_standard_normal_1"]  = 4.00, ["p_standard_normal_2"]  = 4.00,
	["p_standard_normal_3"]  = 4.00, ["p_standard_normal_4"]  = 4.00,
	["p_standard_jumbo_1"]   = 2.00, ["p_standard_jumbo_2"]   = 2.00,
	["p_standard_mega_1"]    = 0.50, ["p_standard_mega_2"]    = 0.50,
	["p_buffoon_normal_1"]   = 1.20, ["p_buffoon_normal_2"]   = 1.20,
	["p_buffoon_jumbo_1"]    = 0.60,
	["p_buffoon_mega_1"]     = 0.15,
	["p_spectral_normal_1"]  = 0.60, ["p_spectral_normal_2"]  = 0.60,
	["p_spectral_jumbo_1"]   = 0.30,
	["p_spectral_mega_1"]    = 0.07,
}
GreenNeedle.TOTAL_PACK_WEIGHT = 48.44

local EDITION_PROBS = {
	["e_negative"]     = 0.003,
	["e_polychrome"]   = 0.006,
	["e_holographic"]  = 0.02,
	["e_foil"]         = 0.04,
}

-- ---------------------------------------------------------------------------
-- Formatting and estimation
-- ---------------------------------------------------------------------------

-- Format a number with B/M/K suffixes for display
function GreenNeedle.format_seed_count(n)
	if n >= 1000000000 then
		return string.format("%.1fB", n / 1000000000)
	elseif n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.0fK", n / 1000)
	else
		return tostring(n)
	end
end

-- Estimate expected seeds to search for current filter combination.
-- Returns 0 if no filters are active.
function GreenNeedle.estimate_search_seeds()
	local s = GreenNeedle.SETTINGS.autoreroll
	local prob = 1.0
	local any_filter = false

	-- Tag filter: ~1/15 available tags at ante 1
	if s.searchTag and s.searchTag ~= "" then
		prob = prob * (1 / 15)
		any_filter = true
	end

	-- Pack filter: sum selected pack weights / total weight
	if s.searchPack and #s.searchPack > 0 then
		local selected_weight = 0
		for _, pk in ipairs(s.searchPack) do
			selected_weight = selected_weight + (GreenNeedle.PACK_WEIGHTS[pk] or 0)
		end
		if selected_weight > 0 then
			prob = prob * (selected_weight / GreenNeedle.TOTAL_PACK_WEIGHT)
			any_filter = true
		end
	end

	-- Determine pack card context for slot counts
	local pack_type = GreenNeedle.get_pack_card_type()

	-- Probability helper for a card appearing in N slots of a pool
	-- c_soul uses the soul check (0.003/slot), not the card pool
	local function tarot_card_prob(card, slots, is_second)
		if card == "c_soul" then
			return 1 - 0.997^slots
		end
		local pool = is_second and 20 or 21
		return 1 - (pool/22)^slots
	end
	local function spectral_card_prob(card, slots, is_second)
		if card == "c_soul" or card == "c_black_hole" then
			-- soul_Tarot / soul_Spectral check: 0.003 per slot
			return 1 - 0.997^slots
		end
		local pool = is_second and 14 or 15
		return 1 - (pool/16)^slots
	end

	-- Tag card filters (Charm Tag = Mega Arcana, 5 tarot slots)
	if s.searchTag == "tag_charm" then
		if s.searchTagCard1 and s.searchTagCard1 ~= "" then
			prob = prob * tarot_card_prob(s.searchTagCard1, 5, false)
			any_filter = true
		end
		if s.searchTagCard2 and s.searchTagCard2 ~= "" then
			prob = prob * tarot_card_prob(s.searchTagCard2, 5, true)
			any_filter = true
		end
	end

	-- Pack card filters (use dynamic slot count based on selected pack variant)
	if s.searchPack and #s.searchPack > 0 and pack_type then
		local slots = GreenNeedle.get_pack_slot_count()
		if pack_type == "spectral" then
			if s.searchPackCard1 and s.searchPackCard1 ~= "" then
				prob = prob * spectral_card_prob(s.searchPackCard1, slots, false)
				any_filter = true
			end
			if s.searchPackCard2 and s.searchPackCard2 ~= "" then
				prob = prob * spectral_card_prob(s.searchPackCard2, slots, true)
				any_filter = true
			end
		elseif pack_type == "tarot" then
			if s.searchPackCard1 and s.searchPackCard1 ~= "" then
				prob = prob * tarot_card_prob(s.searchPackCard1, slots, false)
				any_filter = true
			end
			if s.searchPackCard2 and s.searchPackCard2 ~= "" then
				prob = prob * tarot_card_prob(s.searchPackCard2, slots, true)
				any_filter = true
			end
		end
	end

	-- Voucher ante 1: 1/16 base voucher pool
	if s.searchVoucher and s.searchVoucher ~= "" then
		prob = prob * (1 / 16)
		any_filter = true
	end

	-- Voucher ante 2: ~1/16 pool
	if s.searchVoucher2 and s.searchVoucher2 ~= "" then
		prob = prob * (1 / 16)
		any_filter = true
	end

	-- Legendary joker: 1/5 pool
	if s.searchLegendary and s.searchLegendary ~= "" then
		prob = prob * (1 / 5)
		any_filter = true
	end

	-- Wraith joker: 1/20 rare pool
	if s.searchWraithJoker and s.searchWraithJoker ~= "" then
		local has_wraith = (s.searchPackCard1 == "c_wraith") or (s.searchPackCard2 == "c_wraith")
		if has_wraith then
			prob = prob * (1 / 20)
			any_filter = true
		end
	end

	-- Wraith edition
	if s.searchWraithEdition and s.searchWraithEdition ~= "" then
		local has_wraith = (s.searchPackCard1 == "c_wraith") or (s.searchPackCard2 == "c_wraith")
		if has_wraith then
			local ep = EDITION_PROBS[s.searchWraithEdition] or 0.04
			prob = prob * ep
			any_filter = true
		end
	end

	if not any_filter then return 0 end
	return math.ceil(1 / prob)
end

-- ---------------------------------------------------------------------------
-- Auto reroll search
-- ---------------------------------------------------------------------------

function GreenNeedle.auto_reroll()
	local s = GreenNeedle.SETTINGS.autoreroll
	local seed_found = nil

	if GreenNeedle.native and not GreenNeedle.SETTINGS.force_lua_search then
		-- Native C fast path
		local start_seed = random_string(
			8,
			G.CONTROLLER.cursor_hover.T.x * 0.33411983
				+ G.CONTROLLER.cursor_hover.T.y * 0.874146
				+ 0.412311010 * G.CONTROLLER.cursor_hover.time
		)

		local tag_arg           = s.searchTag          or ""
		local voucher_arg       = s.searchVoucher      or ""
		local legendary_arg     = s.searchLegendary    or ""
		local tag_mask          = GreenNeedle.build_tag_avail_mask(1)

		local pack_arg = ""
		if s.searchPack and #s.searchPack > 0 then
			pack_arg = table.concat(s.searchPack, ",")
		end

		-- Route card filters to the correct native params
		local tarot_card_arg = ""
		local tarot_card2_arg = ""
		local spectral_card_arg = ""
		local spectral_card2_arg = ""
		local tarot_key_append = "ar1"
		local pack_slot_count = GreenNeedle.get_pack_slot_count()
		local tarot_pack_size = 5  -- tag cards always use 5 (Charm Tag = Mega Arcana)
		local spectral_pack_size = 4

		-- Tag card filters (Charm Tag = tarot cards)
		if s.searchTag == "tag_charm" then
			if s.searchTagCard1 and s.searchTagCard1 ~= "" then
				tarot_card_arg = s.searchTagCard1
			end
			if s.searchTagCard2 and s.searchTagCard2 ~= "" then
				tarot_card2_arg = s.searchTagCard2
			end
		end

		-- Pack card filters (only when a pack is selected)
		if s.searchPack and #s.searchPack > 0 then
			local ptype = GreenNeedle.get_pack_card_type()
			if ptype == "tarot" then
				tarot_pack_size = pack_slot_count
				if s.searchPackCard1 and s.searchPackCard1 ~= "" then
					if tarot_card_arg == "" then
						tarot_card_arg = s.searchPackCard1
					elseif tarot_card2_arg == "" then
						tarot_card2_arg = s.searchPackCard1
					end
				end
				if s.searchPackCard2 and s.searchPackCard2 ~= "" then
					if tarot_card_arg == "" then
						tarot_card_arg = s.searchPackCard2
					elseif tarot_card2_arg == "" then
						tarot_card2_arg = s.searchPackCard2
					end
				end
			elseif ptype == "spectral" then
				spectral_pack_size = pack_slot_count
				if s.searchPackCard1 and s.searchPackCard1 ~= "" then
					spectral_card_arg = s.searchPackCard1
				end
				if s.searchPackCard2 and s.searchPackCard2 ~= "" then
					spectral_card2_arg = s.searchPackCard2
				end
			end
		end

		local voucher2_arg = s.searchVoucher2 or ""

		-- Wraith joker filter (only when Wraith is a selected spectral pack card)
		local wraith_joker_arg = ""
		local wraith_edition_arg = ""
		if s.searchWraithJoker and s.searchWraithJoker ~= "" then
			-- Only apply if Wraith is actually selected as a pack card
			if spectral_card_arg == "c_wraith" or spectral_card2_arg == "c_wraith" then
				wraith_joker_arg = s.searchWraithJoker
			end
		end
		if s.searchWraithEdition and s.searchWraithEdition ~= "" then
			if spectral_card_arg == "c_wraith" or spectral_card2_arg == "c_wraith" then
				wraith_edition_arg = s.searchWraithEdition
			end
		end
		local rare_joker_mask = GreenNeedle.build_rare_joker_mask()

		local result = GreenNeedle.native.greenneedle_search(
			start_seed,
			s.seedsPerFrame or 100000,
			tag_arg,
			pack_arg,
			voucher_arg,
			legendary_arg,
			spectral_card_arg,
			tag_mask,
			tarot_card_arg,
			tarot_key_append,
			tarot_pack_size,
			voucher2_arg,
			tarot_card2_arg,
			spectral_card2_arg,
			wraith_joker_arg,
			rare_joker_mask,
			wraith_edition_arg,
			spectral_pack_size
		)
		result = result ~= nil and GreenNeedle.ffi.string(result) or ""
		if result ~= "" then
			seed_found = result
		end
	else
		-- Pure-Lua fallback
		local rerollsThisFrame = 0
		local extra_num = -0.561892350821
		while not seed_found and rerollsThisFrame < (s.seedsPerFrame or 500) do
			rerollsThisFrame = rerollsThisFrame + 1
			extra_num = extra_num + 0.561892350821
			seed_found = random_string(
				8,
				extra_num
					+ G.CONTROLLER.cursor_hover.T.x * 0.33411983
					+ G.CONTROLLER.cursor_hover.T.y * 0.874146
					+ 0.412311010 * G.CONTROLLER.cursor_hover.time
			)
			-- Tag filter
			if s.searchTag and s.searchTag ~= "" then
				if GreenNeedle.predict_tag(seed_found, 1) ~= s.searchTag then
					seed_found = nil
				end
			end
			-- Pack filter
			if seed_found and s.searchPack and #s.searchPack > 0 then
				local pack = GreenNeedle.predict_pack(seed_found, 2)
				local pack_found = false
				for i = 1, #s.searchPack do
					if s.searchPack[i] == pack then pack_found = true; break end
				end
				if not pack_found then seed_found = nil end
			end
			-- Voucher ante 1
			if seed_found and s.searchVoucher and s.searchVoucher ~= "" then
				if GreenNeedle.predict_voucher(seed_found, 1) ~= s.searchVoucher then
					seed_found = nil
				end
			end
			-- Legendary
			if seed_found and s.searchLegendary and s.searchLegendary ~= "" then
				if GreenNeedle.predict_legendary(seed_found) ~= s.searchLegendary then
					seed_found = nil
				end
			end
			-- Tag card 1 (Charm Tag Mega Arcana)
			if seed_found and s.searchTagCard1 and s.searchTagCard1 ~= "" and s.searchTag == "tag_charm" then
				if not GreenNeedle.check_tarot_card(seed_found, "ar1", 1, 5, s.searchTagCard1) then
					seed_found = nil
				end
			end
			-- Tag card 2
			if seed_found and s.searchTagCard2 and s.searchTagCard2 ~= "" and s.searchTag == "tag_charm" then
				if not GreenNeedle.check_tarot_card(seed_found, "ar1", 1, 5, s.searchTagCard2) then
					seed_found = nil
				end
			end
			-- Pack card 1 (only if a pack filter is set)
			if seed_found and s.searchPackCard1 and s.searchPackCard1 ~= "" and s.searchPack and #s.searchPack > 0 then
				local ptype = GreenNeedle.get_pack_card_type()
				local pslots = GreenNeedle.get_pack_slot_count()
				if ptype == "spectral" then
					if not GreenNeedle.check_spectral_card(seed_found, "spe", 1, pslots, nil, s.searchPackCard1) then
						seed_found = nil
					end
				elseif ptype == "tarot" then
					if not GreenNeedle.check_tarot_card(seed_found, "ar1", 1, pslots, s.searchPackCard1) then
						seed_found = nil
					end
				end
			end
			-- Pack card 2 (only if a pack filter is set)
			if seed_found and s.searchPackCard2 and s.searchPackCard2 ~= "" and s.searchPack and #s.searchPack > 0 then
				local ptype = GreenNeedle.get_pack_card_type()
				local pslots = GreenNeedle.get_pack_slot_count()
				if ptype == "spectral" then
					if not GreenNeedle.check_spectral_card(seed_found, "spe", 1, pslots, nil, s.searchPackCard2) then
						seed_found = nil
					end
				elseif ptype == "tarot" then
					if not GreenNeedle.check_tarot_card(seed_found, "ar1", 1, pslots, s.searchPackCard2) then
						seed_found = nil
					end
				end
			end
			-- Voucher ante 2
			if seed_found and s.searchVoucher2 and s.searchVoucher2 ~= "" then
				local used = {}
				if s.searchVoucher and s.searchVoucher ~= "" then
					used[s.searchVoucher] = true
				end
				if GreenNeedle.predict_voucher(seed_found, 2, used) ~= s.searchVoucher2 then
					seed_found = nil
				end
			end
			-- Wraith joker (only when Wraith is a selected spectral pack card)
			if seed_found and s.searchWraithJoker and s.searchWraithJoker ~= "" then
				local has_wraith = false
				if s.searchPackCard1 == "c_wraith" or s.searchPackCard2 == "c_wraith" then
					has_wraith = true
				end
				if has_wraith then
					local mask = GreenNeedle.build_rare_joker_mask()
					if GreenNeedle.predict_wraith_joker(seed_found, 1, mask) ~= s.searchWraithJoker then
						seed_found = nil
					end
				end
			end
			-- Wraith edition (only when Wraith is a selected spectral pack card)
			if seed_found and s.searchWraithEdition and s.searchWraithEdition ~= "" then
				local has_wraith = false
				if s.searchPackCard1 == "c_wraith" or s.searchPackCard2 == "c_wraith" then
					has_wraith = true
				end
				if has_wraith then
					if GreenNeedle.predict_wraith_edition(seed_found, 1) ~= s.searchWraithEdition then
						seed_found = nil
					end
				end
			end
		end
	end

	if seed_found then
		GreenNeedle.AUTOREROLL.autoRerollActive = false
		local _stake = G.GAME.stake
		print("[GN] Found seed: " .. seed_found)
		G:delete_run()
		G:start_run({
			stake = _stake,
			seed = seed_found,
			challenge = G.GAME and G.GAME.challenge and G.GAME.challenge_tab,
		})
		G.GAME.seeded = false
	end
	return seed_found
end

-- ---------------------------------------------------------------------------
-- Attention text display (for "Searching..." overlay)
-- Based on Balatro's attention_text
-- ---------------------------------------------------------------------------

function GreenNeedle.attention_text(args)
    args = args or {}
    args.text = args.text or 'test'
    args.scale = args.scale or 1
    args.colour = copy_table(args.colour or G.C.WHITE)
    args.hold = (args.hold or 0) + 0.1*(G.SPEEDFACTOR)
    args.pos = args.pos or {x = 0, y = 0}
    args.align = args.align or 'cm'
    args.emboss = args.emboss or nil
    args.fade = 1

    if args.cover then
      args.cover_colour = copy_table(args.cover_colour or G.C.RED)
      args.cover_colour_l = copy_table(lighten(args.cover_colour, 0.2))
      args.cover_colour_d = copy_table(darken(args.cover_colour, 0.2))
    else
      args.cover_colour = copy_table(G.C.CLEAR)
    end

    args.uibox_config = {
      align = args.align or 'cm',
      offset = args.offset or {x=0,y=0},
      major = args.cover or args.major or nil,
    }

    G.E_MANAGER:add_event(Event({
      trigger = 'after',
      delay = 0,
      blockable = false,
      blocking = false,
      func = function()
          args.AT = UIBox{
            T = {args.pos.x,args.pos.y,0,0},
            definition =
              {n=G.UIT.ROOT, config = {align = args.cover_align or 'cm', minw = (args.cover and args.cover.T.w or 0.001) + (args.cover_padding or 0), minh = (args.cover and args.cover.T.h or 0.001) + (args.cover_padding or 0), padding = 0.03, r = 0.1, emboss = args.emboss, colour = args.cover_colour}, nodes={
                {n=G.UIT.O, config={draw_layer = 1, object = DynaText({scale = args.scale, string = args.text, maxw = args.maxw, colours = {args.colour},float = true, shadow = true, silent = not args.noisy, args.scale, pop_in = 0, pop_in_rate = 6, rotate = args.rotate or nil})}},
              }},
            config = args.uibox_config
          }
          args.AT.attention_text = true
          args.text = args.AT.UIRoot.children[1].config.object
          args.text:pulse(0.5)

          if args.cover then
            Particles(args.pos.x,args.pos.y, 0,0, {
              timer_type = 'TOTAL',
              timer = 0.01,
              pulse_max = 15,
              max = 0,
              scale = 0.3,
              vel_variation = 0.2,
              padding = 0.1,
              fill=true,
              lifespan = 0.5,
              speed = 2.5,
              attach = args.AT.UIRoot,
              colours = {args.cover_colour, args.cover_colour_l, args.cover_colour_d},
          })
          end
          if args.backdrop_colour then
            args.backdrop_colour = copy_table(args.backdrop_colour)
            Particles(args.pos.x,args.pos.y,0,0,{
              timer_type = 'TOTAL',
              timer = 5,
              scale = 2.4*(args.backdrop_scale or 1),
              lifespan = 5,
              speed = 0,
              attach = args.AT,
              colours = {args.backdrop_colour}
            })
          end
          return true
      end
      }))
      return args
end

function GreenNeedle.remove_attention_text(args)
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 0,
        blockable = false,
        blocking = false,
        func = function()
          if not args.start_time then
            args.start_time = G.TIMERS.TOTAL
            args.text:pop_out(3)
          else
            args.fade = math.max(0, 1 - 3*(G.TIMERS.TOTAL - args.start_time))
            if args.cover_colour then args.cover_colour[4] = math.min(args.cover_colour[4], 2*args.fade) end
            if args.cover_colour_l then args.cover_colour_l[4] = math.min(args.cover_colour_l[4], args.fade) end
            if args.cover_colour_d then args.cover_colour_d[4] = math.min(args.cover_colour_d[4], args.fade) end
            if args.backdrop_colour then args.backdrop_colour[4] = math.min(args.backdrop_colour[4], args.fade) end
            args.colour[4] = math.min(args.colour[4], args.fade)
            if args.fade <= 0 then
              args.AT:remove()
              return true
            end
          end
        end
      }))
end

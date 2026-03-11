-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

GreenNeedle = {}

-- Default settings (used when no settings file exists yet)
GreenNeedle.SETTINGS = {
	force_lua_search = false,
	keybinds = {
		autoReroll = "a",
	},
	autoreroll = {
		searchTag = "",
		searchTagID = 1,
		searchPack = {},
		searchPackID = 1,
		searchVoucher = "",
		searchVoucherID = 1,
		searchVoucher2 = "",
		searchVoucher2ID = 1,
		searchLegendary = "",
		searchLegendaryID = 1,
		searchTagCard1 = "",
		searchTagCard1ID = 1,
		searchTagCard2 = "",
		searchTagCard2ID = 1,
		searchPackCard1 = "",
		searchPackCard1ID = 1,
		searchPackCard2 = "",
		searchPackCard2ID = 1,
		searchWraithJoker = "",
		searchWraithJokerID = 1,
		searchWraithEdition = "",
		searchWraithEditionID = 1,
		searchJudgementJoker = "",
		searchJudgementJokerID = 2,
		searchJudgementPage = 1,
		searchJudgementEdition = "",
		searchJudgementEditionID = 1,
		searchShopJudgementJoker = "",
		searchShopJudgementJokerID = 2,
		searchShopJudgementPage = 1,
		searchShopJudgementEdition = "",
		searchShopJudgementEditionID = 1,
		searchTagJoker = "",
		searchTagJokerID = 2,
		searchTagJokerPage = 1,
		searchBuffoonCard1Page = 1,
		searchBuffoonCard2Page = 1,
		searchBuffoonEdition = "",
		searchBuffoonEditionID = 1,
		seedsPerFrame = 100000,
		seedsPerFrameID = 3,
	},
	erratic = {
		rank1 = "Any", rank1ID = 1, rank1Min = 0, rank1Max = 52,
		rank2 = "Any", rank2ID = 1, rank2Min = 0, rank2Max = 52,
		rank3 = "Any", rank3ID = 1, rank3Min = 0, rank3Max = 52,
		rank4 = "Any", rank4ID = 1, rank4Min = 0, rank4Max = 52,
		clubsMin = 0, clubsMax = 52,
		diamondsMin = 0, diamondsMax = 52,
		heartsMin = 0, heartsMax = 52,
		spadesMin = 0, spadesMax = 52,
	},
}

function initGreenNeedle()
	local lovely = require("lovely")
	local nativefs = require("nativefs")
	assert(load(nativefs.read(lovely.mod_dir .. "/GreenNeedle/GreenNeedle_main.lua")))()
	assert(load(nativefs.read(lovely.mod_dir .. "/GreenNeedle/GreenNeedle_UI.lua")))()
	assert(load(nativefs.read(lovely.mod_dir .. "/GreenNeedle/GreenNeedle_keyhandler.lua")))()
	assert(load(nativefs.read(lovely.mod_dir .. "/GreenNeedle/GreenNeedle_search.lua")))()

	-- Load saved settings (overwrite defaults)
	if nativefs.getInfo(lovely.mod_dir .. "/GreenNeedle/settings.lua") then
		local saved = STR_UNPACK(nativefs.read(lovely.mod_dir .. "/GreenNeedle/settings.lua"))
		if saved then
			-- Merge saved into defaults so new keys get their defaults
			for k, v in pairs(saved) do
				if type(v) == "table" and type(GreenNeedle.SETTINGS[k]) == "table" then
					for k2, v2 in pairs(v) do
						GreenNeedle.SETTINGS[k][k2] = v2
					end
				else
					GreenNeedle.SETTINGS[k] = v
				end
			end
		end
	end
end

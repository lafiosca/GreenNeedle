-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local lovely = require("lovely")
local nativefs = require("nativefs")

GreenNeedle.INITIALIZED = true
GreenNeedle.VER = "0.5.2"

-- Local alias for the global formatter
local function format_count(n)
	return GreenNeedle.format_seed_count(n)
end

local function format_elapsed(seconds)
	local s = math.floor(seconds)
	if s < 60 then return string.format("%ds", s) end
	if s < 3600 then return string.format("%dm %02ds", math.floor(s / 60), s % 60) end
	return string.format("%dh %02dm %02ds", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

-- Display text table is initialized in the update loop on first use

function GreenNeedle.update(dt)
	-- Clean up search overlay when stopped via ctrl+a
	if not GreenNeedle.AUTOREROLL.autoRerollActive and GreenNeedle.AUTOREROLL.autoRerollFrames and GreenNeedle.AUTOREROLL.autoRerollFrames > 0 then
		GreenNeedle.AUTOREROLL.autoRerollFrames = 0
		GreenNeedle.AUTOREROLL.seedsSearched = 0
		GreenNeedle.AUTOREROLL.searchStartTime = nil
		if GreenNeedle.AUTOREROLL.rerollText then
			GreenNeedle.remove_attention_text(GreenNeedle.AUTOREROLL.rerollText)
			GreenNeedle.AUTOREROLL.rerollText = nil
		end
		if GreenNeedle.AUTOREROLL.timerText then
			GreenNeedle.remove_attention_text(GreenNeedle.AUTOREROLL.timerText)
			GreenNeedle.AUTOREROLL.timerText = nil
		end
	end
	if GreenNeedle.AUTOREROLL.autoRerollActive then
		GreenNeedle.AUTOREROLL.autoRerollFrames = (GreenNeedle.AUTOREROLL.autoRerollFrames or 0)
		-- Show counter on first frame, before any search runs
		if GreenNeedle.AUTOREROLL.autoRerollFrames == 0 then
			GreenNeedle.AUTOREROLL.seedsSearched = 0
			GreenNeedle.AUTOREROLL.searchStartTime = os.time()
			if G.GAME.starting_params.erratic_suits_and_ranks then
				GreenNeedle.AUTOREROLL.searchEstimate = GreenNeedle.estimate_combined_seeds()
			else
				GreenNeedle.AUTOREROLL.searchEstimate = GreenNeedle.estimate_search_seeds()
			end
			GreenNeedle.AUTOREROLL.displayText = GreenNeedle.AUTOREROLL.displayText or {}
			GreenNeedle.AUTOREROLL.timerDisplayText = GreenNeedle.AUTOREROLL.timerDisplayText or {}
			local est = GreenNeedle.AUTOREROLL.searchEstimate
			local est_str = est > 0 and (" / ~" .. format_count(est)) or ""
			GreenNeedle.AUTOREROLL.displayText.value = "Searching... (0" .. est_str .. ")"
			GreenNeedle.AUTOREROLL.timerDisplayText.value = "0s"
			local major = G.STAGE == G.STAGES.RUN and G.play or G.title_top
			GreenNeedle.AUTOREROLL.rerollText = GreenNeedle.attention_text({
				scale = 1.4,
				maxw = 8,
				text = {{ref_table = GreenNeedle.AUTOREROLL.displayText, ref_value = "value"}},
				align = 'cm',
				offset = {x = 0, y = -4.7},
				major = major,
			})
			GreenNeedle.AUTOREROLL.timerText = GreenNeedle.attention_text({
				scale = 0.7,
				text = {{ref_table = GreenNeedle.AUTOREROLL.timerDisplayText, ref_value = "value"}},
				align = 'cm',
				offset = {x = 0, y = -3.5},
				major = major,
				colour = {0.8, 0.8, 0.8, 1},
				emboss = 0.05,
			})
			GreenNeedle.AUTOREROLL.autoRerollFrames = 1
			return -- let UI render before starting search
		end
		GreenNeedle.AUTOREROLL.rerollTimer = GreenNeedle.AUTOREROLL.rerollTimer + dt
		if GreenNeedle.AUTOREROLL.rerollTimer >= GreenNeedle.AUTOREROLL.rerollInterval then
			GreenNeedle.AUTOREROLL.rerollTimer = 0
			local seeds_per = GreenNeedle.SETTINGS.autoreroll.seedsPerFrame or 100000
			local seed_found = GreenNeedle.auto_reroll()
			GreenNeedle.AUTOREROLL.seedsSearched = (GreenNeedle.AUTOREROLL.seedsSearched or 0) + seeds_per
			if seed_found then
				GreenNeedle.AUTOREROLL.autoRerollFrames = 0
				GreenNeedle.AUTOREROLL.seedsSearched = 0
				GreenNeedle.AUTOREROLL.searchStartTime = nil
				if GreenNeedle.AUTOREROLL.rerollText then
					GreenNeedle.remove_attention_text(GreenNeedle.AUTOREROLL.rerollText)
					GreenNeedle.AUTOREROLL.rerollText = nil
				end
				if GreenNeedle.AUTOREROLL.timerText then
					GreenNeedle.remove_attention_text(GreenNeedle.AUTOREROLL.timerText)
					GreenNeedle.AUTOREROLL.timerText = nil
				end
				return
			end
			-- Update the displayed counter via ref_table
			local est = GreenNeedle.AUTOREROLL.searchEstimate or 0
			local est_str = est > 0 and (" / ~" .. format_count(est)) or ""
			GreenNeedle.AUTOREROLL.displayText.value = "Searching... (" .. format_count(GreenNeedle.AUTOREROLL.seedsSearched) .. est_str .. ")"
			-- Update timer using wall clock
			local elapsed = os.time() - (GreenNeedle.AUTOREROLL.searchStartTime or os.time())
			local likelihood = ""
			if est > 0 then
				local pct = (1 - math.exp(-GreenNeedle.AUTOREROLL.seedsSearched / est)) * 100
				likelihood = string.format("  (%.3f%%)", pct)
			end
			GreenNeedle.AUTOREROLL.timerDisplayText.value = format_elapsed(elapsed) .. likelihood
		end
		GreenNeedle.AUTOREROLL.autoRerollFrames = GreenNeedle.AUTOREROLL.autoRerollFrames + 1
	end
end

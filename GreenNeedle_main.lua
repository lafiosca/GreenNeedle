-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local lovely = require("lovely")
local nativefs = require("nativefs")

GreenNeedle.INITIALIZED = true
GreenNeedle.VER = "Green Needle v1.0.0"

-- Local alias for the global formatter
local function format_count(n)
	return GreenNeedle.format_seed_count(n)
end

-- Display text table is initialized in the update loop on first use

function GreenNeedle.update(dt)
	-- Clean up search overlay when stopped via ctrl+a
	if not GreenNeedle.AUTOREROLL.autoRerollActive and GreenNeedle.AUTOREROLL.autoRerollFrames and GreenNeedle.AUTOREROLL.autoRerollFrames > 0 then
		GreenNeedle.AUTOREROLL.autoRerollFrames = 0
		GreenNeedle.AUTOREROLL.seedsSearched = 0
		if GreenNeedle.AUTOREROLL.rerollText then
			GreenNeedle.remove_attention_text(GreenNeedle.AUTOREROLL.rerollText)
			GreenNeedle.AUTOREROLL.rerollText = nil
		end
	end
	if GreenNeedle.AUTOREROLL.autoRerollActive then
		GreenNeedle.AUTOREROLL.autoRerollFrames = (GreenNeedle.AUTOREROLL.autoRerollFrames or 0)
		-- Show counter on first frame, before any search runs
		if GreenNeedle.AUTOREROLL.autoRerollFrames == 0 then
			GreenNeedle.AUTOREROLL.seedsSearched = 0
			GreenNeedle.AUTOREROLL.searchEstimate = GreenNeedle.estimate_search_seeds()
			GreenNeedle.AUTOREROLL.displayText = GreenNeedle.AUTOREROLL.displayText or {}
			local est = GreenNeedle.AUTOREROLL.searchEstimate
			local est_str = est > 0 and (" / ~" .. format_count(est)) or ""
			GreenNeedle.AUTOREROLL.displayText.value = "Searching... (0" .. est_str .. ")"
			GreenNeedle.AUTOREROLL.rerollText = GreenNeedle.attention_text({
				scale = 1.4,
				text = {{ref_table = GreenNeedle.AUTOREROLL.displayText, ref_value = "value"}},
				align = 'cm',
				offset = {x = 0, y = -3.5},
				major = G.STAGE == G.STAGES.RUN and G.play or G.title_top,
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
				if GreenNeedle.AUTOREROLL.rerollText then
					GreenNeedle.remove_attention_text(GreenNeedle.AUTOREROLL.rerollText)
					GreenNeedle.AUTOREROLL.rerollText = nil
				end
				return
			end
			-- Update the displayed counter via ref_table
			local est = GreenNeedle.AUTOREROLL.searchEstimate or 0
			local est_str = est > 0 and (" / ~" .. format_count(est)) or ""
			GreenNeedle.AUTOREROLL.displayText.value = "Searching... (" .. format_count(GreenNeedle.AUTOREROLL.seedsSearched) .. est_str .. ")"
		end
		GreenNeedle.AUTOREROLL.autoRerollFrames = GreenNeedle.AUTOREROLL.autoRerollFrames + 1
	end
end

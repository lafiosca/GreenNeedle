-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local lovely = require("lovely")
local nativefs = require("nativefs")

-- Track ctrl state ourselves to handle OS-level remappings (e.g. caps lock -> ctrl)
GreenNeedle.ctrlDown = false

local function isCtrl(key)
	return key == "lctrl" or key == "rctrl"
end

function GreenNeedle.key_press_update(key)
	if isCtrl(key) then GreenNeedle.ctrlDown = true end

	if key == GreenNeedle.SETTINGS.keybinds.autoReroll and GreenNeedle.ctrlDown then
		GreenNeedle.AUTOREROLL.autoRerollActive = not GreenNeedle.AUTOREROLL.autoRerollActive
	end
end

function GreenNeedle.key_release_update(key)
	if isCtrl(key) then GreenNeedle.ctrlDown = false end
end

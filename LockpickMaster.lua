-------------------------------------------------------------------------------
-- LockpickMaster
--
-- For world game objects (chests, doors) it uses ClassicAPI's:
--	GameTooltip:GetGameObject() > returns (name, gameObjectID, guid)
--	GameTooltip:HasGameObject() > boolean guard
--	C_GameObjectInfo.GetGameObjectInfoByID(id) > {name, type, displayID, …}
--	C_GameObjectInfo.RequestLoadGameObjectByID(id) > async cache fill
--	OnTooltipSetGameObject	> HookScript that fires on every GO mouseover
--
-- For lockbox items it uses:
--	GameTooltip:GetItem()	> returns (name, link, itemID)
--	OnTooltipSetItem		> HookScript that fires on every item tooltip
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- ClassicAPI guard
-- Bail out before registering any hooks or globals if the
-- mod is not installed, then notify the player on login.
-------------------------------------------------------------------------------
if not C_GameObjectInfo or not GameTooltip.HasGameObject then
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffff2020LockpickMaster:|r ClassicAPI is not installed. "
			.. "The addon will not function without it. Please install ClassicAPI and restart the game.")
	end)
	return
end

-------------------------------------------------------------------------------
-- SAVED VARIABLES/SETTINGS
-------------------------------------------------------------------------------
LockpickMasterDB = LockpickMasterDB or {}
if LockpickMasterDB.colorMode == nil then LockpickMasterDB.colorMode = "match" end
if LockpickMasterDB.showSkillSuffix == nil then LockpickMasterDB.showSkillSuffix = true end
if LockpickMasterDB.showLoginMsg == nil then LockpickMasterDB.showLoginMsg = true end

local ADDON_NAME	= "LockpickMaster"
local ADDON_VERSION = "1.0"

-------------------------------------------------------------------------------
-- LOCKBOX ITEM DATABASE
-- [itemID] = required
--	or
-- [itemID] = { required, yellow, green, grey }
--
-- required: minimum Lockpicking skill to open the lock.
-- The three optional thresholds mirror skill difficulty colors.
-- Orange starts at required and transitions through yellow, green, grey.
--
-- Thresholds only affect hyperlinked items. Bag item tooltips always use
-- simple green/red or match coloring regardless.
-------------------------------------------------------------------------------
local LOCKBOX_ITEMS = {
	-- Junkboxes --
	[16882]	= { 1, 30, 55, 105 },		-- Battered Junkbox
	[16883]	= { 70, 95, 120, 170 },		-- Worn Junkbox
	[16884]	= { 175, 200, 225, 275 },	-- Sturdy Junkbox
	[16885]	= { 250, 275, 300, 350 },	-- Heavy Junkbox

	-- Crafted/dropped lockboxes/chests --
	[4632]	= { 1, 30, 55, 105 },		-- Ornate Bronze Lockbox
	[4633]	= { 25, 50, 75, 125},		-- Heavy Bronze Lockbox
	[4634]	= { 70, 95, 120, 170 },		-- Iron Lockbox
	[4636]	= { 125, 150, 175, 225 },	-- Strong Iron Lockbox
	[4637]	= { 175, 200, 225, 275 },	-- Steel Lockbox
	[4638]	= { 225, 250, 275, 325 },	-- Reinforced Steel Lockbox
	[5758]	= { 225, 250, 275, 325 },	-- Mithril Lockbox
	[5759]	= { 225, 250, 275, 325 },	-- Thorium Lockbox
	[5760]	= { 225, 250, 275, 325 },	-- Eternium Lockbox
	[6354]	= { 1, 30, 55, 105 },		-- Small Locked Chest
	[6355]	= { 70, 95, 120, 170 },		-- Sturdy Locked Chest
	[6712]	= { 1, 30, 55, 105 },		-- Practice Lock
	[12033]	= { 275, 300, 325, 375 },	-- Thaurissan Family Jewels
	[13875]	= { 175, 200, 225, 275 },	-- Ironbound Locked Chest
	[13918]	= { 250, 275, 300, 350 },	-- Reinforced Locked Chest
}

-------------------------------------------------------------------------------
-- GAMEOBJECT LOCK REQUIREMENTS
-- [gameObjectID] = required
--
-- Plain number only.
-- These IDs are the GO entry IDs (IDs from gameobjectcache.wdb),
-- what ClassicAPI's GameTooltip:GetGameObject() returns as `id`.
-------------------------------------------------------------------------------
local GO_REQUIREMENTS = {
	-- Training lockboxes & strongboxes --
	-- Practice Lockbox
	[178244]	= 1,
	[178245]	= 1,
	[178246]	= 1,
	-- Buccaneer's Strongbox
	[123330]	= 1,
	[123331]	= 1,
	[123332]	= 1,
	[123333]	= 1,

	-- Dungeons --
	[16397]		= 1,	-- Deadmines, Iron Clad Door
	[90566]		= 150,	-- Gnomeregan, Workshop Door
	[101851]	= 175,	-- Scarlet Monastery, Armory Door
	[101854]	= 175,	-- Scarlet Monastery, Herod's Door
	[101850]	= 175,	-- Scarlet Monastery, Cathedral Door
	[104591]	= 175,	-- Scarlet Monastery, Chapel Door
	[170559]	= 250,	-- Blackrock Depths, Shadowforge Gate
	[170560]	= 250,	-- ^
	[170570]	= 250,	-- Blackrock Depths, East Garrison Door
	[161460]	= 250,	-- Blackrock Depths, The Shadowforge Lock
	[170562]	= 250,	-- Blackrock Depths, Cell Door
	[170563]	= 250,	-- ^
	[170564]	= 250,	-- ^
	[170565]	= 250,	-- ^
	[170566]	= 250,	-- ^
	[170567]	= 250,	-- ^
	[170568]	= 250,	-- ^
	[170569]	= 250,	-- ^
	[177192]	= 300, 	-- Dire Maul, North
	[179549]	= 300,	-- ^
	[177217]	= 200, 	-- Dire Maul, North, Gordok Inner Door
	[177188]	= 300,	-- Dire Maul, West
	[177189]	= 300,	-- ^
	[177221]	= 300,	-- Dire Maul, East
	[179549]	= 300,	-- ^
	[179550]	= 300,	-- ^
	[177198]	= 300,	-- Dire Maul, East, Side Entrance
	[174626]	= 280,  -- Scholomance, Scholomance Door
	[175369]	= 300,	-- Stratholme, Elders' Square Service Entrance
	[175368]	= 300,  -- Stratholme, Service Entrance Gate
	[175357]	= 300,  -- Stratholme, Gauntlet Gate
	[175352]	= 300,  -- Stratholme, King's Square Gate
	[175967]	= 175,  -- Stratholme, The Bastion Door

	-- Loch Modan/Searing Gorge Gate --
	[150137]	= 225,	-- Searing Gorge
	[150138]	= 225,	-- Loch Modan

	-- Outdoor/generic chests --
	[3239]		= 100,	-- Benedict's Chest
	[20691]		= 160,	-- Cozzle's Footlocker
	[103815]	= 1,	-- Ambermill Strongbox
	[105176]	= 1,	-- Venture Co. Strongbox
	[121264]	= 25,	-- Lucius's Lockbox
	[123214]	= 70,	-- Duskwood Chest
	[129127]	= 70,	-- Gallywix's Lockbox
	[179498]	= 250,  -- Scarlet Footlocker
	-- Alliance Strongbox
	[3714]		= 1,
	[4095]		= 25,
	[105570]	= 70,
	-- Mossy Footlocker
	[179493]	= 175,
	[179497]	= 225,
	-- Large Iron Bound Chest
	[74447]		= 25,
	[75295]		= 1,
	[75296]		= 70,
	[75297]		= 125,
	-- Large Mithril Bound Chest
	[131978]	= 175,
	[153468]	= 250,
	[153469]	= 275,
	-- Battered Footlocker
	[179486]	= 70,
	[179488]	= 110,
	[179490]	= 150,
	-- Dented Footlocker
	[179492]	= 175,
	[179494]	= 200,
	[179496]	= 225,
	-- Waterlogged Footlocker
	[179487]	= 70,
	[179489]	= 110,
	[179491]	= 150,
}

-------------------------------------------------------------------------------
-- LOCKED TEXT EXCEPTIONS
-- Some objects allow lockpicking but do not show a "Locked" line in their
-- tooltip. List their GO IDs here to bypass the IsTooltipLocked() guard.
-------------------------------------------------------------------------------
local GO_NO_LOCKED_TEXT = {
	[3239]		= true,
	[20691]		= true,
}

-------------------------------------------------------------------------------
-- PENDING CACHE LOADS
-- When a GO is not yet in the client cache we request it asynchronously.
-- We store the goID so that when GAMEOBJECT_DATA_LOAD_RESULT fires we can
-- decide whether to re-show a pending tooltip.
-------------------------------------------------------------------------------
local pendingLoad = {}

-------------------------------------------------------------------------------
-- HELPER: GetLockpickingSkill
-- Returns the player's current Lockpicking rank, or 0 if they lack the skill.
-------------------------------------------------------------------------------
local function GetLockpickingSkill()
	for i = 1, GetNumSkillLines() do
		local name, _, _, rank = GetSkillLineInfo(i)
		if name == "Lockpicking" then
			return tonumber(rank) or 0
		end
	end
	return 0
end

-------------------------------------------------------------------------------
-- HELPER: CanPickLock(required)
-- Returns true if player's Lockpicking skill meets the requirement.
-------------------------------------------------------------------------------
local function CanPickLock(required)
	required = tonumber(required) or 0
	return GetLockpickingSkill() >= required
end

-------------------------------------------------------------------------------
-- HELPER: IsRogue
-- Only rogues have Lockpicking. We show the addon lines only for rogues,
-- but still silently remain loaded so the tooltip hooks do not error.
-------------------------------------------------------------------------------
local function IsRogue()
	local _, class = UnitClass("player")
	return class == "ROGUE"
end

-------------------------------------------------------------------------------
-- HELPER: GetTooltipLockedLine
-- Scans the visible GameTooltip lines for a line containing "Locked".
-- Returns (lineIndex, r, g, b) or (nil) if not found.
-------------------------------------------------------------------------------
local function GetTooltipLockedLine()
	for i = 2, 30 do
		local left = getglobal("GameTooltipTextLeft" .. i)
		if not left then break end
		local t = left:GetText()
		if t and string.find(t, "Locked") then
			local r, g, b = left:GetTextColor()
			return i, (r or 0), (g or 0), (b or 0)
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- HELPER: IsTooltipLocked
-- Returns true when the tooltip contains a "Locked" line.
-------------------------------------------------------------------------------
local function IsTooltipLocked()
	return GetTooltipLockedLine() ~= nil
end

-------------------------------------------------------------------------------
-- HELPER: GetTooltipRequiresKeyLine
-- Scans visible GameTooltip lines for a "Requires <Key>" line, ex: a line
-- that starts with "Requires" but does not contain "Lockpicking".
-------------------------------------------------------------------------------
local function GetTooltipRequiresKeyLine()
	for i = 2, 30 do
		local left = getglobal("GameTooltipTextLeft" .. i)
		if not left then break end
		local t = left:GetText()
		if t and string.find(t, "^Requires") and not string.find(t, "Lockpicking") then
			local r, g, b = left:GetTextColor()
			return i, t, (r or 1), (g or 1), (b or 1)
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- HELPER: GetSimpleColor(pickable)
-- Returns match or simple green/red color. Used for bag item tooltips.
-------------------------------------------------------------------------------
local function GetSimpleColor(pickable)
	if LockpickMasterDB.colorMode == "match" then
		local _, r, g, b = GetTooltipLockedLine()
		if r then
			return string.format("|cff%02x%02x%02x",
				math.floor(r * 255),
				math.floor(g * 255),
				math.floor(b * 255))
		end
	end
	return pickable and "|cff00ff00" or "|cffff2020"
end

-------------------------------------------------------------------------------
-- HELPER: GetThresholdColor(skill, required, entry)
-- Returns a difficulty color using thresholds from entry if present.
-- entry = { required, yellow, green, grey }
-- Falls back to simple green/red if no thresholds.
-------------------------------------------------------------------------------
local function GetThresholdColor(skill, required, entry)
	if skill < required then
		return "|cffff2020"
	end
	if type(entry) == "table" and entry[2] and entry[3] and entry[4] then
		if skill < entry[2] then
			return "|cffff7f00"  -- orange
		elseif skill < entry[3] then
			return "|cffffff00"  -- yellow
		elseif skill < entry[4] then
			return "|cff40bf40"  -- green
		else
			return "|cff808080"  -- grey
		end
	end
	return "|cff00ff00"
end

-------------------------------------------------------------------------------
-- HELPER: GetRequired(entry)
-- Extracts the required skill from either a plain number or table entry.
-------------------------------------------------------------------------------
local function GetRequired(entry)
	if type(entry) == "table" then
		return tonumber(entry[1])
	end
	return tonumber(entry)
end

-------------------------------------------------------------------------------
-- HELPER: AppendLockLine(entry, tooltip, useThresholds)
-- Adds the lockpicking line to the tooltip.
-- entry: plain number or { required, yellow, green, grey }
-- tooltip: frame to write to, defaults to GameTooltip
-- useThresholds: if true, applies difficulty color thresholds
-------------------------------------------------------------------------------
local function AppendLockLine(entry, tooltip, useThresholds)
	if not IsRogue() then return end
	tooltip = tooltip or GameTooltip
	local required = GetRequired(entry)
	if not required then return end
	local skill = GetLockpickingSkill()
	local color

	if useThresholds then
		color = GetThresholdColor(skill, required, entry)
	else
		color = GetSimpleColor(skill >= required)
	end

	if skill >= required then
		local suffix = LockpickMasterDB.showSkillSuffix and (" |cffaaddff(" .. skill .. ")|r") or ""
		tooltip:AddLine(color .. "Requires Lockpicking " .. "(" .. required .. ")" .. suffix)
	else
		local deficit = required - skill
		local suffix = LockpickMasterDB.showSkillSuffix and (" |cffff8040(need " .. deficit .. " more)|r") or ""
		tooltip:AddLine(color .. "Requires Lockpicking " .. "(" .. required .. ")" .. suffix)
	end
	tooltip:Show()
end

local function HandleGameObjectTooltip()
	if not GameTooltip:HasGameObject() then return end

	local name, goID, guid = GameTooltip:GetGameObject()
	if not goID or goID == 0 then return end

	-- Only act on locked objects to avoid cluttering all GO tooltips.
	-- Exception: some objects don't show "Locked" but are still pickable.
	if not IsTooltipLocked() and not GO_NO_LOCKED_TEXT[goID] then return end

	local entry = GO_REQUIREMENTS[goID]

	-- If not found, check if the GO data is in the client cache.
	-- If it's not cached yet, request a load and bail; we'll retry on the event.
	if not entry then
		local info = C_GameObjectInfo.GetGameObjectInfoByID(goID)
		if not info then
			if not pendingLoad[goID] then
				pendingLoad[goID] = true
				C_GameObjectInfo.RequestLoadGameObjectByID(goID)
			end
		end
		return
	end

	if not IsRogue() then return end

	local lockedIndex = GetTooltipLockedLine()
	if not lockedIndex then return end

	local keyLineIndex, keyLineText, keyR, keyG, keyB = GetTooltipRequiresKeyLine()

	local required = GetRequired(entry)
	local skill = GetLockpickingSkill()
	local color = GetSimpleColor(skill >= required)
	local ourText
	if skill >= required then
		local suffix = LockpickMasterDB.showSkillSuffix and (" |cffaaddff(" .. skill .. ")|r") or ""
		ourText = color .. "Requires Lockpicking (" .. required .. ")" .. suffix
	else
		local deficit = required - skill
		local suffix = LockpickMasterDB.showSkillSuffix and (" |cffff8040(need " .. deficit .. " more)|r") or ""
		ourText = color .. "Requires Lockpicking (" .. required .. ")" .. suffix
	end

	local ourSlot = lockedIndex + 1
	local ourFrame = getglobal("GameTooltipTextLeft" .. ourSlot)
	if not ourFrame then
		GameTooltip:AddLine(ourText)
		GameTooltip:Show()
		return
	end

	if keyLineIndex and keyLineText then
		ourFrame:SetText(ourText)
		GameTooltip:AddLine(
			string.format("|cff%02x%02x%02x",
				math.floor(keyR * 255),
				math.floor(keyG * 255),
				math.floor(keyB * 255))
			.. keyLineText)
	else
		GameTooltip:AddLine(ourText)
	end

	GameTooltip:Show()
end

local function HandleItemTooltip()
	local name, link, itemID = GameTooltip:GetItem()
	if not itemID then return end

	local entry = LOCKBOX_ITEMS[itemID]
	if not entry then return end

	for i = 2, 30 do
		local left = getglobal("GameTooltipTextLeft" .. i)
		if not left then break end
		local t = left:GetText()
		if t and string.find(t, "<Right Click to Open>", 1, true) then
			return
		end
	end

	if MerchantFrame and MerchantFrame:IsVisible() then
		if not IsRogue() then return end
		local required = GetRequired(entry)
		local skill = GetLockpickingSkill()
		local color = GetSimpleColor(skill >= required)
		local ourText
		if skill >= required then
			local suffix = LockpickMasterDB.showSkillSuffix and (" |cffaaddff(" .. skill .. ")|r") or ""
			ourText = color .. "Requires Lockpicking (" .. required .. ")" .. suffix
		else
			local deficit = required - skill
			local suffix = LockpickMasterDB.showSkillSuffix and (" |cffff8040(need " .. deficit .. " more)|r") or ""
			ourText = color .. "Requires Lockpicking (" .. required .. ")" .. suffix
		end

		for i = 2, 30 do
			local left = getglobal("GameTooltipTextLeft" .. i)
			if not left then break end
			local t = left:GetText()
			if t then
					if string.find(t, "^No sell price") then
					local r, g, b = left:GetTextColor()
					left:SetText(ourText)
					GameTooltip:AddLine(
						string.format("|cff%02x%02x%02x",
							math.floor((r or 1) * 255),
							math.floor((g or 1) * 255),
							math.floor((b or 1) * 255))
						.. t)
					GameTooltip:Show()
					return
				elseif t == " " then
					left:SetText(ourText)
					GameTooltip:AddLine(" ", 1.0, 1.0, 1.0)
					local numLines = GameTooltip:NumLines()
					local moneyFrame = getglobal("GameTooltipMoneyFrame")
					if moneyFrame then
						moneyFrame:SetPoint("LEFT", "GameTooltipTextLeft" .. numLines, "LEFT", 4, 0)
					end
					GameTooltip:Show()
					return
				end
			end
		end
	end

	AppendLockLine(entry, GameTooltip, false)
end

-------------------------------------------------------------------------------
-- HOOKS: OnShow/OnHide
-- Using SetScript with saved previous handler chaining rather than HookScript
-- prevents hook stacking across reloads/relogs.
-------------------------------------------------------------------------------
local lastTooltipID = nil

local prevOnShow = GameTooltip:GetScript("OnShow")
GameTooltip:SetScript("OnShow", function()
	if prevOnShow then prevOnShow() end

	local tooltipID = nil

	if GameTooltip:HasGameObject() then
		local _, goID = GameTooltip:GetGameObject()
		tooltipID = "go:" .. tostring(goID)
		if tooltipID ~= lastTooltipID then
			lastTooltipID = tooltipID
			HandleGameObjectTooltip()
		end
	elseif GameTooltip:GetItem() then
		local _, _, itemID = GameTooltip:GetItem()
		if itemID then
			tooltipID = "item:" .. tostring(itemID)
			if tooltipID ~= lastTooltipID then
				lastTooltipID = tooltipID
				HandleItemTooltip()
			end
		end
	end
end)

local prevOnHide = GameTooltip:GetScript("OnHide")
GameTooltip:SetScript("OnHide", function()
	if prevOnHide then prevOnHide() end
	lastTooltipID = nil
end)

-------------------------------------------------------------------------------
-- HOOK: ItemRefTooltip OnShow
-- Chat link tooltips use ItemRefTooltip, not GameTooltip.
-- The item link is parsed from the tooltip's own GetItem() call, falling back
-- to scanning tooltip lines for an item: hyperlink if GetItem() returns nil.
-------------------------------------------------------------------------------
local lastItemRefID = nil

ItemRefTooltip:SetScript("OnShow", function()
	local _, _, itemID = ItemRefTooltip:GetItem()
	if not itemID then
		-- GetItem() may return nil for hyperlinks; scan line 1 for the link
		local line = getglobal("ItemRefTooltipTextLeft1")
		if line then
			local text = line:GetText() or ""
			local _, _, found = string.find(text, "item:(%d+)")
			itemID = tonumber(found)
		end
	end
	if not itemID then return end
	if itemID == lastItemRefID then return end
	lastItemRefID = itemID
	local entry = LOCKBOX_ITEMS[itemID]
	if not entry then return end
	AppendLockLine(entry, ItemRefTooltip, true)
end)

ItemRefTooltip:SetScript("OnHide", function()
	lastItemRefID = nil
end)

-------------------------------------------------------------------------------
-- EVENT FRAME
-- Handles GAMEOBJECT_DATA_LOAD_RESULT for async cache fills.
-- If the tooltip is still showing the same GO after the cache loads,
-- we append the lock line retroactively.
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GAMEOBJECT_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then
		if LockpickMasterDB.showLoginMsg then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cffffff00" .. ADDON_NAME .. "|r v" .. ADDON_VERSION .. " loaded."
				.. "  Type |cffaaddff/lm|r for help.")
		end

	elseif event == "GAMEOBJECT_DATA_LOAD_RESULT" then
		local goID	  = arg1
		local success = arg2
		pendingLoad[goID] = nil

		if success and GameTooltip:HasGameObject() then
			local _, activeID = GameTooltip:GetGameObject()
			if activeID == goID and IsTooltipLocked() then
				local entry = GO_REQUIREMENTS[goID]
				if entry then
					AppendLockLine(entry, GameTooltip, false)
				end
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- SLASH COMMANDS
-- /lm or /lockpickmaster
-------------------------------------------------------------------------------
SLASH_LOCKPICKMASTER1 = "/lm"
SLASH_LOCKPICKMASTER2 = "/lockpickmaster"

SlashCmdList["LOCKPICKMASTER"] = function(msg)
	local arg = string.lower(msg or "")

	-- /lm --
	if arg == "" then
		local skill = GetLockpickingSkill()
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffffff00" .. ADDON_NAME .. "|r v" .. ADDON_VERSION
			.. " - Your Lockpicking: |cffaaddff" .. skill .. "|r"
			.. " | Color mode: |cffaaddff" .. LockpickMasterDB.colorMode .. "|r")
		DEFAULT_CHAT_FRAME:AddMessage("Commands:")
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaddff/lm items:|r     - list known lockbox items")
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaddff/lm objects:|r  - list known unlockable objects")
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaddff/lm skill:|r       - toggle |cffaaddff(you: X)|r / |cffff8040(need X more)|r suffix on tooltips")
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaddff/lm color:|r     - toggle color mode (simple / match)")
		DEFAULT_CHAT_FRAME:AddMessage("  |cffaaddff/lm login:|r     - toggle the login message")

	-- /lm skill --
	elseif arg == "skill" then
		LockpickMasterDB.showSkillSuffix = not LockpickMasterDB.showSkillSuffix
		if LockpickMasterDB.showSkillSuffix then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cffffff00" .. ADDON_NAME .. "|r: Skill suffix |cff00ff00ON|r"
				.. " - tooltips will show |cffaaddff(you: X)|r / |cffff8040(need X more)|r.")
		else
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cffffff00" .. ADDON_NAME .. "|r: Skill suffix |cffff2020OFF|r"
				.. " - tooltips will show the required skill only.")
		end

	-- /lm items --
	elseif arg == "items" then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffffff00" .. ADDON_NAME .. " - Known unlockable items:|r")
		-- Collect into a sortable array.
		local sorted = {}
		for id, entry in pairs(LOCKBOX_ITEMS) do
			sorted[table.getn(sorted) + 1] = { id = id, entry = entry, req = GetRequired(entry) }
		end
		table.sort(sorted, function(a, b)
			if a.req ~= b.req then return a.req < b.req end
			return a.id < b.id
		end)
		for _, row in ipairs(sorted) do
			local name, _, quality = GetItemInfo(row.id)
			local canPick = CanPickLock(row.req)
			local label
			if name then
				local r, g, b = GetItemQualityColor(quality or 0)
				local col = string.format("|cff%02x%02x%02x",
					math.floor((r or 1) * 255),
					math.floor((g or 1) * 255),
					math.floor((b or 1) * 255))
				label = col .. "|Hitem:" .. row.id .. ":0:0:0|h[" .. name .. "]|h|r"
			else
				local col = canPick and "|cff00ff00" or "|cffff2020"
				label = col .. "Item #" .. row.id .. "|r"
			end
			DEFAULT_CHAT_FRAME:AddMessage(
				"  " .. label
				.. " (ID: " .. row.id .. ")"
				.. "  - requires |cffaaddff" .. row.req .. "|r"
				.. (canPick and " |cff00ff00(pickable)|r" or " |cffff2020(too low)|r"))
		end

	-- /lm objects --
	elseif arg == "objects" then
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffffff00" .. ADDON_NAME .. " - Known unlockable objects (GO IDs):|r")
		-- Collect into a sortable array.
		local sorted = {}
		for goID, entry in pairs(GO_REQUIREMENTS) do
			sorted[table.getn(sorted) + 1] = { goID = goID, entry = entry, req = GetRequired(entry) }
		end
		table.sort(sorted, function(a, b)
			if a.req ~= b.req then return a.req < b.req end
			return a.goID < b.goID
		end)
		local uncached = false
		for _, row in ipairs(sorted) do
			local info = C_GameObjectInfo.GetGameObjectInfoByID(row.goID)
			local label
			if info and info.name and info.name ~= "" then
				label = info.name
			else
				C_GameObjectInfo.RequestLoadGameObjectByID(row.goID)
				label = "|cffaaaaaa[loading...]|r"
				uncached = true
			end
			local canPick = CanPickLock(row.req)
			local col = canPick and "|cff00ff00" or "|cffff2020"
			DEFAULT_CHAT_FRAME:AddMessage(
				"  " .. col .. label .. "|r  (ID: " .. row.goID .. ")"
				.. "  - requires |cffaaddff" .. row.req .. "|r"
				.. (canPick and " |cff00ff00(pickable)|r" or " |cffff2020(too low)|r"))
		end
		if uncached then
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cffaaaaaa[loading...] entries are not yet cached. " ..
				"Type |cffaaddff/lm objects|r again in a moment to see their names.|r")
		end

	-- /lm color --
	elseif arg == "color" or arg == "colour" then
		if LockpickMasterDB.colorMode == "simple" then
			LockpickMasterDB.colorMode = "match"
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cffffff00" .. ADDON_NAME .. "|r: Color mode: "
				.. "|cffaaddffMatch|r (mirrors the game's Locked line color).")
		else
			LockpickMasterDB.colorMode = "simple"
			DEFAULT_CHAT_FRAME:AddMessage(
				"|cffffff00" .. ADDON_NAME .. "|r: Color mode: "
				.. "|cffaaddffSimple|r "
				.. "(|cff00ff00green|r = pickable, |cffff2020red|r = too low).")
		end

	-- /lm login
	elseif arg == "login" then
		LockpickMasterDB.showLoginMsg = not LockpickMasterDB.showLoginMsg
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffffff00" .. ADDON_NAME .. "|r: Login message "
			.. (LockpickMasterDB.showLoginMsg and "|cff00ff00ON|r." or "|cffff2020OFF|r."))

	else
		DEFAULT_CHAT_FRAME:AddMessage(
			"|cffffff00" .. ADDON_NAME .. "|r: Unknown command '"
			.. msg .. "'. Type |cffaaddff/lm|r for help.")
	end
end
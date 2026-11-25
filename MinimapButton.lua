-- QuickRaidMark minimap button: hover for the add-on's name, click to open a
-- small settings window. It shows the menu key with a button that opens the
-- game's keybinding settings at the "Quick Raid Mark Menu" binding, and lets
-- you pick Ctrl, Alt or Shift for switching marker sets. Drag the button to
-- move it around the minimap.
--
-- Built on LibDataBroker + LibDBIcon (in Libs\), the standard minimap-button
-- library, so button-collector add-ons (Leatrix Plus, MinimapButtonButton,
-- etc.) gather it with its own tooltip and click instead of replacing them.

local ADDON_NAME, ns = ... -- ns: shared with QuickRaidMark.lua (swap key)
local TITLE = "QuickRaidMark"
local BINDING_LABEL = "Quick Raid Mark Menu" -- see BINDING_NAME_ in QuickRaidMark.lua
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" -- Skull
local DEFAULT_POSITION = 225 -- degrees around the minimap

local function Print(msg)
	print("|cff66ccffQuickRaidMark:|r " .. msg)
end

----------------------------------------------------------------------
-- Opening the keybinding settings at our binding
----------------------------------------------------------------------
local function OpenKeybinding()
	if InCombatLockdown() then
		Print("Keybindings can't be changed in combat. Try again after the fight.")
		return
	end

	if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
		Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
		-- Filter the list down to our binding by typing its name into the
		-- settings search box, once the panel has finished opening.
		C_Timer.After(0, function()
			local box = SettingsPanel and SettingsPanel.SearchBox
			if box and box.SetText then
				pcall(box.SetText, box, BINDING_LABEL)
			end
		end)
	elseif KeyBindingFrame_LoadUI then -- older-style keybinding window
		KeyBindingFrame_LoadUI()
		if KeyBindingFrame then ShowUIPanel(KeyBindingFrame) end
	else
		Print("Open Options > Keybindings > AddOns > QuickRaidMark to set the key.")
	end
end

----------------------------------------------------------------------
-- Settings window (opened by clicking the minimap button)
----------------------------------------------------------------------
local BINDING_ACTION = "CLICK QuickRaidMarkToggle:LeftButton"
local window

local function BuildWindow()
	local f = CreateFrame("Frame", "QuickRaidMarkSettings", UIParent, "BackdropTemplate")
	f:SetSize(270, 200)
	f:SetPoint("CENTER", 0, 100)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	-- drag anywhere on the window to move it
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, f:GetName()) -- Escape closes it

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText(TITLE)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Menu key: shows the current binding, button to change it.
	local keyHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	keyHeader:SetPoint("TOPLEFT", 24, -52)
	keyHeader:SetText("Menu key")

	local keyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	keyText:SetPoint("TOPLEFT", keyHeader, "BOTTOMLEFT", 0, -4)

	local keyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	keyButton:SetSize(120, 22)
	keyButton:SetPoint("TOPRIGHT", -24, -54)
	keyButton:SetText("Change keybind")
	keyButton:SetScript("OnClick", function()
		f:Hide()
		OpenKeybinding()
	end)

	-- Swap key: three radio buttons in a row.
	local swapHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	swapHeader:SetPoint("TOPLEFT", 24, -104)
	swapHeader:SetText("Raid/ground swap key")

	local swapNote = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	swapNote:SetPoint("TOPLEFT", swapHeader, "BOTTOMLEFT", 0, -4)
	swapNote:SetText("Press it while the menu is open to switch sets.")
	swapNote:SetTextColor(0.75, 0.75, 0.75)

	local radios = {}
	local function Refresh()
		local key = GetBindingKey(BINDING_ACTION)
		if key then
			keyText:SetText(GetBindingText and GetBindingText(key) or key)
			keyText:SetTextColor(1, 1, 1)
		else
			keyText:SetText("Not bound")
			keyText:SetTextColor(1, 0.3, 0.3)
		end
		local current = ns.GetSwapKey()
		for k, radio in pairs(radios) do
			radio:SetChecked(k == current)
		end
	end

	for i, k in ipairs(ns.SWAP_KEY_ORDER) do
		local radio = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
		radio:SetSize(20, 20)
		radio:SetPoint("TOPLEFT", 24 + (i - 1) * 76, -144)
		-- own label (and a wider click area that includes it)
		local label = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
		label:SetText(ns.SWAP_KEYS[k].label)
		radio:SetHitRectInsets(0, -(label:GetStringWidth() + 8), 0, 0)
		radio:SetScript("OnClick", function()
			if not ns.SetSwapKey(k) then
				Print("The swap key can't be changed in combat. Try again after the fight.")
			end
			Refresh() -- re-check the right one either way
		end)
		radios[k] = radio
	end

	f:SetScript("OnShow", Refresh)
	f:RegisterEvent("UPDATE_BINDINGS")
	f:SetScript("OnEvent", function(self)
		if self:IsShown() then Refresh() end
	end)
	return f
end

local function ToggleWindow()
	GameTooltip:Hide()
	window = window or BuildWindow()
	window:SetShown(not window:IsShown())
end

----------------------------------------------------------------------
-- Registration (once saved variables are loaded)
----------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON_NAME then return end
	self:UnregisterEvent("ADDON_LOADED")

	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (LDB and DBIcon) then return end

	QuickRaidMarkDB = QuickRaidMarkDB or {}
	QuickRaidMarkDB.minimap = QuickRaidMarkDB.minimap or { minimapPos = DEFAULT_POSITION }

	local launcher = LDB:NewDataObject(ADDON_NAME, {
		type = "launcher",
		text = TITLE,
		icon = ICON,
		OnClick = function()
			ToggleWindow()
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(TITLE)
			tooltip:AddLine("Click for settings", 0.8, 0.8, 0.8)
			tooltip:AddLine("Drag to move this button", 0.8, 0.8, 0.8)
		end,
	})
	DBIcon:Register(ADDON_NAME, launcher, QuickRaidMarkDB.minimap)
end)

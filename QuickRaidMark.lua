-- QuickRaidMark: hold a keybind to open a radial raid-marker menu centred on the
-- cursor, move the mouse toward a marker, and release the key to mark your
-- current target with it.
--
-- Setting raid markers is a protected action on this client, so addon code
-- cannot call SetRaidTarget() directly. Instead the keybind "clicks" a secure
-- action button: a secure snippet shows the menu on key-down, and on key-up
-- works out which marker the mouse is pointing at and lets the button run the
-- game's /tm command for it. All of this works in combat.

-- Labels shown in Options > Keybindings
BINDING_HEADER_QUICKRAIDMARK = "QuickRaidMark"
_G["BINDING_NAME_CLICK QuickRaidMarkToggle:LeftButton"] = "Marker menu (hold, point, release)"

-- The game's "/tm" (target marker) slash command.
local TARGET_MARKER_CMD = SLASH_TARGET_MARKER3 or "/tm"
-- Ground (world) markers: "/wm N" puts a targeting circle on the cursor to
-- click where the marker goes; "/cwm all" removes every ground marker.
local WORLD_MARKER_CMD = "/wm"
local CLEAR_WORLD_MARKER_CMD = "/cwm"

-- Layout (all sizes in UI pixels)
local MENU_SIZE   = 223  -- diameter of the dark background circle
local WEDGE_TEXTURE_SIZE = 250 -- the slice highlight textures are drawn for this size
local BACKGROUND_ALPHA = 0.35 -- 0 = invisible, 1 = solid black
local WEDGE_ALPHA = 0.6  -- how dark the pointed-at slice gets (0 = not at all, 1 = black)
local DIM_ALPHA   = 0.2  -- icons not pointed at, while a slice is pointed at
local BACKDROP_DIM_ALPHA = 0.3 -- background and lines, while a slice is pointed at
local RING_RADIUS = 85   -- distance from the centre to each marker icon
local KEY_LABEL_RADIUS = 48 -- distance from the centre to each number-key label
local ICON_SIZE   = 34   -- the centre Skull
local RING_ICON_SIZE = 28 -- the icons around the ring
local HOVER_SCALE = 1.45 -- how much the pointed-at ring icon grows
local DEAD_ZONE   = 28   -- releasing within this distance of the centre marks CENTRE_MARKER
local LINE_INNER  = 26   -- divider lines start just outside the centre...
local LINE_OUTER  = 104  --...and end near the edge of the background

-- Raid marker indexes: 1 Star, 2 Circle, 3 Diamond, 4 Triangle,
-- 5 Moon, 6 Square, 7 Cross, 8 Skull.
-- 0 = clear the target's marker.
-- Skull sits in the centre, so a quick tap of the keybind marks Skull.
-- The ring is placed clockwise starting at the top; the bottom slot clears.
local CENTRE_MARKER = 8
local MARKER_ORDER = { 7, 4, 5, 2, 0, 3, 6, 1 }

-- Pressing Ctrl while the menu is open switches between raid and ground
-- markers, and the menu remembers the set until Ctrl is pressed again. The icons stay where they are; each raid marker maps to the
-- ground marker with the same symbol (ground markers are numbered
-- differently). The clear slot removes all ground markers.
local GROUND_FOR_MARKER = {
	[0] = 0, -- clear: /cwm all
	[1] = 5, -- Star
	[2] = 6, -- Circle
	[3] = 3, -- Diamond
	[4] = 2, -- Triangle
	[5] = 7, -- Moon
	[6] = 1, -- Square
	[7] = 4, -- Cross
	[8] = 8, -- Skull
}

-- The game's marker artwork fills its texture unevenly (the Cross reaches
-- the edges, the Circle has a lot of empty space), so each icon gets a
-- size factor to make them look the same size. Tweak these by eye.
local ICON_SCALE = {
	[0] = 0.80, -- clear (red X)
	[1] = 1.00, -- Star
	[2] = 1.10, -- Circle
	[3] = 1.00, -- Diamond
	[4] = 1.00, -- Triangle
	[5] = 1.05, -- Moon
	[6] = 0.95, -- Square
	[7] = 0.85, -- Cross
	[8] = 1.00, -- Skull
}
local function IconSize(markerIndex, base)
	return (base or ICON_SIZE) * (ICON_SCALE[markerIndex] or 1)
end

local function MarkerTexture(markerIndex)
	if markerIndex == 0 then
		return "Interface\\Buttons\\UI-GroupLoot-Pass-Up" -- red X: clear
	end
	return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. markerIndex
end

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAN_22_5 = 0.41421356 -- tan(22.5 degrees): half the width of each slice

local function Print(msg)
	print("|cff66ccffQuickRaidMark:|r " .. msg)
end

-- Explains why nothing happened, and returns true if the mark should have
-- landed. Only prints; the secure button does the marking. `hadUnit` is
-- true when the unit under the cursor was marked (the target is already
-- cleared again by then).
-- Warnings print at most once every WARN_COOLDOWN seconds.
local WARN_COOLDOWN = 10
local lastWarn = -math.huge
local function Warn(msg)
	local now = GetTime()
	if now - lastWarn >= WARN_COOLDOWN then
		lastWarn = now
		Print(msg)
	end
end

local function WarnIfCannotMark(hadUnit, ground)
	if not ground and not hadUnit and not UnitExists("target") then
		Warn("You have no target, and there was no unit under your cursor.")
		return false
	elseif IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		Warn("You need to be raid leader or assistant to set markers in a raid.")
		return false
	end
	return true
end

-- Which ring slot (1 = top, then clockwise to 8 = top-left) the mouse points
-- at, given its offset from the menu centre. nil means the centre (Skull).
-- The secure snippet further down repeats this same logic; keep them in sync.
local function SlotFromOffset(dx, dy)
	if dx * dx + dy * dy < DEAD_ZONE * DEAD_ZONE then
		return nil
	end
	local ax, ay = math.abs(dx), math.abs(dy)
	if ay < ax * TAN_22_5 then
		return dx > 0 and 3 or 7          -- right / left
	elseif ax < ay * TAN_22_5 then
		return dy > 0 and 1 or 5          -- top / bottom
	elseif dy > 0 then
		return dx > 0 and 2 or 8          -- top-right / top-left
	else
		return dx > 0 and 4 or 6          -- bottom-right / bottom-left
	end
end

----------------------------------------------------------------------
-- Screen-sized secure frame, used only to read the cursor position from
-- inside secure snippets (works in combat).
----------------------------------------------------------------------
local screen = CreateFrame("Frame", "QuickRaidMarkScreen", UIParent, "SecureFrameTemplate")
screen:SetAllPoints(UIParent)

----------------------------------------------------------------------
-- Menu frame (display only; nothing in it is clickable)
----------------------------------------------------------------------
local menu = CreateFrame("Frame", "QuickRaidMarkMenu", UIParent, "SecureHandlerBaseTemplate")
menu:SetFrameStrata("DIALOG")
menu:SetSize(MENU_SIZE, MENU_SIZE)
menu:Hide()

-- Round dark background, one even shade. It and the faint lines fade back
-- (see SetHovered) while a slice is pointed at.
local backdrop = {}
do
	local disc = menu:CreateTexture(nil, "BACKGROUND")
	backdrop[#backdrop + 1] = disc
	disc:SetAllPoints()
	disc:SetColorTexture(0, 0, 0, BACKGROUND_ALPHA)

	local mask = menu:CreateMaskTexture()
	mask:SetAllPoints(disc)
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	disc:AddMaskTexture(mask)
end

-- Highlight of the slice being pointed at: a darkened fill plus a glowing
-- gold outline. Both textures are a slice pointing straight up from the menu
-- centre and are rotated to each slice.
-- (Media/make_wedge_layers.py regenerates them if they need restyling.)
local wedgeFill = menu:CreateTexture(nil, "BACKGROUND", nil, 1)
wedgeFill:SetSize(WEDGE_TEXTURE_SIZE, WEDGE_TEXTURE_SIZE)
wedgeFill:SetPoint("CENTER")
wedgeFill:SetTexture("Interface\\AddOns\\QuickRaidMark\\Media\\WedgeFill")
wedgeFill:SetVertexColor(0, 0, 0, WEDGE_ALPHA) -- white slice tinted black
wedgeFill:Hide()

local wedgeOutline = menu:CreateTexture(nil, "BORDER", nil, 1) -- above the divider lines
wedgeOutline:SetSize(WEDGE_TEXTURE_SIZE, WEDGE_TEXTURE_SIZE)
wedgeOutline:SetPoint("CENTER")
wedgeOutline:SetTexture("Interface\\AddOns\\QuickRaidMark\\Media\\WedgeOutline")
wedgeOutline:SetBlendMode("ADD")
wedgeOutline:Hide()

local wedge = {
	SetRotation = function(_, r) wedgeFill:SetRotation(r) wedgeOutline:SetRotation(r) end,
	Show = function() wedgeFill:Show() wedgeOutline:Show() end,
	Hide = function() wedgeFill:Hide() wedgeOutline:Hide() end,
}

-- Faint divider lines between the markers.
for i = 0, #MARKER_ORDER - 1 do
	local angle = math.rad(90 - 22.5 - i * (360 / #MARKER_ORDER))
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local line = menu:CreateLine(nil, "BORDER")
	backdrop[#backdrop + 1] = line
	line:SetThickness(2)
	line:SetColorTexture(1, 1, 1, 0.12)
	line:SetStartPoint("CENTER", menu, cosA * LINE_INNER, sinA * LINE_INNER)
	line:SetEndPoint("CENTER", menu, cosA * LINE_OUTER, sinA * LINE_OUTER)
end

----------------------------------------------------------------------
-- Marker icons around the ring
----------------------------------------------------------------------
local slots = {}

for i, markerIndex in ipairs(MARKER_ORDER) do
	local angle = math.rad(90 - (i - 1) * (360 / #MARKER_ORDER))
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local texturePath = MarkerTexture(markerIndex)

	local size = IconSize(markerIndex, RING_ICON_SIZE)
	local icon = menu:CreateTexture(nil, "ARTWORK")
	icon:SetSize(size, size)
	icon:SetPoint("CENTER", menu, "CENTER", cosA * RING_RADIUS, sinA * RING_RADIUS)
	icon:SetTexture(texturePath)

	-- Additive copy of the icon, shown while pointed at, to make it glow.
	local glow = menu:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints(icon)
	glow:SetTexture(texturePath)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0.5)
	glow:Hide()

	-- Small number on the inner side of the slice: the number key for this
	-- marker (keys run 1 Skull ... 8 Star, i.e. key = 9 - marker). Skull is
	-- in the centre and the clear slot has no key, so neither gets one.
	local keyLabel
	if markerIndex ~= 0 then
		keyLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		keyLabel:SetPoint("CENTER", menu, "CENTER", cosA * KEY_LABEL_RADIUS, sinA * KEY_LABEL_RADIUS)
		keyLabel:SetText(9 - markerIndex)
		keyLabel:SetTextColor(0.85, 0.85, 0.85)
		keyLabel:SetShadowOffset(1, -1)
	end

	slots[i] = { icon = icon, glow = glow, size = size, keyLabel = keyLabel,
		x = cosA * RING_RADIUS, y = sinA * RING_RADIUS }
end

----------------------------------------------------------------------
-- Centre: gold ring with the Skull. Releasing the key here (or just
-- tapping it) marks Skull.
----------------------------------------------------------------------
local CENTRE_ICON_SIZE = IconSize(CENTRE_MARKER)
local CENTRE_CIRCLE_SEGMENTS = 40

local centre = CreateFrame("Frame", nil, menu)
centre:SetSize(LINE_INNER * 2, LINE_INNER * 2)
centre:SetPoint("CENTER")

local centreIcon = centre:CreateTexture(nil, "ARTWORK")
centreIcon:SetSize(CENTRE_ICON_SIZE, CENTRE_ICON_SIZE)
centreIcon:SetPoint("CENTER")
centreIcon:SetTexture(MarkerTexture(CENTRE_MARKER))

-- Plain thin circle where the divider lines start, drawn in the same
-- style as the dividers (a ring of short line segments).
for i = 0, CENTRE_CIRCLE_SEGMENTS - 1 do
	local a1 = math.rad(i * 360 / CENTRE_CIRCLE_SEGMENTS)
	local a2 = math.rad((i + 1) * 360 / CENTRE_CIRCLE_SEGMENTS)
	local seg = menu:CreateLine(nil, "BORDER")
	backdrop[#backdrop + 1] = seg
	seg:SetThickness(2)
	seg:SetColorTexture(1, 1, 1, 0.12)
	seg:SetStartPoint("CENTER", menu, math.cos(a1) * LINE_INNER, math.sin(a1) * LINE_INNER)
	seg:SetEndPoint("CENTER", menu, math.cos(a2) * LINE_INNER, math.sin(a2) * LINE_INNER)
end

local centreGlow = centre:CreateTexture(nil, "OVERLAY", nil, 1)
centreGlow:SetSize(CENTRE_ICON_SIZE + 10, CENTRE_ICON_SIZE + 10)
centreGlow:SetPoint("CENTER")
centreGlow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
centreGlow:SetBlendMode("ADD")
centreGlow:Hide()

----------------------------------------------------------------------
-- Live highlight of whatever the mouse is pointing at (visual only)
----------------------------------------------------------------------
local hoveredSlot = false -- false = nothing drawn yet, nil = centre

local function SetHovered(slot)
	if slot == hoveredSlot then
		return
	end
	if hoveredSlot then
		local old = slots[hoveredSlot]
		old.icon:SetSize(old.size, old.size)
		old.glow:Hide()
	end
	if slot then
		local new = slots[slot]
		new.icon:SetSize(new.size * HOVER_SCALE, new.size * HOVER_SCALE)
		new.glow:Show()
		-- Slot 1 is the top; each later slot is 45 degrees further clockwise.
		wedge:SetRotation(-math.rad((slot - 1) * (360 / #MARKER_ORDER)))
		wedge:Show()
	else
		wedge:Hide()
	end
	-- While a ring slice is pointed at, every other icon fades back.
	for i, s in ipairs(slots) do
		local a = (slot and i ~= slot) and DIM_ALPHA or 1
		s.icon:SetAlpha(a)
		if s.keyLabel then s.keyLabel:SetAlpha(a) end
	end
	centreIcon:SetAlpha(slot and DIM_ALPHA or 1)
	for _, region in ipairs(backdrop) do
		region:SetAlpha(slot and BACKDROP_DIM_ALPHA or 1)
	end
	centreGlow:SetShown(slot == nil)
	hoveredSlot = slot
end

-- Fade in over FADE_IN_TIME seconds after the menu opens. (Only the alpha
-- changes, which addon code may do in combat; showing, hiding and placing
-- the menu stay with the secure snippet.)
local FADE_IN_TIME = 0.12
local fadeElapsed = FADE_IN_TIME
local menuX, menuY -- where the menu was last shown, for the confirmation pulse

menu:SetScript("OnUpdate", function(self, elapsed)
	if fadeElapsed < FADE_IN_TIME then
		fadeElapsed = fadeElapsed + elapsed
		self:SetAlpha(math.min(1, fadeElapsed / FADE_IN_TIME))
	end

	local cx, cy = self:GetCenter()
	if not cx then return end
	menuX, menuY = cx, cy
	local x, y = GetCursorPosition()
	local scale = self:GetEffectiveScale()
	SetHovered(SlotFromOffset(x / scale - cx, y / scale - cy))
end)
menu:HookScript("OnShow", function(self)
	fadeElapsed = 0
	self:SetAlpha(0)
	hoveredSlot = false
	SetHovered(nil)
end)

----------------------------------------------------------------------
-- Confirmation: the chosen icon briefly swells and fades where it sat in
-- the menu. A plain (not secure) frame, so it can play in combat.
----------------------------------------------------------------------
local PULSE_TIME  = 0.35
local PULSE_SCALE = 1.8

local pulse = CreateFrame("Frame", nil, UIParent)
pulse:SetFrameStrata("DIALOG")
pulse:Hide()
local pulseIcon = pulse:CreateTexture(nil, "ARTWORK")
pulseIcon:SetAllPoints()

local pulseAnim = pulse:CreateAnimationGroup()
local grow = pulseAnim:CreateAnimation("Scale")
grow:SetScaleFrom(1, 1)
grow:SetScaleTo(PULSE_SCALE, PULSE_SCALE)
grow:SetDuration(PULSE_TIME)
grow:SetSmoothing("OUT")
local fade = pulseAnim:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0)
fade:SetDuration(PULSE_TIME)
fade:SetSmoothing("IN")
pulseAnim:SetScript("OnFinished", function() pulse:Hide() end)

-- slot: 0 = centre, 1-8 = ring slot.
local function PlayPulse(slot)
	if not menuX then return end
	local markerIndex, ox, oy, size
	if slot == 0 then
		markerIndex, ox, oy = CENTRE_MARKER, 0, 0
		size = IconSize(CENTRE_MARKER)
	else
		local s = slots[slot]
		if not s then return end
		markerIndex, ox, oy = MARKER_ORDER[slot], s.x, s.y
		size = s.size * HOVER_SCALE
	end
	pulseAnim:Stop()
	pulseIcon:SetTexture(MarkerTexture(markerIndex))
	pulse:SetSize(size, size)
	pulse:ClearAllPoints()
	pulse:SetPoint("CENTER", UIParent, "BOTTOMLEFT", menuX + ox, menuY + oy)
	pulse:Show()
	pulseAnim:Play()
end

----------------------------------------------------------------------
-- The keybind button (see Bindings.xml). Hold = show menu, release = mark.
----------------------------------------------------------------------
local toggle = CreateFrame("Button", "QuickRaidMarkToggle", UIParent, "SecureActionButtonTemplate")
toggle:RegisterForClicks("AnyUp", "AnyDown")
toggle:SetAttribute("useOnKeyDown", false) -- run the action on release
toggle:SetAttribute("type", "macro")
toggle:SetAttribute("macrotext", "")
for i, markerIndex in ipairs(MARKER_ORDER) do
	toggle:SetAttribute("marker" .. i, markerIndex)
	toggle:SetAttribute("groundmarker" .. i, GROUND_FOR_MARKER[markerIndex])
end
toggle:SetAttribute("centremarker", CENTRE_MARKER)
toggle:SetAttribute("centregroundmarker", GROUND_FOR_MARKER[CENTRE_MARKER])
toggle:SetAttribute("tmcmd", TARGET_MARKER_CMD)
toggle:SetAttribute("wmcmd", WORLD_MARKER_CMD)
toggle:SetAttribute("cwmcmd", CLEAR_WORLD_MARKER_CMD)
SecureHandlerSetFrameRef(toggle, "screen", screen)

-- Pressing Ctrl while the menu is open flips it between raid and ground
-- markers (the "ground" attribute on the keybind button). The choice stays
-- until Ctrl flips it back, so the menu reopens on the set used last.
-- A secure state driver watches Ctrl, so this works in combat.
local ctrlWatcher = CreateFrame("Frame", "QuickRaidMarkCtrlWatcher", UIParent, "SecureHandlerStateTemplate")
SecureHandlerSetFrameRef(ctrlWatcher, "toggle", toggle)
SecureHandlerSetFrameRef(ctrlWatcher, "menu", menu)
ctrlWatcher:SetAttribute("_onstate-ctrl", [[
	if newstate ~= "down" then return end
	local menu = self:GetFrameRef("menu")
	if not menu:IsShown() then return end
	local toggle = self:GetFrameRef("toggle")
	toggle:SetAttribute("ground", not toggle:GetAttribute("ground"))
]])
RegisterStateDriver(ctrlWatcher, "ctrl", "[mod:ctrl] down; up")

-- Shows which set the menu is on: a label just under the menu.
local modeLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
modeLabel:SetPoint("TOP", menu, "BOTTOM", 0, -4)
modeLabel:SetShadowOffset(1, -1)

-- Hint just above the menu.
local hintLabel = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintLabel:SetPoint("BOTTOM", menu, "TOP", 0, 4)
hintLabel:SetShadowOffset(1, -1)
hintLabel:SetTextColor(0.8, 0.8, 0.8)

local function ShowMode(ground)
	if ground then
		modeLabel:SetText("Ground markers")
		modeLabel:SetTextColor(0.55, 0.85, 1)
		hintLabel:SetText("Press Ctrl for raid markers")
	else
		modeLabel:SetText("Raid markers")
		modeLabel:SetTextColor(1, 0.82, 0)
		hintLabel:SetText("Press Ctrl for ground markers")
	end
end
ShowMode(false)

toggle:HookScript("OnAttributeChanged", function(_, name, value)
	if name == "ground" then
		ShowMode(value)
	end
end)

-- Runs (securely) before every click of the button, with `owner` = the menu.
-- Returning false cancels the click; returning nothing lets the macro run.
-- (Global function form: frames created from Lua don't get the
-- WrapScript/SetFrameRef methods on this client.)
--
-- Marking the unit under the cursor: /tm can only mark a unit token, and
-- "mouseover" changes as soon as the mouse moves toward a marker. So if you
-- have no target when the key goes down, the unit under the cursor is
-- targeted right then (the macro runs on key-down for that one press), and
-- on release it is marked and the target is cleared again, leaving you
-- with no target as before.
SecureHandlerWrapScript(toggle, "OnClick", menu, ([[
	local screen = self:GetFrameRef("screen")
	local x, y = screen:GetMousePosition()
	if x then
		x, y = x * screen:GetWidth(), y * screen:GetHeight()
	end

	if down then
		-- Key pressed: open the menu centred on the cursor.
		if not x then
			x, y = screen:GetWidth() / 2, screen:GetHeight() / 2
		end
		centreX, centreY = x, y
		self:SetAttribute("lastslot", nil)
		self:SetAttribute("borrowed", nil)
		-- (checked before the menu shows, since the menu takes the mouse)
		local borrow = SecureCmdOptionParse("[@target,exists] no; [@mouseover,exists] yes; no") == "yes"
		owner:ClearAllPoints()
		owner:SetPoint("CENTER", screen, "BOTTOMLEFT", x, y)
		owner:Show()
		-- number keys 1-8 pick a marker while the menu is open
		-- (also bound with Ctrl, in case Ctrl is still held after flipping)
		for i = 1, 8 do
			owner:SetBindingClick(true, "" .. i, "QuickRaidMarkNumber" .. i)
			owner:SetBindingClick(true, "CTRL-" .. i, "QuickRaidMarkNumber" .. i)
		end
		if borrow then
			self:SetAttribute("borrowed", true)
			self:SetAttribute("useOnKeyDown", true) -- run this one on key-down
			self:SetAttribute("macrotext", "/target mouseover")
			return
		end
		return false
	end

	-- Key released.
	owner:ClearBindings() -- number keys go back to normal
	self:SetAttribute("useOnKeyDown", false)
	local after = ""
	if self:GetAttribute("borrowed") then
		after = "\n/cleartarget"
		-- if nothing gets marked below, still give the target back
		self:SetAttribute("macrotext", "/cleartarget")
	end

	-- Close the menu and mark whatever the mouse points at.
	-- (returning nothing runs the /cleartarget set above; false runs nothing)
	if not owner:IsShown() then
		if after == "" then return false end
		return
	end
	owner:Hide()
	if not x or not centreX then
		if after == "" then return false end
		return
	end

	-- Which set the menu is on (Ctrl flips it; see ctrlWatcher).
	local ground = self:GetAttribute("ground")
	local dx, dy = x - centreX, y - centreY
	local slot, marker
	if dx * dx + dy * dy < %d then -- centre (or a quick tap): Skull
		slot = 0
		if ground then
			marker = self:GetAttribute("centregroundmarker")
		else
			marker = self:GetAttribute("centremarker")
		end
	end

	if not slot then
	local ax, ay = dx, dy
	if ax < 0 then ax = -ax end
	if ay < 0 then ay = -ay end
	if ay < ax * %f then
		if dx > 0 then slot = 3 else slot = 7 end
	elseif ax < ay * %f then
		if dy > 0 then slot = 1 else slot = 5 end
	elseif dy > 0 then
		if dx > 0 then slot = 2 else slot = 8 end
	else
		if dx > 0 then slot = 4 else slot = 6 end
	end
	if ground then
		marker = self:GetAttribute("groundmarker" .. slot)
	else
		marker = self:GetAttribute("marker" .. slot)
	end
	end

	local command
	if not ground then
		command = self:GetAttribute("tmcmd") .. " " .. marker
	elseif marker == 0 then
		command = self:GetAttribute("cwmcmd") .. " all"
	else
		command = self:GetAttribute("wmcmd") .. " " .. marker
	end
	self:SetAttribute("lastslot", slot)
	self:SetAttribute("macrotext", command .. after)
]]):format(DEAD_ZONE * DEAD_ZONE, TAN_22_5, TAN_22_5))

toggle:SetScript("PostClick", function(self, _, down)
	-- (Only reads the attribute: changing attributes from normal addon code
	-- is blocked in combat. The secure snippet resets it on each key press.)
	if down then return end
	local slot = self:GetAttribute("lastslot")
	if slot and WarnIfCannotMark(self:GetAttribute("borrowed"), self:GetAttribute("ground")) then
		PlayPulse(slot)
	end
end)

----------------------------------------------------------------------
-- Number keys: while the menu is open, 1-8 are bound (by the secure snippet
-- above) to these hidden buttons. Pressing one closes the menu and marks at
-- once (on whichever set the menu is on). Releasing the
-- menu key afterwards does nothing more.
----------------------------------------------------------------------
-- Key number -> raid marker: 1 Skull, 2 Cross, 3 Square, 4 Moon,
-- 5 Triangle, 6 Diamond, 7 Circle, 8 Star.
local NUMBER_KEY_MARKER = { 8, 7, 6, 5, 4, 3, 2, 1 }

-- Where a marker sits in the menu, for the pulse: 0 = centre, else ring slot.
local function SlotForMarker(markerIndex)
	if markerIndex == CENTRE_MARKER then return 0 end
	for i, m in ipairs(MARKER_ORDER) do
		if m == markerIndex then return i end
	end
end

for key, markerIndex in ipairs(NUMBER_KEY_MARKER) do
	local button = CreateFrame("Button", "QuickRaidMarkNumber" .. key, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "")
	button:SetAttribute("marker", markerIndex)
	button:SetAttribute("groundmarker", GROUND_FOR_MARKER[markerIndex])
	SecureHandlerSetFrameRef(button, "toggle", toggle)

	SecureHandlerWrapScript(button, "OnClick", menu, [[
		self:SetAttribute("fired", nil)
		if not owner:IsShown() then return false end
		owner:Hide()
		owner:ClearBindings()

		local toggle = self:GetFrameRef("toggle")
		local ground = toggle:GetAttribute("ground") -- the set the menu is on
		local command
		if ground then
			command = toggle:GetAttribute("wmcmd") .. " " .. self:GetAttribute("groundmarker")
		else
			command = toggle:GetAttribute("tmcmd") .. " " .. self:GetAttribute("marker")
		end
		if toggle:GetAttribute("borrowed") then
			command = command .. "\n/cleartarget"
		end
		self:SetAttribute("fired", true)
		self:SetAttribute("macrotext", command)
	]])

	button:SetScript("PostClick", function(self)
		if not self:GetAttribute("fired") then return end
		if WarnIfCannotMark(toggle:GetAttribute("borrowed"), toggle:GetAttribute("ground")) then
			PlayPulse(SlotForMarker(markerIndex))
		end
	end)
end

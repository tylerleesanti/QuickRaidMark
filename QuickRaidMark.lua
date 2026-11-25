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
_G["BINDING_NAME_CLICK QuickRaidMarkToggle:LeftButton"] = "Quick Raid Mark Menu"

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
local CLEAR_SLOT -- the ring slot holding 0 (clear)
for i, m in ipairs(MARKER_ORDER) do
	if m == 0 then CLEAR_SLOT = i end
end

-- Pressing the swap key (Ctrl by default) while the menu is open switches
-- between raid and ground markers, and the menu remembers the set until it
-- is pressed again. The icons stay where they are; each raid marker maps to the
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

-- Ground-marker look, so the two sets can't be mistaken for each other:
-- the background turns dark brown, the lines and slice outline turn blue,
-- and every marker sits on a coloured pool of light, like the real ground
-- markers.
local RAID_BG   = { 0, 0, 0, BACKGROUND_ALPHA }
local GROUND_BG = { 0.18, 0.11, 0.05, 0.6 } -- dark brown
local RAID_LINE   = { 1, 1, 1, 0.12 }
local GROUND_LINE = { 0.5, 0.8, 1, 0.3 }
local GROUND_OUTLINE = { 0.45, 0.8, 1 } -- slice outline tint
-- Colour of each ground marker's light (by raid marker index).
local MARKER_COLOR = {
	[1] = { 1.00, 0.92, 0.20 }, -- Star
	[2] = { 1.00, 0.55, 0.10 }, -- Circle
	[3] = { 0.80, 0.30, 1.00 }, -- Diamond
	[4] = { 0.30, 1.00, 0.30 }, -- Triangle
	[5] = { 0.75, 0.85, 1.00 }, -- Moon
	[6] = { 0.25, 0.60, 1.00 }, -- Square
	[7] = { 1.00, 0.25, 0.20 }, -- Cross
	[8] = { 1.00, 1.00, 1.00 }, -- Skull
}

local groundMode = false -- which look the menu currently has

local function SizeIcon(texture, size)
	texture:SetSize(size, size)
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

-- Everything outside the centre (slice highlight, divider lines, ring icons,
-- key numbers, labels) sits on this layer, so the opening animation can
-- fade it in as one piece after the centre has appeared.
local ringLayer = CreateFrame("Frame", nil, menu)
ringLayer:SetAllPoints()

-- Round dark background, one even shade. It and the faint lines fade back
-- (see SetHovered) while a slice is pointed at. It grows out from the centre
-- when the menu opens (see ApplyOpen).
local backdrop = {}
local disc = menu:CreateTexture(nil, "BACKGROUND")
do
	backdrop[#backdrop + 1] = disc
	disc:SetSize(MENU_SIZE, MENU_SIZE)
	disc:SetPoint("CENTER")
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
local wedgeFill = ringLayer:CreateTexture(nil, "BACKGROUND", nil, 1)
wedgeFill:SetSize(WEDGE_TEXTURE_SIZE, WEDGE_TEXTURE_SIZE)
wedgeFill:SetPoint("CENTER")
wedgeFill:SetTexture("Interface\\AddOns\\QuickRaidMark\\Media\\WedgeFill")
wedgeFill:SetVertexColor(0, 0, 0, WEDGE_ALPHA) -- white slice tinted black
wedgeFill:Hide()

local wedgeOutline = ringLayer:CreateTexture(nil, "BORDER", nil, 1) -- above the divider lines
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

-- Faint divider lines between the markers (and, further down, the centre
-- circle). Kept in `lines` so they can be recoloured for ground markers.
local lines = {}
for i = 0, #MARKER_ORDER - 1 do
	local angle = math.rad(90 - 22.5 - i * (360 / #MARKER_ORDER))
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local line = ringLayer:CreateLine(nil, "BORDER")
	backdrop[#backdrop + 1] = line
	lines[#lines + 1] = line
	line:SetThickness(2)
	line:SetColorTexture(1, 1, 1, 0.12)
	line:SetStartPoint("CENTER", menu, cosA * LINE_INNER, sinA * LINE_INNER)
	line:SetEndPoint("CENTER", menu, cosA * LINE_OUTER, sinA * LINE_OUTER)
end

----------------------------------------------------------------------
-- Marker icons around the ring
----------------------------------------------------------------------
local slots = {}

-- A glowing ground circle in the marker's colour at the foot of `icon`
-- (it follows the icon as it moves and grows), squashed flat so it looks
-- like it lies on the ground. It breathes slowly while shown. Hidden until
-- ground markers. (Media/make_ground_pool.py regenerates the texture.)
local GROUND_POOL_TEXTURE = "Interface\\AddOns\\QuickRaidMark\\Media\\GroundPool"
local POOL_PULSE_TIME = 1.2 -- seconds from bright to dim

local function MakeGroundPool(parent, icon, markerIndex)
	local color = MARKER_COLOR[markerIndex]
	if not color then return nil end -- the clear slot has none
	local pool = parent:CreateTexture(nil, "ARTWORK", nil, -1) -- under the icon
	-- a flat ellipse straddling the icon's bottom edge, as if it stands on it
	pool:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -9, 9)
	pool:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 9, -8)
	pool:SetTexture(GROUND_POOL_TEXTURE)
	pool:SetVertexColor(color[1], color[2], color[3], 0.9)
	pool:SetBlendMode("ADD")

	local pulse = pool:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local dim = pulse:CreateAnimation("Alpha")
	dim:SetFromAlpha(1)
	dim:SetToAlpha(0.55)
	dim:SetDuration(POOL_PULSE_TIME)
	dim:SetSmoothing("IN_OUT")
	pool.pulse = pulse

	pool:Hide()
	return pool
end

local function ShowGroundPool(pool, shown)
	if not pool then return end
	pool:SetShown(shown)
	if shown then pool.pulse:Play() else pool.pulse:Stop() end
end

for i, markerIndex in ipairs(MARKER_ORDER) do
	local angle = math.rad(90 - (i - 1) * (360 / #MARKER_ORDER))
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local texturePath = MarkerTexture(markerIndex)

	local size = IconSize(markerIndex, RING_ICON_SIZE)
	local icon = ringLayer:CreateTexture(nil, "ARTWORK")
	icon:SetSize(size, size)
	icon:SetPoint("CENTER", menu, "CENTER", cosA * RING_RADIUS, sinA * RING_RADIUS)
	icon:SetTexture(texturePath)

	-- Pool of coloured light under the marker, shown on ground markers.
	local pool = MakeGroundPool(ringLayer, icon, markerIndex)

	-- Additive copy of the icon, shown while pointed at, to make it glow.
	local glow = ringLayer:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints(icon)
	glow:SetTexture(texturePath)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0.5)
	glow:Hide()

	-- Small number on the inner side of the slice: the number key for this
	-- marker (keys run 1 Skull ... 8 Star, 9 clear, i.e. key = 9 - marker).
	-- Skull is in the centre, so it has no label (its key is 1).
	local keyLabel = ringLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	keyLabel:SetPoint("CENTER", menu, "CENTER", cosA * KEY_LABEL_RADIUS, sinA * KEY_LABEL_RADIUS)
	keyLabel:SetText(9 - markerIndex)
	keyLabel:SetTextColor(0.85, 0.85, 0.85)
	keyLabel:SetShadowOffset(1, -1)

	slots[i] = { icon = icon, glow = glow, pool = pool, size = size, keyLabel = keyLabel,
		cos = cosA, sin = sinA, x = cosA * RING_RADIUS, y = sinA * RING_RADIUS }
end

----------------------------------------------------------------------
-- Centre: gold ring with the Skull. Releasing the key here (or just
-- tapping it) marks Skull.
----------------------------------------------------------------------
local CENTRE_ICON_SIZE = IconSize(CENTRE_MARKER)
local CENTRE_CIRCLE_SEGMENTS = 40

local centre = CreateFrame("Frame", nil, menu)
centre:SetFrameLevel(ringLayer:GetFrameLevel() + 1)
centre:SetSize(LINE_INNER * 2, LINE_INNER * 2)
centre:SetPoint("CENTER")

local centreIcon = centre:CreateTexture(nil, "ARTWORK")
centreIcon:SetSize(CENTRE_ICON_SIZE, CENTRE_ICON_SIZE)
centreIcon:SetPoint("CENTER")
centreIcon:SetTexture(MarkerTexture(CENTRE_MARKER))
local centrePool = MakeGroundPool(centre, centreIcon, CENTRE_MARKER)

-- Plain thin circle where the divider lines start, drawn in the same
-- style as the dividers (a ring of short line segments).
for i = 0, CENTRE_CIRCLE_SEGMENTS - 1 do
	local a1 = math.rad(i * 360 / CENTRE_CIRCLE_SEGMENTS)
	local a2 = math.rad((i + 1) * 360 / CENTRE_CIRCLE_SEGMENTS)
	local seg = centre:CreateLine(nil, "BORDER") -- fades in with the centre
	backdrop[#backdrop + 1] = seg
	lines[#lines + 1] = seg
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
local hoveredSlot = false -- false = nothing drawn yet, nil = centre,
                          -- 0 = nothing highlighted (number keys used)

local function SetHovered(slot)
	if slot == hoveredSlot then
		return
	end
	if hoveredSlot and hoveredSlot > 0 then
		local old = slots[hoveredSlot]
		SizeIcon(old.icon, old.size)
		old.glow:Hide()
	end
	local ring = slot and slot > 0 and slot or nil -- the ring slot to light up
	if ring then
		local new = slots[ring]
		SizeIcon(new.icon, new.size * HOVER_SCALE)
		new.glow:Show()
		-- Slot 1 is the top; each later slot is 45 degrees further clockwise.
		wedge:SetRotation(-math.rad((ring - 1) * (360 / #MARKER_ORDER)))
		wedge:Show()
	else
		wedge:Hide()
	end
	-- While a ring slice is pointed at, every other icon fades back.
	for i, s in ipairs(slots) do
		local a = (ring and i ~= ring) and DIM_ALPHA or 1
		s.icon:SetAlpha(a)
		if s.keyLabel then s.keyLabel:SetAlpha(a) end
	end
	centreIcon:SetAlpha(ring and DIM_ALPHA or 1)
	for _, region in ipairs(backdrop) do
		region:SetAlpha(ring and BACKDROP_DIM_ALPHA or 1)
	end
	centreGlow:SetShown(slot == nil)
	hoveredSlot = slot
end

-- Opening animation, over OPEN_TIME seconds: the centre Skull pops in
-- first, the dark background grows out from the centre and darkens, and
-- then the ring (icons, lines, numbers, labels) fades in while sliding out
-- to its place. (Only sizes, positions and alpha of plain textures change,
-- which addon code may do in combat; showing, hiding and placing the menu
-- itself stay with the secure snippet.)
local OPEN_TIME   = 0.30 -- seconds for the whole opening
local RING_DELAY  = 0.25 -- fraction of OPEN_TIME before the ring starts to appear
local RING_START  = 0.60 -- the ring starts at this fraction of its full radius
local openElapsed = OPEN_TIME
local menuX, menuY -- where the menu was last shown, for the confirmation pulse

local function EaseOut(t)
	return 1 - (1 - t) * (1 - t)
end

-- p: 0 = just opened, 1 = fully open.
local function ApplyOpen(p)
	local e = EaseOut(p)

	-- Centre: quick fade and pop over the first part of the opening.
	local c = EaseOut(math.min(1, p / 0.4))
	centre:SetAlpha(c)
	SizeIcon(centreIcon, CENTRE_ICON_SIZE * (0.6 + 0.4 * c))

	-- Background: grows from the centre circle out to full size, darkening.
	local d = LINE_INNER * 2 + (MENU_SIZE - LINE_INNER * 2) * e
	disc:SetSize(d, d)
	local bg = groundMode and GROUND_BG or RAID_BG
	disc:SetColorTexture(bg[1], bg[2], bg[3], bg[4] * (0.3 + 0.7 * e))

	-- Ring: fades in and slides outward, starting a moment later.
	local r = EaseOut(math.max(0, math.min(1, (p - RING_DELAY) / (1 - RING_DELAY))))
	ringLayer:SetAlpha(r)
	local spread = RING_START + (1 - RING_START) * r
	for _, s in ipairs(slots) do
		s.icon:SetPoint("CENTER", menu, "CENTER", s.cos * RING_RADIUS * spread, s.sin * RING_RADIUS * spread)
		s.keyLabel:SetPoint("CENTER", menu, "CENTER", s.cos * KEY_LABEL_RADIUS * spread, s.sin * KEY_LABEL_RADIUS * spread)
	end
end

-- Switches the menu between the raid-marker and ground-marker look.
-- (Plain textures only, so it works in combat.)
local function ApplyMode(ground)
	ground = not not ground
	if ground == groundMode then return end
	groundMode = ground

	local line = ground and GROUND_LINE or RAID_LINE
	for _, l in ipairs(lines) do
		l:SetColorTexture(line[1], line[2], line[3], line[4])
	end
	if ground then
		wedgeOutline:SetDesaturated(true)
		wedgeOutline:SetVertexColor(GROUND_OUTLINE[1], GROUND_OUTLINE[2], GROUND_OUTLINE[3])
	else
		wedgeOutline:SetDesaturated(false)
		wedgeOutline:SetVertexColor(1, 1, 1)
	end

	-- Show (or hide) the pool of light under every marker.
	for _, s in ipairs(slots) do
		ShowGroundPool(s.pool, ground)
	end
	ShowGroundPool(centrePool, ground)

	-- Background colour and centre size: let a running opening animation
	-- pick them up, otherwise set them straight away.
	ApplyOpen(math.min(1, openElapsed / OPEN_TIME))
end

menu:SetScript("OnUpdate", function(self, elapsed)
	if openElapsed < OPEN_TIME then
		openElapsed = openElapsed + elapsed
		ApplyOpen(math.min(1, openElapsed / OPEN_TIME))
	end

	local cx, cy = self:GetCenter()
	if not cx then return end
	menuX, menuY = cx, cy
	local x, y = GetCursorPosition()
	local scale = self:GetEffectiveScale()
	local slot = SlotFromOffset(x / scale - cx, y / scale - cy)
	-- After a number key, releasing won't mark by direction, so stop
	-- highlighting slices (the mouse is off pointing at mobs anyway).
	-- On ground markers the Clear slice still works, so it still lights up.
	if QuickRaidMarkToggle:GetAttribute("numberused") then
		if not (groundMode and slot == CLEAR_SLOT) then
			slot = 0
		end
	end
	SetHovered(slot)
end)
local menuOpenedAt = 0 -- GetTime() when the menu last opened

menu:HookScript("OnShow", function(self)
	menuOpenedAt = GetTime()
	openElapsed = 0
	ApplyOpen(0)
	-- (re)start the ground circles' breathing, in case it stopped while hidden
	if groundMode then
		for _, s in ipairs(slots) do ShowGroundPool(s.pool, true) end
		ShowGroundPool(centrePool, true)
	end
	hoveredSlot = false
	SetHovered(nil)
end)

----------------------------------------------------------------------
-- Confirmation: the chosen icon briefly swells and fades where it sat in
-- the menu. A plain (not secure) frame, so it can play in combat.
----------------------------------------------------------------------
local PULSE_TIME  = 0.35
-- Menu open for less than this many seconds (a quick tap for Skull):
-- skip the pulse when the key is released.
local QUICK_TAP_TIME = 0.25
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
	SizeIcon(pulse, size)
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

-- Pressing the swap key (Ctrl by default; Alt or Shift can be chosen from
-- the minimap button) while the menu is open flips it between raid and
-- ground markers (the "ground" attribute on the keybind button). The choice
-- stays until the swap key flips it back, so the menu reopens on the set
-- used last. A secure state driver watches the key, so this works in combat.
local SWAP_KEYS = {
	CTRL  = { label = "Ctrl",  condition = "[mod:ctrl] down; up" },
	ALT   = { label = "Alt",   condition = "[mod:alt] down; up" },
	SHIFT = { label = "Shift", condition = "[mod:shift] down; up" },
}
local SWAP_KEY_ORDER = { "CTRL", "ALT", "SHIFT" }
local swapKey = "CTRL"
toggle:SetAttribute("swapprefix", "CTRL-") -- for the number-key bindings

local ctrlWatcher = CreateFrame("Frame", "QuickRaidMarkCtrlWatcher", UIParent, "SecureHandlerStateTemplate")
SecureHandlerSetFrameRef(ctrlWatcher, "toggle", toggle)
SecureHandlerSetFrameRef(ctrlWatcher, "menu", menu)
ctrlWatcher:SetAttribute("_onstate-swap", [[
	if newstate ~= "down" then return end
	local menu = self:GetFrameRef("menu")
	if not menu:IsShown() then return end
	local toggle = self:GetFrameRef("toggle")
	toggle:SetAttribute("ground", not toggle:GetAttribute("ground"))
]])
RegisterStateDriver(ctrlWatcher, "swap", SWAP_KEYS[swapKey].condition)

-- Shows which set the menu is on: a label just under the menu.
local modeLabel = ringLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
modeLabel:SetPoint("TOP", menu, "BOTTOM", 0, -4)
modeLabel:SetShadowOffset(1, -1)

-- Hint just above the menu.
local hintLabel = ringLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintLabel:SetPoint("BOTTOM", menu, "TOP", 0, 4)
hintLabel:SetShadowOffset(1, -1)
hintLabel:SetTextColor(0.8, 0.8, 0.8)

local function ShowMode(ground)
	ApplyMode(ground)
	if QuickRaidMarkToggle:GetAttribute("numberused") then
		if ground then
			hintLabel:SetText("Release to close, or over Clear to remove all")
		else
			hintLabel:SetText("Release the key to close")
		end
	elseif ground then
		hintLabel:SetText("Press " .. SWAP_KEYS[swapKey].label .. " for raid markers")
	else
		hintLabel:SetText("Press " .. SWAP_KEYS[swapKey].label .. " for ground markers")
	end
	if ground then
		modeLabel:SetText("Ground markers")
		modeLabel:SetTextColor(0.55, 0.85, 1)
	else
		modeLabel:SetText("Raid markers")
		modeLabel:SetTextColor(1, 0.82, 0)
	end
end
ShowMode(false)

toggle:HookScript("OnAttributeChanged", function(_, name, value)
	if name == "ground" or name == "numberused" then
		ShowMode(toggle:GetAttribute("ground"))
	end
end)

-- Shared with MinimapButton.lua (its menu picks the swap key).
local ADDON_NAME, ns = ...
ns.SWAP_KEYS, ns.SWAP_KEY_ORDER = SWAP_KEYS, SWAP_KEY_ORDER
function ns.GetSwapKey()
	return swapKey
end
-- Changes the swap key and saves it. Secure setup, so not in combat:
-- returns false (and changes nothing) if it can't be done right now.
function ns.SetSwapKey(key)
	if not SWAP_KEYS[key] then return false end
	if InCombatLockdown() then return false end
	swapKey = key
	toggle:SetAttribute("swapprefix", key .. "-")
	RegisterStateDriver(ctrlWatcher, "swap", SWAP_KEYS[key].condition)
	ShowMode(toggle:GetAttribute("ground"))
	QuickRaidMarkDB = QuickRaidMarkDB or {}
	QuickRaidMarkDB.swapKey = key
	return true
end

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
		self:SetAttribute("numberused", nil)
		-- (checked before the menu shows, since the menu takes the mouse)
		local borrow = SecureCmdOptionParse("[@target,exists] no; [@mouseover,exists] yes; no") == "yes"
		owner:ClearAllPoints()
		owner:SetPoint("CENTER", screen, "BOTTOMLEFT", x, y)
		owner:Show()
		-- number keys 1-9 mark the unit under the mouse while the menu is open
		-- (also bound with the swap key, in case it's still held after flipping)
		for i = 1, 9 do
			owner:SetBindingClick(true, "" .. i, "QuickRaidMarkNumber" .. i)
			owner:SetBindingClick(true, self:GetAttribute("swapprefix") .. i, "QuickRaidMarkNumber" .. i)
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

	-- Which set the menu is on (the swap key flips it; see ctrlWatcher).
	local ground = self:GetAttribute("ground")

	-- Number keys were used while the menu was open: just close it.
	-- (On ground markers, releasing over the Clear slice still clears;
	-- that's checked below once the slot is known.)
	local numberused = self:GetAttribute("numberused")
	if numberused and not ground then
		owner:Hide()
		if after == "" then return false end
		return
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

	-- After number keys on ground markers, only the Clear slice does anything.
	if numberused and slot ~= %d then
		if after == "" then return false end
		return
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
]]):format(DEAD_ZONE * DEAD_ZONE, TAN_22_5, TAN_22_5, CLEAR_SLOT))

toggle:SetScript("PostClick", function(self, _, down)
	-- (Only reads the attribute: changing attributes from normal addon code
	-- is blocked in combat. The secure snippet resets it on each key press.)
	if down then return end
	local slot = self:GetAttribute("lastslot")
	if slot and WarnIfCannotMark(self:GetAttribute("borrowed"), self:GetAttribute("ground"))
			and GetTime() - menuOpenedAt >= QUICK_TAP_TIME then
		PlayPulse(slot)
	end
end)

----------------------------------------------------------------------
-- Number keys: while the menu is open, 1-9 are bound (by the secure snippet
-- above) to these hidden buttons. Each press marks the unit under the mouse
-- (or your target if the mouse isn't over a unit) and the menu STAYS OPEN,
-- so you can point at one mob after another and mark them all in one go.
-- Once a number key has been used, releasing the menu key just closes the
-- menu; it does not also mark by direction.
----------------------------------------------------------------------
-- Key number -> raid marker: 1 Skull, 2 Cross, 3 Square, 4 Moon,
-- 5 Triangle, 6 Diamond, 7 Circle, 8 Star, 9 clear.
local NUMBER_KEY_MARKER = { 8, 7, 6, 5, 4, 3, 2, 1, 0 }

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

		local toggle = self:GetFrameRef("toggle")
		-- tells the menu key's release not to mark by direction as well
		toggle:SetAttribute("numberused", true)

		local ground = toggle:GetAttribute("ground") -- the set the menu is on
		local command
		if ground then
			local g = self:GetAttribute("groundmarker")
			if g == 0 then
				command = toggle:GetAttribute("cwmcmd") .. " all"
			else
				command = toggle:GetAttribute("wmcmd") .. " " .. g
			end
		else
			-- the unit under the mouse, or the target if there isn't one
			local m = self:GetAttribute("marker")
			command = toggle:GetAttribute("tmcmd") .. " [@mouseover,exists] " .. m .. "; " .. m
		end
		self:SetAttribute("fired", true)
		self:SetAttribute("macrotext", command)
	]])

	button:SetScript("PostClick", function(self)
		if not self:GetAttribute("fired") then return end
		local hadUnit = toggle:GetAttribute("borrowed") or UnitExists("mouseover")
		if WarnIfCannotMark(hadUnit, toggle:GetAttribute("ground")) then
			PlayPulse(SlotForMarker(markerIndex))
		end
	end)
end

----------------------------------------------------------------------
-- Raid markers are the default: after IDLE_RESET seconds without using the
-- menu, it switches back from ground markers to raid markers.
--
-- The set lives in a secure attribute, which normal addon code may only
-- change out of combat. So the check runs every few seconds out of combat,
-- and once more right as combat starts (the last moment it is allowed).
-- If the five minutes run out mid-combat, the switch happens when combat
-- ends.
----------------------------------------------------------------------
local IDLE_RESET = 300 -- seconds (5 minutes)
local lastUse = GetTime()

local function NoteUse()
	lastUse = GetTime()
end
toggle:HookScript("PreClick", NoteUse)
for key = 1, #NUMBER_KEY_MARKER do
	_G["QuickRaidMarkNumber" .. key]:HookScript("PreClick", NoteUse)
end
toggle:HookScript("OnAttributeChanged", function(_, name)
	if name == "ground" then NoteUse() end -- swap-key flips count as use
end)

local function ResetIfIdle()
	if InCombatLockdown() or menu:IsShown() then return end
	if toggle:GetAttribute("ground") and GetTime() - lastUse >= IDLE_RESET then
		toggle:SetAttribute("ground", nil)
	end
end

C_Timer.NewTicker(5, ResetIfIdle)
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED") -- combat starting
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")  -- combat over
combatWatcher:SetScript("OnEvent", ResetIfIdle)

-- Saved swap key (see ns.SetSwapKey), applied once saved variables load.
local savedLoader = CreateFrame("Frame")
savedLoader:RegisterEvent("ADDON_LOADED")
savedLoader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON_NAME then return end
		self:UnregisterEvent("ADDON_LOADED")
	end
	local key = QuickRaidMarkDB and QuickRaidMarkDB.swapKey
	if key and key ~= swapKey and not ns.SetSwapKey(key) then
		-- (a /reload in combat) try again once combat ends
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end)

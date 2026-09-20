-- Wick's Poisons and Things
-- Combo.lua: combo points over the target's nameplate.
--
-- The client puts the class resource under the player's own nameplate and
-- nowhere else, so over the target's head has to be ours.
--
-- The catch is that combo points are a unit power, and on this client unit
-- power comes back as a secret value to an addon: the number has a type and
-- a home, but comparing it throws. So nothing here ever compares one. Each
-- pip is a status bar covering exactly one point of the range, and the raw
-- number goes straight into SetValue. Bar three fills when the third point
-- lands because its range is two to three, not because anything asked how
-- many points there are. That renders the same whether the value is secret
-- or plain, which means it keeps working if Blizzard changes its mind.

local ADDON, ns = ...
local Core = WickCore
local Chrome = Core.Chrome
local C = Chrome.Colors

local Combo = {}
ns.combo = Combo

local FALLBACK_MAX = 5
local PIP_W, PIP_H, PIP_GAP, PAD = 17, 6, 3, 3
local FILL = "Interface\\Buttons\\WHITE8X8"

local function powerType()
    return (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
end

local function db()
    return ns.A and ns.A.db and ns.A.db.profile or {}
end

-- Read without ever comparing. Both calls can hand back a secret.
local function points()
    if GetComboPoints then
        local ok, n = pcall(GetComboPoints, "player", "target")
        if ok and n ~= nil then return n end
    end
    local ok, n = pcall(UnitPower, "player", powerType())
    if ok and n ~= nil then return n end
    return 0
end

-- The maximum is worth asking for, since talents move it, but it is a
-- power too and can be secret. Ask the client whether it will answer
-- honestly before trusting a comparison on it.
local function maxPoints()
    local S = rawget(_G, "C_Secrets")
    if S and S.ShouldUnitPowerMaxBeSecret then
        local ok, secret = pcall(S.ShouldUnitPowerMaxBeSecret, "player", powerType())
        if ok and secret then return FALLBACK_MAX end
    end
    local ok, n = pcall(function()
        local v = UnitPowerMax("player", powerType())
        if type(v) == "number" and v > 0 and v <= 10 then return v end
        return nil
    end)
    if ok and n then return n end
    return FALLBACK_MAX
end

function Combo:Build()
    if self.row then return self.row end
    local row = CreateFrame("Frame", "WicksPoisonsComboRow", UIParent)
    row:SetHeight(PIP_H + PAD * 2)
    row:Hide()
    local bg = Chrome:Texture(row, "BACKGROUND", C.voidBG)
    bg:SetAllPoints()
    Chrome:AddBorder(row)
    row.pips = {}
    self.row = row
    self:Reshape()
    return row
end

function Combo:Reshape()
    local row = self.row
    if not row then return end
    local n = maxPoints()
    for i = #row.pips + 1, n do
        local bar = CreateFrame("StatusBar", nil, row)
        bar:SetStatusBarTexture(FILL)
        bar:SetStatusBarColor(C.fel[1], C.fel[2], C.fel[3], 1)
        local empty = Chrome:Texture(bar, "BACKGROUND", C.shadow)
        empty:SetAllPoints()
        row.pips[i] = bar
    end
    for i = 1, #row.pips do
        local bar = row.pips[i]
        if i <= n then
            -- One point of range each: pip i fills as the count crosses it.
            bar:SetMinMaxValues(i - 1, i)
            bar:SetSize(PIP_W, PIP_H)
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", row, "LEFT", PAD + (i - 1) * (PIP_W + PIP_GAP), 0)
            bar:Show()
        else
            bar:Hide()
        end
    end
    row.count = n
    row:SetWidth(PAD * 2 + n * PIP_W + math.max(0, n - 1) * PIP_GAP)
    self:Refresh()
end

function Combo:Refresh()
    local row = self.row
    if not row or not row.count then return end
    local n = points()
    for i = 1, row.count do
        pcall(row.pips[i].SetValue, row.pips[i], n)
    end
end

-- Ride whichever nameplate currently belongs to the target.
function Combo:Attach()
    local row = self.row or self:Build()
    if not ns.isRogue or db().comboOnPlate == false then
        row:Hide()
        return
    end
    local NP = rawget(_G, "C_NamePlate")
    local plate = NP and NP.GetNamePlateForUnit and NP.GetNamePlateForUnit("target")
    if not plate then
        row:Hide()
        return
    end
    local uf = plate.UnitFrame
    -- Anchor to a frame, never to a texture or font string.
    local anchor = (uf and (uf.HealthBarsContainer or uf.healthBar or uf.HealthBar)) or uf or plate
    row:SetParent(plate)
    row:SetFrameStrata("HIGH")
    row:ClearAllPoints()
    row:SetPoint("BOTTOM", anchor, "TOP", 0, 5)
    row:Show()
    self:Refresh()
end

function Combo:Init()
    if not ns.isRogue then return end
    self:Build()
    ns.RegisterEvents({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED",
        "UNIT_POWER_UPDATE",
        "UNIT_MAXPOWER",
    })
    ns:On("PLAYER_ENTERING_WORLD", function() Combo:Attach() end)
    ns:On("PLAYER_TARGET_CHANGED", function() Combo:Attach() end)
    ns:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
        if UnitIsUnit and UnitIsUnit(unit, "target") then Combo:Attach() end
    end)
    ns:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        if UnitIsUnit and UnitIsUnit(unit, "target") then Combo:Attach() end
    end)
    ns:On("UNIT_POWER_UPDATE", function(_, unit, token)
        if unit == "player" and (token == nil or token == "COMBO_POINTS") then Combo:Refresh() end
    end)
    ns:On("UNIT_MAXPOWER", function(_, unit, token)
        if unit == "player" and (token == nil or token == "COMBO_POINTS") then Combo:Reshape() end
    end)
end

function Combo:OptionRow(page, y)
    local O = Core.Options
    y = O:Heading(page, "Combo points", y)
    y = O:Check(page, "Show them over the target's nameplate",
        function() return db().comboOnPlate ~= false end,
        function(v) db().comboOnPlate = v; Combo:Attach() end, y)
    y = O:Note(page, "Needs enemy nameplates switched on in the game's own settings, since the pips ride the target's plate. The game's own class resource only ever sits under your own nameplate.", y)
    return y
end

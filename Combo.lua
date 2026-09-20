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
local PIP_W, PIP_H, PIP_GAP = 18, 9, 4

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
    row:SetHeight(PIP_H)
    row:Hide()
    -- No background on the row. A filled strip over a nameplate reads as
    -- one more bar; separate outlined pips read as pips.
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
        local empty = Chrome:Texture(bar, "BACKGROUND", C.void)
        empty:SetAllPoints()
        -- Build the fill as a plain colour rather than naming a texture
        -- file. An art path that resolves to nothing leaves the pip
        -- looking permanently empty with nothing to show for it.
        local fill = Chrome:Texture(bar, "ARTWORK", C.fel)
        bar:SetStatusBarTexture(fill)
        Chrome:AddBorder(bar)
        row.pips[i] = bar
    end
    for i = 1, #row.pips do
        local bar = row.pips[i]
        if i <= n then
            -- One point of range each: pip i fills as the count crosses it.
            bar:SetMinMaxValues(i - 1, i)
            bar:SetSize(PIP_W, PIP_H)
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", row, "LEFT", (i - 1) * (PIP_W + PIP_GAP), 0)
            bar:Show()
        else
            bar:Hide()
        end
    end
    row.count = n
    row:SetWidth(n * PIP_W + math.max(0, n - 1) * PIP_GAP)
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
    local health = (uf and (uf.HealthBarsContainer or uf.healthBar or uf.HealthBar)) or uf or plate
    row:SetParent(plate)
    row:SetFrameStrata("HIGH")
    row:ClearAllPoints()
    -- Under the health bar by default. Straight above it is where the
    -- name lives, which is what the first version covered up.
    --
    -- The one thing under there to share with is the cast bar, whose
    -- container anchors to the bottom of the unit frame. Anyone who
    -- minds can move the pips above the name instead, anchored to the
    -- name itself since the gap beneath it is a client constant we would
    -- otherwise be guessing at.
    local placed = false
    if db().comboAbove and uf and uf.name then
        -- The name is a font string. An unprotected frame may anchor to a
        -- region, but this client refuses it for protected ones, so keep
        -- a frame fallback rather than trust that we are never protected.
        placed = pcall(row.SetPoint, row, "BOTTOM", uf.name, "TOP", 0, 2)
        row.anchoredToName = placed
    end
    if not placed then
        row.anchoredToName = false
        row:SetPoint("TOP", health, "BOTTOM", 0, -3)
    end
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

-- /wpt combo. Whether a pip is empty because there are no points or
-- because the client will not say is not something you can see.
function Combo:Report(print_)
    local S = rawget(_G, "C_Secrets")
    local function ask(fn, ...)
        if not (S and S[fn]) then return "no such predicate" end
        local ok, v = pcall(S[fn], ...)
        return ok and tostring(v) or "errored"
    end
    print_(("power secret: %s   max secret: %s")
        :format(ask("ShouldUnitPowerBeSecret", "player", powerType()),
                ask("ShouldUnitPowerMaxBeSecret", "player", powerType())))

    local secret = rawget(_G, "issecretvalue")
    local function describe(label, getter)
        local ok, v = pcall(getter)
        if not ok then return print_(label .. ": call failed") end
        local isSecret = secret and secret(v)
        if isSecret then return print_(label .. ": secret, type " .. type(v)) end
        return print_(("%s: %s (type %s)"):format(label, tostring(v), type(v)))
    end
    describe("GetComboPoints", function() return GetComboPoints and GetComboPoints("player", "target") end)
    describe("UnitPower", function() return UnitPower("player", powerType()) end)
    describe("UnitPowerMax", function() return UnitPowerMax("player", powerType()) end)

    local row = self.row
    print_(("row: %s, %d pips, parent %s")
        :format(row and (row:IsShown() and "shown" or "hidden") or "not built",
                row and row.count or 0,
                row and row:GetParent() and (row:GetParent():GetName() or "unnamed plate") or "none"))
    local NP = rawget(_G, "C_NamePlate")
    local plate = NP and NP.GetNamePlateForUnit and NP.GetNamePlateForUnit("target")
    print_("target has a nameplate: " .. tostring(plate ~= nil))
end

function Combo:OptionRow(page, y)
    local O = Core.Options
    y = O:Heading(page, "Combo points", y)
    y = O:Check(page, "Show them over the target's nameplate",
        function() return db().comboOnPlate ~= false end,
        function(v) db().comboOnPlate = v; Combo:Attach() end, y)
    y = O:Check(page, "Put them above the name instead",
        function() return db().comboAbove == true end,
        function(v) db().comboAbove = v; Combo:Attach() end, y)
    y = O:Note(page, "Needs enemy nameplates switched on in the game's own settings, since the pips ride the target's plate. They sit under the health bar, sharing that space with the target's cast bar; above the name is clear of everything if you would rather. The game's own class resource only ever appears under your own nameplate, never the target's.", y)
    return y
end

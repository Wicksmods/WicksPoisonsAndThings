-- Wick's Poisons and Things
-- Swap.lua: the dagger in your main hand while you are stealthed.
--
-- A rogue fighting with a slow main hand still wants a dagger there to
-- open with, since Ambush and Backstab will not come out of anything
-- else, and wants the slow one back by the second Sinister Strike.
--
-- None of this can be automatic. Equipping is a protected action, so an
-- addon that watched for the cast and moved the weapons itself would be
-- blocked exactly when it mattered, which is in combat. What an addon
-- can do is keep the two macros right: a secure button whose macrotext
-- is rewritten out of combat, the same thing the coating keys do.
--
-- Two decisions worth keeping:
--
-- Weapons are addressed by item id rather than by name, the way the
-- coating macro is, so two swords called the same thing cannot pick the
-- wrong one.
--
-- Each macro names where both weapons should end up rather than
-- describing a move. Pressing one twice does nothing the second time,
-- and neither can get out of step with what you are actually wearing.

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local Core = WickCore
local D = Core.Dialect

local Swap = {}
ns.swap = Swap

local MAIN, OFF = 16, 17
local WEAPON_CLASS, DAGGER_SUBCLASS = 2, 15

-- Classic's ids. Forever retunes plenty, so the name is asked for
-- rather than assumed and the literal is only the last resort.
local STEALTH_ID, STRIKE_ID = 1784, 1752
local STEALTH_NAME, STRIKE_NAME = "Stealth", "Sinister Strike"

local function db()
    return ns.A and ns.A.db and ns.A.db.profile or {}
end

local function spellName(id, fallback)
    local ok, n = pcall(D.GetSpellName, id)
    if ok and type(n) == "string" and n ~= "" then return n end
    return fallback
end

function Swap:StrikeSpell()
    -- Not every rogue swaps back on Sinister Strike. /wpt swap strike
    -- <name> puts something else on the key.
    local override = db().swapStrike
    if type(override) == "string" and override ~= "" then return override end
    return spellName(STRIKE_ID, STRIKE_NAME)
end

function Swap:StealthSpell()
    return spellName(STEALTH_ID, STEALTH_NAME)
end

-- A macro cannot ask about a cooldown: there is no [cooldown]
-- conditional. So it is asked here, and while Stealth is down the lines
-- that would put the dagger up are left out of the macro entirely.
-- Otherwise the weapons swap and the cast goes nowhere, leaving you
-- holding a dagger you cannot open with.
--
-- isActive is the part of a cooldown this client still answers for when
-- the times come back secret. Anything it will not answer at all counts
-- as ready, since refusing to work on a missing reading would be worse
-- than the bug.
function Swap:StealthReady()
    local ok, cd = pcall(D.GetSpellCooldown, STEALTH_ID)
    if not ok or type(cd) ~= "table" or cd.active == nil then return true end
    return cd.active ~= true
end

-- ============================================================
-- What is in your hands
-- ============================================================

local function handAt(slot)
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if not id then return nil end
    local info = D.GetItemInfoInstant(id)
    return {
        id = id,
        -- Subclass rather than speed: the client will describe an item
        -- it has never sent us, but a weapon's speed lives in its
        -- tooltip and this client does not hand that over. The
        -- non-dagger is the slow one by the nature of the setup.
        dagger = info ~= nil and info.classID == WEAPON_CLASS
                 and info.subclassID == DAGGER_SUBCLASS,
    }
end

-- The pair only means something when exactly one hand holds a dagger.
-- Two daggers is already the stealth setup, and none means there is
-- nothing to open with.
function Swap:Pair()
    local m, o = handAt(MAIN), handAt(OFF)
    if not (m and o) then return nil, "you need a weapon in each hand" end
    if m.dagger and o.dagger then return nil, "both hands hold a dagger, nothing to swap" end
    if not (m.dagger or o.dagger) then return nil, "neither hand holds a dagger" end
    if m.dagger then
        return { dagger = m.id, other = o.id, daggerInMain = true }
    end
    return { dagger = o.id, other = m.id, daggerInMain = false }
end

-- Both hands are named on every branch. If the client swaps two
-- equipped weapons straight over, the second line is a no-op; if it
-- puts the displaced one in a bag instead, the second line picks it
-- back up. Either way the hands end up as named.
local function equip(cond, first, second)
    return ("/equipslot %s %d item:%d"):format(cond, MAIN, first),
           ("/equipslot %s %d item:%d"):format(cond, OFF, second)
end

-- The stealth key is a toggle for the spell, so it is a toggle for the
-- weapons: entering, the dagger comes up; leaving, the slow one goes
-- back. Without the second half, dropping stealth put the dagger in
-- your main hand on the way out.
--
-- Nothing moves while you are in combat, because Stealth will not cast
-- there and a swap you did not ask for leaves you fighting with the
-- wrong weapons.
--
-- The strike key leaves your hands alone while you are stealthed. A
-- press from stealth used to strip the dagger you were about to open
-- with; now it strikes, and the swap comes on the next press, once the
-- opener has broken stealth.
function Swap:Text(which, pair)
    if not pair then return "" end
    local lines = {}
    if which == "stealth" then
        -- Going in only while there is a stealth to go into. Coming
        -- back out is not something a cooldown should be able to stop,
        -- so those two stay whatever it says.
        if self.stealthReady ~= false then
            local a, b = equip("[nostealth,nocombat]", pair.dagger, pair.other)
            table.insert(lines, a)
            table.insert(lines, b)
        end
        local c, d = equip("[stealth]", pair.other, pair.dagger)
        table.insert(lines, c)
        table.insert(lines, d)
        table.insert(lines, "/cast " .. self:StealthSpell())
    else
        local a, b = equip("[nostealth]", pair.other, pair.dagger)
        lines = { a, b, "/cast " .. self:StrikeSpell() }
    end
    return table.concat(lines, "\n")
end

-- What the strip draws: the icon of the weapon each key would put in
-- your main hand, and which of the two you are already holding there.
function Swap:Faces()
    local pair = self.pair
    if not pair then return nil end
    local function icon(id)
        local info = D.GetItemInfoInstant(id)
        return info and info.icon or nil
    end
    return {
        stealth = { id = pair.dagger, icon = icon(pair.dagger), live = pair.daggerInMain },
        strike  = { id = pair.other,  icon = icon(pair.other),  live = not pair.daggerInMain },
    }
end

function Swap:Shown()
    return ns.isRogue and db().swap ~= false
end

-- ============================================================
-- The keys
-- ============================================================

local buttons = { stealth = {}, strike = {} }
local pending = false

function Swap:RegisterButton(which, b)
    local list = buttons[which]
    if not list then return end
    list[#list + 1] = b
    b:SetAttribute("type", "macro")
    self:Update()
end

function Swap:Update()
    -- A secure attribute cannot be written in combat, which is the
    -- whole reason this is a key you press rather than something that
    -- happens to you.
    if InCombatLockdown() then pending = true return end
    pending = false
    local pair, why = self:Pair()
    self.pair, self.why = pair, why
    self.stealthReady = self:StealthReady()
    self.macro = {}
    local on = db().swap ~= false
    for which, list in pairs(buttons) do
        local text = on and self:Text(which, pair) or ""
        self.macro[which] = text
        for _, b in ipairs(list) do b:SetAttribute("macrotext", text) end
    end
    if ns.UI and ns.UI.RefreshSwap then ns.UI:RefreshSwap() end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end

function Swap:Init()
    if not ns.isRogue or self.inited then return end
    self.inited = true
    for which, name in pairs({ stealth = "WicksPoisonsStealthButton",
                               strike  = "WicksPoisonsStrikeButton" }) do
        local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        b:SetSize(1, 1)
        b:SetPoint("CENTER")
        b:SetAlpha(0)
        b:EnableMouse(false)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:Show()
        self:RegisterButton(which, b)
    end

    ns.RegisterEvents({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD",
                        "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_COOLDOWN" })
    ns:On("PLAYER_EQUIPMENT_CHANGED", function() Swap:Update() end)
    ns:On("PLAYER_ENTERING_WORLD", function() Swap:Update() end)
    ns:On("PLAYER_REGEN_ENABLED", function() if pending then Swap:Update() end end)
    -- This one fires constantly, so it only does the work when the
    -- answer has actually turned over.
    ns:On("SPELL_UPDATE_COOLDOWN", function()
        if Swap:StealthReady() ~= Swap.stealthReady then Swap:Update() end
    end)
    self:Update()
end

-- ============================================================
-- /wpt swap
-- ============================================================

function Swap:Command(rest, print_)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = rest:lower()

    if lower == "on" or lower == "off" then
        db().swap = (lower == "on")
        self:Update()
        return print_("weapon swap keys " .. (db().swap and "on" or "off") .. ".")
    end

    local spell = rest:match("^[Ss][Tt][Rr][Ii][Kk][Ee]%s+(.+)$")
    if spell then
        db().swapStrike = spell
        self:Update()
        return print_("swapping back on " .. spell .. ".")
    end
    if lower == "strike" then
        db().swapStrike = nil
        self:Update()
        return print_("swapping back on " .. self:StrikeSpell() .. ", the default.")
    end

    return self:Report(print_)
end

function Swap:Report(print_)
    if db().swap == false then
        print_("weapon swap keys are off. /wpt swap on switches them back.")
    end
    local pair, why = self.pair, self.why
    if not pair then
        print_("no swap set up: " .. tostring(why or "nothing read yet"))
    else
        local name = function(id)
            return D.GetItemNameByID(id) or ("item " .. tostring(id))
        end
        print_(("dagger: %s   other: %s   (dagger is in your %s hand now)")
            :format(name(pair.dagger), name(pair.other),
                    pair.daggerInMain and "main" or "off"))
    end
    if self.stealthReady == false then
        print_("stealth is on cooldown, so the stealth key will not move your weapons until it is back.")
    end
    for _, which in ipairs({ "stealth", "strike" }) do
        local text = self.macro and self.macro[which]
        if text and text ~= "" then
            print_(which .. " key: " .. text:gsub("\n", " | "))
        else
            print_(which .. " key: empty")
        end
    end
    print_("bind them under Key Bindings, Wick's Poisons and Things.")
end

function Swap:OptionRow(page, y)
    local O = Core.Options
    y = O:Heading(page, "Weapon swap", y)
    y = O:Check(page, "Keep the swap keys loaded",
        function() return db().swap ~= false end,
        function(v) db().swap = v; Swap:Update() end, y)
    y = O:Note(page, ("Two keys for a slow main hand and a dagger off hand. One puts the dagger in your main hand and stealths, the other puts the slow weapon back and strikes. They follow whatever you are wearing, so a new weapon needs nothing done to it. Swapping in combat costs you a swing, and your coatings travel with the blades. Bind them under Key Bindings. Swapping back on %s; change that with /wpt swap strike <spell>.")
        :format(Swap:StrikeSpell()), y)
    return y
end

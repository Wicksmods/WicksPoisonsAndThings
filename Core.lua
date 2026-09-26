-- Wick's Poisons and Things
-- Core.lua: WickCore addon object, saved variables, event dispatch, slash command.
--
-- The rogue kit for World of Warcraft: Forever. A rogue's setup is two
-- coated blades and the right talents. Both are readable out of combat
-- and neither is a combat tracker, so the kit sits inside Forever's addon
-- rules. Through WickCore it adds the talent layer, the pre-pull
-- checklist and racials.

local ADDON, ns = ...

local Core = WickCore
if not Core then
    -- WickCore is missing or switched off.
    --
    -- The TOC asks for it with OptionalDeps rather than Dependencies on
    -- purpose. A hard dependency makes the client refuse to load this addon
    -- at all, so nothing of ours runs and the player is told nothing beyond
    -- a greyed line in the AddOns list. Loading anyway lets us say what is
    -- wrong and where to get it.
    --
    -- One line for the lot of them, not one per addon: with the whole suite
    -- installed and WickCore switched off, a line each would be a wall.
    local need = _G.WicksNeedCore
    if not need then
        need = {}
        _G.WicksNeedCore = need
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function()
            table.sort(need)
            print(("|cff4FC778Wick's Mods|r: %s %s WickCore, which is not installed or not switched on. It is in the same download as the rest of the suite: |cffD4C8A1wicksmods.com|r")
                :format(table.concat(need, ", "), #need == 1 and "needs" or "need"))
        end)
    end
    need[#need + 1] = "Wick's Poisons and Things"
    return
end
local D, R = Core.Dialect, Core.Restrict

ns.version = "0.9.0"

local PROFILE_DEFAULTS = {
    warnMinutes = 5,      -- a blade under this many minutes reads as low
    pinned      = {},     -- hand -> itemID the key should always apply
    showStrip   = true,
    comboOnPlate = true,  -- pips over the target's nameplate
    comboEnergy  = true,  -- and an energy bar under them
    stripLocked = true,
    strip       = {},
    window      = {},
    kitWindow   = {},
}

local A = Core:NewAddon("WicksPoisonsAndThings", {
    title    = "Wick's Poisons and Things",
    version  = ns.version,
    savedVar = "WicksPoisonsSaved",
    defaults = { profile = PROFILE_DEFAULTS, global = {} },
})
ns.A = A

-- ============================================================
-- Event dispatcher
-- ============================================================
local events = {}
function ns:On(event, fn)
    events[event] = events[event] or {}
    table.insert(events[event], fn)
end

local frame = CreateFrame("Frame", "WicksPoisonsEvents")
ns.eventFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
    if events[event] then
        for _, fn in ipairs(events[event]) do
            local ok, err = pcall(fn, event, ...)
            if not ok then A:Print(("error in %s: %s"):format(event, tostring(err))) end
        end
    end
end)
function ns.RegisterEvents(list)
    for _, ev in ipairs(list) do pcall(frame.RegisterEvent, frame, ev) end
end

local _, playerClass = UnitClass("player")
ns.isRogue = playerClass == "ROGUE"

ns.SPELL = {
    STEALTH   = 1784,
    PICK_LOCK = 1804,
    SPRINT    = 2983,
    EVASION   = 5277,
}

-- ============================================================
-- Lifecycle
-- ============================================================
function A:OnInitialize()
    ns.db = self.db
    self.db:On("OnProfileChanged", function()
        if ns.UI and ns.UI.ApplyStripVisibility then ns.UI:ApplyStripVisibility() end
        if ns.Poisons and ns.Poisons.UpdateMacros then ns.Poisons:UpdateMacros() end
    end)

    Core.Cooldowns:New(self, { key = "cooldownBar" })

    Core.Kit:New(self, {
        racials = true,
        checklist = {
            { label = "Main hand coated", weaponEnchant = "main" },
            { label = "Off hand coated",  weaponEnchant = "off", check = function()
                -- Only a real second weapon needs coating.
                local s = ns.Poisons:Hand("off")
                if not s.hasWeapon then return nil end
                return s.coated == true
            end },
            { label = "Poisons in bags", check = function()
                local list = ns.Poisons:Available()
                return #list > 0
            end },
            { label = "Stealth", cast = "Stealth", known = ns.SPELL.STEALTH },
        },
    })
end

function A:OnEnable()
    if not ns.isRogue then
        self:Print("loaded (non-rogue: viewer mode).")
    else
        self:Print("loaded. /wpt for the poison panel, /wpt kit for talents and checklist.")
    end
    if ns.Poisons and ns.Poisons.Init then ns.Poisons:Init() end
    if ns.UI and ns.UI.Init then ns.UI:Init() end

    self:RegisterLauncher({
        onClick = function(_, button)
            if button == "RightButton" then self.kit:Toggle()
            else ns.UI:Toggle() end
        end,
        tooltip = function(tt)
            tt:AddLine(Core.Chrome:TitleMarkup("Wick's Poisons and Things"))
            tt:AddLine("Left-click: poisons   Right-click: talents and checklist", 0.5, 0.5, 0.5)
        end,
    })

    if self.cooldowns then self.cooldowns:Init() end
    if ns.combo then ns.combo:Init() end

    self:RegisterOptions(function(page, addon)
        local O = Core.Options
        local db = addon.db.profile
        local y = O:Heading(page, "Strip", 0)
        y = O:Check(page, "Show the compact strip", function() return db.showStrip ~= false end,
            function(v) db.showStrip = v; ns.UI:ApplyStripVisibility() end, y)
        y = O:Check(page, "Lock the strip", function() return db.stripLocked ~= false end,
            function(v) db.stripLocked = v end, y)
        y = O:Note(page, "One row: each blade's coating and how long it has left. Click a blade to recoat, right-click for the full panel.", y)
        y = O:Heading(page, "Coatings", y - 6)
        y = O:Note(page, ("Warn under %d minutes. Change it with /wpt warn <minutes>. Pin a poison per hand with /wpt pin main <item link>."):format(db.warnMinutes or 5), y)
        y = O:Button(page, "Open panel", function() ns.UI:Toggle() end, y, 100)
        y = O:Button(page, "Open kit", function() addon.kit:Toggle() end, y, 100)
        if ns.combo then y = ns.combo:OptionRow(page, y - 6) end
        if addon.cooldowns then y = addon.cooldowns:OptionRow(page, y - 6) end
        y = O:ProfileSection(page, addon, y - 8)
    end)
end

-- Keybinding entry points
BINDING_HEADER_WICKSPOISONS = "Wick's Poisons and Things"
_G["BINDING_NAME_CLICK WicksPoisonsMainButton:LeftButton"] = "Coat main hand"
_G["BINDING_NAME_CLICK WicksPoisonsOffButton:LeftButton"] = "Coat off hand"
BINDING_NAME_WICKSPOISONS_TOGGLE = "Toggle poison panel"
function WicksPoisonsAndThings_Toggle() if ns.UI then ns.UI:Toggle() end end

-- ============================================================
-- Slash command
-- ============================================================
A:RegisterSlash(function(_, msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = msg:lower()
    local db = A.db.profile
    if lower == "" or lower == "show" or lower == "toggle" then ns.UI:Toggle() return end
    if lower == "kit" or lower == "talents" or lower == "checklist" then A.kit:Toggle() return end
    if lower == "cd" or lower:match("^cd%s") then return A.cooldowns:Command(msg:match("^%a+%s*(.*)$")) end
    if lower == "combo" then
        if ns.combo then ns.combo:Report(function(line) A:Print(line) end)
        else A:Print("combo points are rogue only") end
        return
    end
    if lower == "options" or lower == "config" then A:OpenOptions() return end
    if lower == "strip" then
        db.showStrip = not (db.showStrip ~= false)
        ns.UI:ApplyStripVisibility()
        A:Print("strip " .. (db.showStrip and "shown" or "hidden") .. ".")
        return
    end
    if lower == "unlock" or lower == "move" then ns.UI:SetStripLocked(false) return end
    if lower == "lock" then ns.UI:SetStripLocked(true) return end
    if lower:match("^warn") then
        local n = tonumber(lower:match("^warn%s+(%d+)") or "")
        if not n then A:Print(("warning under %d minutes. Use /wpt warn <minutes>."):format(db.warnMinutes or 5)) return end
        db.warnMinutes = n
        A:Print(("warning set to %d minutes."):format(n))
        ns.UI:Refresh()
        return
    end
    if lower:match("^pin") then
        local hand, rest = msg:match("^%a+%s+(%a+)%s*(.*)$")
        hand = hand and hand:lower()
        if hand ~= "main" and hand ~= "off" then
            A:Print("which hand? /wpt pin main [item link], /wpt pin off clear")
            return
        end
        db.pinned = db.pinned or {}
        if rest == "" then
            local pick = ns.Poisons:ChoiceFor(hand)
            A:Print(("%s hand: %s%s"):format(hand, pick and pick.name or "nothing to apply",
                db.pinned[hand] and "  (pinned)" or ""))
            return
        end
        if rest:lower() == "clear" or rest:lower() == "off" then
            db.pinned[hand] = nil
            A:Print(hand .. " hand unpinned.")
        else
            local id = tonumber(rest) or tonumber(rest:match("item:(%d+)") or "")
            if not id then A:Print("give an item link or item ID.") return end
            db.pinned[hand] = id
            A:Print(("%s hand pinned to item %d."):format(hand, id))
        end
        ns.Poisons:UpdateMacros()
        return
    end
    if lower == "status" or lower == "debug" then
        local s = ns.Poisons:State()
        for _, hand in ipairs({ "main", "off" }) do
            local h = s[hand]
            A:Print(("%s: weapon %s  coated %s  minutes %s  charges %s"):format(
                hand, tostring(h.weapon or "none"), tostring(h.coated),
                h.msLeft and string.format("%.1f", h.msLeft / 60000) or "?", tostring(h.charges)))
        end
        A:Print(("carrying %d coating(s). main macro: %s"):format(#ns.Poisons:Available(),
            ((ns.Poisons.macro and ns.Poisons.macro.main) or ""):gsub("\n", " | ")))
        return
    end
    A:Print("commands: show | strip | lock | unlock | kit | options | warn <minutes> | pin <main|off> [link|clear] | status")
end, "/wpt", "/wpoisons")

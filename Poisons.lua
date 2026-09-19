-- Wick's Poisons and Things
-- Poisons.lua: what is on each blade, what is in the bags, and one key to
-- reapply.
--
-- Coating a weapon is the rogue's version of feeding a pet: a chore done
-- before the pull, out of combat, that the client is happy to tell us
-- about. The temporary enchantment on each hand reads through
-- C_PaperDollInfo, and applying is a secure macro that uses the poison
-- and then the weapon slot.

local ADDON, ns = ...
local Core = WickCore
local D, R = Core.Dialect, Core.Restrict

local Poisons = {}
ns.Poisons = Poisons

local MAINHAND = rawget(_G, "INVSLOT_MAINHAND") or 16
local OFFHAND  = rawget(_G, "INVSLOT_OFFHAND")  or 17
Poisons.SLOT = { main = MAINHAND, off = OFFHAND }

local tempInfo = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
local enchInfo = C_Item and C_Item.GetWeaponEnchantInfo

-- Consumables that coat a weapon: poisons, and on other clients also
-- stones and oils. The client's own subclass is the primary test.
local TEMP_ENHANCEMENT = Enum and Enum.ItemConsumableSubclass
    and Enum.ItemConsumableSubclass.ItemenhancementTemporary
local CONSUMABLE_CLASS = 0

local function plain(v)
    if v == nil or R:IsSecret(v) then return nil end
    return v
end

-- ============================================================
-- What is on the blades
-- ============================================================

-- hand is "main" or "off". Nil fields mean the client would not say.
function Poisons:Hand(hand)
    local slot = self.SLOT[hand]
    local s = { hand = hand, slot = slot }
    local weapon = GetInventoryItemID and GetInventoryItemID("player", slot)
    s.hasWeapon = weapon and true or false
    if weapon then
        local it = D.GetItemInfo(weapon)
        s.weapon = it and it.name
    end
    if tempInfo then
        local ok, info = pcall(tempInfo, slot)
        if ok and type(info) == "table" then
            s.coated = true
            s.msLeft = plain(info.remainingTimeMs)
            s.charges = plain(info.chargesRemaining)
            s.enchantID = plain(info.enchantID)
        elseif ok then
            s.coated = false
        end
    end
    if s.coated and enchInfo then
        local ok, info = pcall(enchInfo, slot)
        if ok and type(info) == "table" then
            local e = info.enchants and info.enchants[1] or info
            s.icon = e and e.enchantIconID
            if s.msLeft == nil then s.msLeft = plain(e and e.timeLeft) end
            if s.charges == nil then s.charges = plain(e and e.charges) end
        end
    end
    return s
end

function Poisons:State()
    return { main = self:Hand("main"), off = self:Hand("off") }
end

-- ============================================================
-- What is in the bags
-- ============================================================

local function isCoating(id, name)
    local t = D.GetItemInfoInstant(id)
    if t and TEMP_ENHANCEMENT and t.classID == CONSUMABLE_CLASS
       and t.subclassID == TEMP_ENHANCEMENT then
        return true
    end
    -- Without the subclass, fall back to the name. Every poison says so.
    return name and name:lower():find("poison") ~= nil
end

function Poisons:Available()
    local seen, list = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = D.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = D.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] then
                local it = D.GetItemInfo(id)
                local name = it and it.name
                if isCoating(id, name) then
                    seen[id] = true
                    list[#list + 1] = {
                        itemID = id, name = name or ("item " .. id),
                        icon = it and it.icon, itemLevel = it and it.itemLevel or 0,
                        count = D.GetItemCount(id, false) or (info.stackCount or 1),
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
        return a.itemID < b.itemID
    end)
    return list
end

-- The coating a hand's key will apply: the pinned one while it is carried,
-- otherwise the highest the player has.
function Poisons:ChoiceFor(hand)
    local list = self:Available()
    if #list == 0 then return nil end
    local db = ns.db and ns.db.profile
    local pinned = db and db.pinned and db.pinned[hand]
    if pinned then
        for _, p in ipairs(list) do if p.itemID == pinned then p.pinned = true; return p end end
    end
    return list[1]
end

-- ============================================================
-- Coating keys
-- ============================================================

local buttons = { main = {}, off = {} }
local pending = false

function Poisons:RegisterButton(hand, b)
    local list = buttons[hand]
    if not list then return end
    list[#list + 1] = b
    b:SetAttribute("type", "macro")
    self:UpdateMacros()
end

function Poisons:UpdateMacros()
    if InCombatLockdown() then pending = true return end
    pending = false
    self.choice = self.choice or {}
    for hand, list in pairs(buttons) do
        local pick = self:ChoiceFor(hand)
        self.choice[hand] = pick
        -- Use the coating, then the weapon slot it goes on. Stopping the
        -- cast first keeps a half-finished application from eating it.
        local text = pick and ("/stopcasting\n/use item:%d\n/use %d"):format(pick.itemID, self.SLOT[hand]) or ""
        self.macro = self.macro or {}
        self.macro[hand] = text
        for _, b in ipairs(list) do b:SetAttribute("macrotext", text) end
    end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end

function Poisons:Init()
    if self.inited then return end
    self.inited = true
    for hand, name in pairs({ main = "WicksPoisonsMainButton", off = "WicksPoisonsOffButton" }) do
        local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        b:SetSize(1, 1)
        b:SetPoint("CENTER")
        b:SetAlpha(0)
        b:EnableMouse(false)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:Show()
        self:RegisterButton(hand, b)
    end

    ns.RegisterEvents({ "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" })
    local function refresh() if ns.UI then ns.UI:Refresh() end end
    ns:On("BAG_UPDATE_DELAYED", function() Poisons:UpdateMacros() end)
    ns:On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then refresh() end end)
    ns:On("PLAYER_EQUIPMENT_CHANGED", function() Poisons:UpdateMacros() end)
    ns:On("PLAYER_ENTERING_WORLD", function() Poisons:UpdateMacros() end)
    ns:On("PLAYER_REGEN_ENABLED", function() if pending then Poisons:UpdateMacros() end refresh() end)
    ns:On("WEAPON_ENCHANT_CHANGED", refresh)
    ns:On("WEAPON_SLOT_CHANGED", refresh)
    self:UpdateMacros()
end

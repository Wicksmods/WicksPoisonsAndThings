-- Wick's Poisons and Things
-- UI.lua: the compact strip and the details panel.
--
-- The strip is two blades side by side, each showing its coating and how
-- long it has left. Clicking a blade recoats it, which is the same secure
-- button the keybind uses. Everything else lives in tooltips and in the
-- panel a right-click opens.

local ADDON, ns = ...
local Core = WickCore
local Chrome, R = Core.Chrome, Core.Restrict
local C = Chrome.Colors

local UI = {}
ns.UI = UI

local RED   = { 0.80, 0.30, 0.30, 1 }
local AMBER = { 0.85, 0.65, 0.25, 1 }
local BLANK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function tint(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
local function handName(hand) return hand == "main" and "Main hand" or "Off hand" end

local function minutesLeft(h)
    if not h.msLeft then return nil end
    return h.msLeft / 60000
end

local function clockText(h)
    local m = minutesLeft(h)
    if not m then return h.coated and "on" or "" end
    if m >= 60 then return ("%dh"):format(math.floor(m / 60)) end
    if m >= 1 then return ("%dm"):format(math.floor(m)) end
    return ("%ds"):format(math.max(0, math.floor(h.msLeft / 1000)))
end

local function handColor(h, warnMinutes)
    if not h.hasWeapon then return C.muted end
    if not h.coated then return RED end
    local m = minutesLeft(h)
    if m and m < warnMinutes then return AMBER end
    return C.fel
end

local function handLines(tt, h, pick, warnMinutes)
    tt:AddLine(handName(h.hand), 1, 1, 1)
    if not h.hasWeapon then
        tt:AddLine("Nothing equipped in this hand", 0.6, 0.6, 0.6)
        return
    end
    tt:AddLine(h.weapon or "Weapon", 0.83, 0.78, 0.63)
    if h.coated then
        local m = minutesLeft(h)
        local c = handColor(h, warnMinutes)
        tt:AddLine(m and ("Coated, %d minutes left"):format(math.floor(m)) or "Coated", c[1], c[2], c[3])
        if h.charges then tt:AddLine(("%d charges"):format(h.charges), 0.83, 0.78, 0.63) end
    else
        tt:AddLine("Not coated", RED[1], RED[2], RED[3])
    end
    tt:AddLine(" ")
    if pick then
        tt:AddLine(("Click to apply %s  x%d%s"):format(pick.name, pick.count or 0, pick.pinned and "  (pinned)" or ""),
            0.6, 0.6, 0.6, true)
    else
        tt:AddLine("No coating in your bags for this hand.", 0.6, 0.6, 0.6, true)
    end
end

-- ============================================================
-- Compact strip
-- ============================================================

local STRIP_H = 26
local HAND_W  = 92
local PAD     = 6

local function makeBlade(parent, hand, strip)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetSize(HAND_W, STRIP_H - 4)
    b:RegisterForClicks("AnyUp", "AnyDown")
    ns.Poisons:RegisterButton(hand, b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 3, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = Chrome:Text(b, 11)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
    b.text:SetPoint("RIGHT", -3, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.10)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        handLines(GameTooltip, ns.Poisons:Hand(hand), ns.Poisons.choice and ns.Poisons.choice[hand],
            ns.db and ns.db.profile.warnMinutes or 5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function UI:BuildStrip()
    if self.strip then return self.strip end
    local db = ns.db and ns.db.profile
    local f = CreateFrame("Frame", "WicksPoisonsStrip", UIParent)
    self.strip = f
    f:SetSize(PAD + HAND_W * 2 + 3 + PAD, STRIP_H)
    f:SetPoint("CENTER", 0, -250)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if db and not db.stripLocked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        if db then db.strip = db.strip or {}; Chrome:SavePosition(s, db.strip) end
    end)
    f:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then UI:Toggle() end end)
    if db and db.strip and db.strip.point then
        local w, h = f:GetWidth(), f:GetHeight()
        Chrome:RestorePosition(f, db.strip)
        f:SetSize(w, h)
    end
    f:Hide()

    local bg = Chrome:Texture(f, "BACKGROUND", C.voidBG); bg:SetAllPoints()
    Chrome:AddBorder(f)
    Chrome:AddBrackets(f)

    -- An anchor frame per side, because the blades are protected and can
    -- only anchor to frames.
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", PAD, -2); left:SetSize(HAND_W, STRIP_H - 4)
    f.mainBtn = makeBlade(f, "main", f)
    f.mainBtn:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)

    local mid = CreateFrame("Frame", nil, f)
    mid:SetPoint("LEFT", left, "RIGHT", 1, 0); mid:SetSize(1, STRIP_H - 6)
    local div = Chrome:Texture(mid, "ARTWORK", C.border); div:SetAllPoints()

    f.offBtn = makeBlade(f, "off", f)
    f.offBtn:SetPoint("LEFT", mid, "RIGHT", 1, 0)

    f:SetScript("OnShow", function() UI:RefreshStrip() end)
    R:OnChange(function() if f:IsShown() then UI:RefreshStrip() end end)
    -- Coatings tick down, so the clock needs its own beat.
    f.ticker = C_Timer and C_Timer.NewTicker and C_Timer.NewTicker(20, function()
        if f:IsShown() then UI:RefreshStrip() end
    end)
    return f
end

function UI:ApplyStripVisibility()
    local db = ns.db and ns.db.profile
    local want = ns.isRogue and db and db.showStrip ~= false
    if want then
        self:BuildStrip()
        self.strip:Show()
        self:RefreshStrip()
    elseif self.strip then
        self.strip:Hide()
    end
end

function UI:SetStripLocked(locked)
    local db = ns.db and ns.db.profile
    if db then db.stripLocked = locked and true or false end
    ns.A:Print(locked and "strip locked." or "strip unlocked: drag it into place, then /wpt lock.")
end

local function dressBlade(btn, h, pick, warn)
    if not btn or not btn.text then return end
    local c = handColor(h, warn)
    if h.coated and h.icon then
        btn.icon:SetTexture(h.icon)
        btn.icon:SetDesaturated(false)
        btn.icon:SetAlpha(1)
    elseif pick then
        btn.icon:SetTexture(pick.icon or BLANK)
        btn.icon:SetDesaturated(not h.coated)
        btn.icon:SetAlpha(h.coated and 1 or 0.45)
    else
        btn.icon:SetTexture(BLANK)
        btn.icon:SetDesaturated(true)
        btn.icon:SetAlpha(0.35)
    end
    if not h.hasWeapon then
        btn.text:SetText(handName(h.hand) == "Main hand" and "Main: empty" or "Off: empty")
    elseif h.coated then
        btn.text:SetText(("%s  %s"):format(h.hand == "main" and "Main" or "Off", clockText(h)))
    else
        btn.text:SetText(("%s  bare"):format(h.hand == "main" and "Main" or "Off"))
    end
    tint(btn.text, c)
end

function UI:RefreshStrip()
    local f = self.strip
    if not f or not f.mainBtn or not f:IsShown() then return end
    local warn = ns.db and ns.db.profile.warnMinutes or 5
    local choice = ns.Poisons.choice or {}
    dressBlade(f.mainBtn, ns.Poisons:Hand("main"), choice.main, warn)
    dressBlade(f.offBtn, ns.Poisons:Hand("off"), choice.off, warn)
end

-- ============================================================
-- Details panel
-- ============================================================

function UI:Build()
    if self.panel then return self.panel end
    local db = ns.db and ns.db.profile
    local p = Chrome:NewPanel("WicksPoisonsPanel", {
        title = "Wick's Poisons and Things", width = 340, height = 240,
        closable = true, strata = "MEDIUM", db = db and db.window,
    })
    self.panel = p
    local ct = p.content

    local y = 0
    local head = Chrome:Heading(ct, "Blades"); head:SetPoint("TOPLEFT", 0, y)
    y = y - 20
    p.rows = {}
    for _, hand in ipairs({ "main", "off" }) do
        local row = CreateFrame("Frame", nil, ct)
        row:SetPoint("TOPLEFT", 0, y); row:SetSize(300, 34)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.title = Chrome:Text(row, 12)
        row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.detail = Chrome:Text(row, 10, C.muted)
        row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
        p.rows[hand] = row
        y = y - 38
    end

    y = y - 4
    local shead = Chrome:Heading(ct, "In your bags"); shead:SetPoint("TOPLEFT", 0, y)
    y = y - 20
    p.stock = Chrome:Text(ct, 11, C.muted)
    p.stock:SetPoint("TOPLEFT", 0, y)
    p.stock:SetWidth(300)
    p.stock:SetJustifyH("LEFT")

    local kitBtn = Chrome:Button(ct, "Kit", 70, 20)
    kitBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    kitBtn:SetScript("OnClick", function() ns.A.kit:Toggle() end)
    local optBtn = Chrome:Button(ct, "Options", 70, 20)
    optBtn:SetPoint("RIGHT", kitBtn, "LEFT", -6, 0)
    optBtn:SetScript("OnClick", function() ns.A:OpenOptions() end)
    local stripBtn = Chrome:Button(ct, "Strip", 70, 20)
    stripBtn:SetPoint("RIGHT", optBtn, "LEFT", -6, 0)
    stripBtn:SetScript("OnClick", function()
        if db then db.showStrip = not (db.showStrip ~= false) end
        UI:ApplyStripVisibility()
    end)

    p:SetScript("OnShow", function() UI:Refresh() end)
    R:OnChange(function() if p:IsShown() then UI:Refresh() end end)
    return p
end

function UI:Init()
    self:ApplyStripVisibility()
end

function UI:Toggle()
    self:Build()
    self.panel:Toggle()
end

function UI:RefreshPanel()
    local p = self.panel
    if not p or not p.rows or not p:IsShown() then return end
    local warn = ns.db and ns.db.profile.warnMinutes or 5
    local choice = ns.Poisons.choice or {}
    for _, hand in ipairs({ "main", "off" }) do
        local h = ns.Poisons:Hand(hand)
        local row = p.rows[hand]
        local pick = choice[hand]
        if h.coated and h.icon then row.icon:SetTexture(h.icon)
        elseif pick then row.icon:SetTexture(pick.icon or BLANK)
        else row.icon:SetTexture(BLANK) end
        row.icon:SetDesaturated(not h.coated)
        row.title:SetText(("%s: %s"):format(handName(hand), h.hasWeapon and (h.weapon or "weapon") or "nothing equipped"))
        tint(row.title, handColor(h, warn))
        if not h.hasWeapon then
            row.detail:SetText("")
        elseif h.coated then
            local m = minutesLeft(h)
            row.detail:SetText(("Coated%s%s"):format(
                m and (", " .. math.floor(m) .. " minutes left") or "",
                h.charges and (", " .. h.charges .. " charges") or ""))
        else
            row.detail:SetText(pick and ("Bare. The key applies " .. pick.name) or "Bare, and nothing in your bags to apply")
        end
    end
    local list = ns.Poisons:Available()
    if #list == 0 then
        p.stock:SetText("No coatings carried.")
    else
        local parts = {}
        for i, it in ipairs(list) do
            if i > 6 then parts[#parts + 1] = ("and %d more"):format(#list - 6) break end
            parts[#parts + 1] = ("%s x%d"):format(it.name, it.count or 0)
        end
        p.stock:SetText(table.concat(parts, ", "))
    end
end

function UI:Refresh()
    self:RefreshPanel()
    self:RefreshStrip()
end

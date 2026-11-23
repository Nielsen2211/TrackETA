-- TrackETA: en lille bar med al din sporing. Klik paa et ikon for at skifte.
-- Samme stil som LevelETA, GoldETA og LayerETA.
--
-- Ikonerne er rigtige knapper i spillet (SecureActionButtonTemplate), saa et klik kaster sporingen
-- direkte, ogsaa i kamp. Den slags knapper maa ikke flyttes, vises eller skjules i kamp, saa aendringer
-- i layoutet venter, til kampen er slut. Hvilket spor der er aktivt, laeses fra minimappets sporing.
local ADDON = "TrackETA"
local PATH = "Interface\\AddOns\\TrackETA\\"
local TEX = PATH .. "Textures\\"
local F_SEMI = PATH .. "Fonts\\Inter-SemiBold.ttf"
local F_BOLD = PATH .. "Fonts\\Inter-Bold.ttf"
local DB

-- alle spor, i den raekkefoelge de vises. Kun dem, du kan, kommer paa baren.
local SPELLS = {
  1494,   -- Track Beasts
  19883,  -- Track Humanoids
  19884,  -- Track Undead
  19885,  -- Track Hidden
  19880,  -- Track Elementals
  19878,  -- Track Demons
  19882,  -- Track Giants
  19879,  -- Track Dragonkin
  5225,   -- Track Humanoids (druid, kat)
  5502,   -- Sense Undead (paladin)
  5500,   -- Sense Demons (warlock)
  2383,   -- Find Herbs
  2580,   -- Find Minerals
  2481,   -- Find Treasure (dwarf)
}

local LOC = {
  en = { title = "TrackETA", settings = "Settings", tracking = "Tracking", bar = "Bar", vertical = "Vertical bar", lock = "Lock position", large = "Large icons",
    showTitle = "Show handle", none = "You know no tracking yet.", hint = "Left-click: track\nRight-click: settings",
    grip = "Drag to move\nRight-click: settings", minimap = "Minimap button", language = "Language", langName = "Language: English",
    mmTip = "Left-click: show or hide the bar\nRight-click: settings\nDrag: move this button", done = "Done", combat = "Changes the bar after combat.", locked = "Bar locked", unlocked = "Bar unlocked",
    help = "/teta: settings  ·  /teta lock  ·  /teta hide  ·  /teta reset  ·  /teta da|en" },
  da = { title = "TrackETA", settings = "Indstillinger", tracking = "Sporing", bar = "Bar", vertical = "Lodret bar", lock = "Lås placering", large = "Store ikoner",
    showTitle = "Vis håndtag", none = "Du kan ingen sporing endnu.", hint = "Venstreklik: spor\nHøjreklik: indstillinger",
    grip = "Træk for at flytte\nHøjreklik: indstillinger", minimap = "Minimap-knap", language = "Sprog", langName = "Sprog: Dansk",
    mmTip = "Venstreklik: vis eller skjul baren\nHøjreklik: indstillinger\nTræk: flyt knappen", done = "Færdig", combat = "Ændrer baren efter kampen.", locked = "Baren er låst", unlocked = "Baren er låst op",
    help = "/teta: indstillinger  ·  /teta lock  ·  /teta hide  ·  /teta reset  ·  /teta da|en" },
}
local function T(k) return (LOC[(DB and DB.lang) or "en"] or LOC.en)[k] end

local defaults = { lang = "en", vertical = false, locked = false, large = false, hidden = false, grip = true, showMinimap = true, mmAngle = 220 }

-- Forever skjuler nogle vaerdier for addons ("secret values"): dem roerer vi ikke
local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end
local function combat() return InCombatLockdown and InCombatLockdown() end

-- ---------- stavelser ----------
local function spellName(id)
  local ok, n = pcall(function()
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
  end)
  if ok and not secret(n) and type(n) == "string" and n ~= "" then return n end
end

local function spellIcon(id)
  local ok, t = pcall(function()
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id)
  end)
  if ok and not secret(t) and t then return t end
end

local function known(id)
  local function try(fn, ...) if type(fn) ~= "function" then return false end local ok, v = pcall(fn, ...) return ok and v == true end
  -- erhvervs-stavelser (Find Herbs) staar ikke altid som "kendt", men IsPlayerSpell finder dem
  return try(C_SpellBook and C_SpellBook.IsSpellKnown, id) or try(IsSpellKnown, id) or try(IsPlayerSpell, id)
end

-- hvilke spor er aktive lige nu: navn og ikon, laest fra minimappets sporing
local function activeNow()
  local names, icons = {}, {}
  local M = C_Minimap
  if M and M.GetNumTrackingTypes and M.GetTrackingInfo then
    local ok, num = pcall(M.GetNumTrackingTypes)
    num = ok and not secret(num) and tonumber(num) or 0
    for i = 1, num do
      local ok2, a, tex, active = pcall(M.GetTrackingInfo, i)   -- Classic: navn, ikon, aktiv; nyere: en tabel
      if ok2 then
        local n, sid = a, nil
        if type(a) == "table" then n, tex, active, sid = a.name, a.texture, a.active, a.spellID end
        if active == true and not secret(n) then
          if type(n) == "string" then names[n] = true end
          if sid and not secret(sid) then names[sid] = true end
          if tex and not secret(tex) then icons[tex] = true end
        end
      end
    end
  end
  if GetTrackingTexture then
    local ok, tex = pcall(GetTrackingTexture)
    if ok and tex and not secret(tex) then icons[tex] = true end
  end
  return names, icons
end

-- ---------- baren ----------
local function fs(parent, font, size)
  local t = parent:CreateFontString(nil, "OVERLAY")
  t:SetFont(font, size, ""); t:SetShadowOffset(0, 0)
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

local function skin(frame)
  local function part(name)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(TEX .. name); t:SetTexCoord(0, 520 / 1024, 0, 40 / 64)
    return t
  end
  local top = part("PanelTop"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(20)
  local bot = part("PanelBottom"); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(20)
  local mid = part("PanelMid"); mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
end

-- navn og guldstreg oeverst, som i LevelETA
local function header(frame, titleText)
  local title = fs(frame, F_BOLD, 15)
  title:SetPoint("LEFT", frame, "TOPLEFT", 14, -20)
  if titleText then title:SetText(titleText) end
  local line = frame:CreateTexture(nil, "ARTWORK")
  line:SetSize(22, 2); line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
  line:SetColorTexture(1, 0.8, 0.35, 0.9)
  return title
end

-- lag: det vindue du klikker paa eller aabner, kommer foran de andre ETA vinduer.
-- Baren har sikre knapper, saa den loeftes kun uden for kamp.
local function lift(frame, secure)
  if frame.SetToplevel and not secure then frame:SetToplevel(true) end
  frame:SetFrameLevel(40)
  local function up(self) if not (secure and combat()) then self:Raise() end end
  frame:HookScript("OnShow", up)
  frame:HookScript("OnMouseDown", up)
end

local bar = CreateFrame("Frame", "TrackETAFrame", UIParent)
bar:SetSize(120, 46); bar:SetPoint("TOP", UIParent, "TOP", 0, -150)
bar:SetMovable(true); bar:EnableMouse(true); bar:SetClampedToScreen(true); bar:RegisterForDrag("LeftButton")
skin(bar)
lift(bar, true)

local openSettings   -- saettes laengere nede
local refresh, layout

local function savePos()
  local l, t = bar:GetLeft(), bar:GetTop()
  if l and t then bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t); DB.point = { l, t } end
end
-- baren flyttes i kanten og i haandtaget, ikke paa ikonerne (et klik der kaster sporing)
bar:SetScript("OnDragStart", function(self) if DB and not DB.locked and not combat() then self:StartMoving() end end)
bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
bar:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then openSettings() end end)
bar:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("TrackETA", 1, 0.82, 0.3)
  GameTooltip:AddLine(T("grip"), 0.6, 0.6, 0.6); GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- haandtaget: tre smaa prikker i venstre side
local grip = {}
for i = 1, 3 do
  local d = bar:CreateTexture(nil, "ARTWORK"); d:SetSize(4, 4); d:SetTexture(TEX .. "Dot"); d:SetVertexColor(1, 0.82, 0.3); d:SetAlpha(0.55)
  grip[i] = d
end

-- en knap pr spor. De laves alle med det samme (udenfor kamp), og vises kun, hvis du kan stavelsen.
local buttons = {}
for i, id in ipairs(SPELLS) do
  local b = CreateFrame("Button", "TrackETAButton" .. i, bar, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type1", "spell")
  -- hoejreklik aabner indstillingerne via en tom makro med vores kommando: det er sikkert i kamp
  b:SetAttribute("type2", "macro"); b:SetAttribute("macrotext2", "/teta config")
  b.id = id

  local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.icon = icon
  -- moerk kant om alle ikoner, guld kant om det aktive
  local function edge(r, g, bl, a, layer)
    local t = {}
    for k = 1, 4 do local e = b:CreateTexture(nil, layer); e:SetColorTexture(r, g, bl, a); t[k] = e end
    t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT"); t[1]:SetHeight(2)
    t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT"); t[2]:SetHeight(2)
    t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT"); t[3]:SetWidth(2)
    t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT"); t[4]:SetWidth(2)
    return t
  end
  b.dark = edge(0.04, 0.05, 0.07, 1, "BORDER")
  -- det aktive spor: en kort guldstreg under ikonet, som stregen under titlen
  local mark = b:CreateTexture(nil, "OVERLAY"); mark:SetHeight(2)
  mark:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 6, -2); mark:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -6, -2)
  mark:SetColorTexture(1, 0.8, 0.35, 0.9)
  b.mark = mark
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(icon); hl:SetColorTexture(1, 1, 1, 0.12)
  local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  cd:SetAllPoints(icon); if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
  b.cd = cd

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.id)
    if not ok then GameTooltip:AddLine(spellName(self.id) or "?", 1, 1, 1) end
    GameTooltip:AddLine(T("hint"), 0.6, 0.6, 0.6); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  buttons[i] = b
end

-- hvilke knapper skal med: dem du kan, og som ikke er slaaet fra
local function wanted()
  local list = {}
  for _, b in ipairs(buttons) do
    if known(b.id) and not (DB.hide and DB.hide[b.id]) then list[#list + 1] = b end
  end
  return list
end

local pending = false
layout = function()
  if not DB then return end
  if combat() then pending = true; return end
  pending = false
  local list = wanted()
  local size = DB.large and 36 or 30
  local gap, pad = 4, 8
  local gripW = DB.grip and 10 or 0
  for _, b in ipairs(buttons) do b:Hide(); b:ClearAllPoints() end
  for k = 1, 3 do grip[k]:SetShown(DB.grip and #list > 0) end
  if DB.hidden or #list == 0 then bar:Hide(); return end
  for i, b in ipairs(list) do
    local name = spellName(b.id)
    b:SetAttribute("spell1", name or b.id)
    b.icon:SetTexture(spellIcon(b.id) or 134400)
    b:SetSize(size, size)
    local off = (i - 1) * (size + gap)
    if DB.vertical then b:SetPoint("TOPLEFT", bar, "TOPLEFT", pad, -(pad + gripW + off))
    else b:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + gripW + off, -pad) end
    b:Show()
  end
  local long = pad * 2 + gripW + #list * size + (#list - 1) * gap
  local short = pad * 2 + size + 2
  if DB.vertical then
    bar:SetSize(short - 2, long)
    for k = 1, 3 do grip[k]:ClearAllPoints(); grip[k]:SetPoint("TOP", bar, "TOP", (k - 2) * 6, -pad - 2) end
  else
    bar:SetSize(long, short)
    for k = 1, 3 do grip[k]:ClearAllPoints(); grip[k]:SetPoint("LEFT", bar, "LEFT", pad + 1, (k - 2) * 6) end
  end
  bar:Show()
  refresh()
end

-- det der maa aendres i kamp: hvilket spor er aktivt, og nedkoelingen
refresh = function()
  if not DB then return end
  local names, icons = activeNow()
  for _, b in ipairs(buttons) do
    if b:IsShown() then
      local name, icon = spellName(b.id), spellIcon(b.id)
      local on = names[b.id] or (name and names[name]) or (icon and icons[icon]) or false
      b.mark:SetShown(on)
      if b.icon.SetDesaturated then b.icon:SetDesaturated(not on) end
      b.icon:SetAlpha(on and 1 or 0.72)
      -- nedkoeling (sporing har en kort global nedkoeling)
      local start, dur
      pcall(function()
        if C_Spell and C_Spell.GetSpellCooldown then
          local c = C_Spell.GetSpellCooldown(b.id)
          if type(c) == "table" then start, dur = c.startTime, c.duration end
        elseif GetSpellCooldown then
          start, dur = GetSpellCooldown(b.id)
        end
      end)
      if not secret(start) and not secret(dur) and type(start) == "number" and type(dur) == "number" and dur > 0 then
        b.cd:SetCooldown(start, dur)
      else
        b.cd:Clear()
      end
    end
  end
end

-- ---------- indstillinger (samme byggeklodser som LevelETA) ----------
local SW, SP = 260, 18
local S = CreateFrame("Frame", "TrackETASettings", UIParent)
S:SetSize(SW, 200); S:SetPoint("CENTER"); S:SetFrameStrata("HIGH"); S:Hide()
S:SetMovable(true); S:EnableMouse(true); S:SetClampedToScreen(true); S:RegisterForDrag("LeftButton")
S:SetScript("OnDragStart", S.StartMoving); S:SetScript("OnDragStop", S.StopMovingOrSizing)
skin(S)
lift(S)
tinsert(UISpecialFrames, "TrackETASettings")   -- Escape lukker den
local sTitle = header(S)
local close = CreateFrame("Button", nil, S); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -10, -10)
local cx = fs(close, F_BOLD, 16); cx:SetPoint("CENTER"); cx:SetText("×"); cx:SetTextColor(0.55, 0.58, 0.64)
close:SetScript("OnEnter", function() cx:SetTextColor(1, 1, 1) end)
close:SetScript("OnLeave", function() cx:SetTextColor(0.55, 0.58, 0.64) end)
close:SetScript("OnClick", function() S:Hide() end)
local note = fs(S, F_SEMI, 11); note:SetTextColor(1, 0.6, 0.35); note:SetJustifyH("LEFT")

local function pill(w)
  local b = CreateFrame("Button", nil, S); b:SetSize(w, 24)
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(TEX .. "Pill"); bg:SetTexCoord(0, 240 / 256, 0, 48 / 64)
  b.text = fs(b, F_SEMI, 12); b.text:SetPoint("CENTER"); b.text:SetTextColor(0.85, 0.87, 0.92)
  b:SetScript("OnEnter", function() b.text:SetTextColor(1, 0.82, 0.4) end)
  b:SetScript("OnLeave", function() b.text:SetTextColor(0.85, 0.87, 0.92) end)
  return b
end
local langBtn = pill(130); langBtn:SetPoint("BOTTOMLEFT", SP, 16)
local doneBtn = pill(SW - 2 * SP - 130 - 8); doneBtn:SetPoint("BOTTOMRIGHT", -SP, 16)
doneBtn:SetScript("OnClick", function() S:Hide() end)

local rowPool, heads = {}, {}
local function head(i)
  local h = heads[i]
  if not h then h = fs(S, F_BOLD, 11); h:SetTextColor(1, 0.82, 0.4); heads[i] = h end
  return h
end
-- en raekke: evt. et ikon, en tekst og en kontakt til hoejre. Klik paa hele raekken skifter.
local function toggleRow(i)
  local r = rowPool[i]
  if r then return r end
  r = CreateFrame("Button", nil, S); r:SetHeight(24)
  local off = r:CreateTexture(nil, "ARTWORK"); off:SetSize(32, 18); off:SetPoint("RIGHT"); off:SetTexture(TEX .. "ToggleOff"); off:SetTexCoord(0, 1, 0, 36 / 64)
  local on = r:CreateTexture(nil, "ARTWORK"); on:SetAllPoints(off); on:SetTexture(TEX .. "ToggleOn"); on:SetTexCoord(0, 1, 0, 36 / 64)
  local ic = r:CreateTexture(nil, "ARTWORK"); ic:SetSize(16, 16); ic:SetPoint("LEFT", 0, 0); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local tx = fs(r, F_SEMI, 12); tx:SetTextColor(0.85, 0.87, 0.92); tx:SetJustifyH("LEFT")
  tx:SetPoint("RIGHT", off, "LEFT", -8, 0)
  r.off, r.on, r.ic, r.tx = off, on, ic, tx
  r:SetScript("OnClick", function(self) if self.set then self.set(not self.get()); S.build() end end)
  rowPool[i] = r
  return r
end

function S.build()
  if not DB then return end
  local y, n, h = -44, 0, 0
  local function section(text)
    h = h + 1; local hd = head(h); hd:ClearAllPoints(); hd:SetPoint("TOPLEFT", SP, y); hd:SetText(text); hd:Show()
    y = y - 20
  end
  local function add(text, icon, get, set)
    n = n + 1; local r = toggleRow(n)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", SP, y); r:SetPoint("RIGHT", S, "RIGHT", -SP, 0)
    r.get, r.set = get, set
    local isOn = get() and true or false
    r.off:SetShown(set ~= nil and not isOn); r.on:SetShown(set ~= nil and isOn)
    r.tx:ClearAllPoints()
    if set then r.tx:SetPoint("RIGHT", r.off, "LEFT", -8, 0) else r.tx:SetPoint("RIGHT", r, "RIGHT", 0, 0) end
    if icon then
      r.ic:SetTexture(icon); r.ic:Show(); r.tx:SetPoint("LEFT", r.ic, "RIGHT", 8, 0)
    else
      r.ic:Hide(); r.tx:SetPoint("LEFT", r, "LEFT", 0, 0)
    end
    r.tx:SetText(text)
    r:Show()
    y = y - 24
  end

  section(T("tracking"))
  local any = false
  for _, id in ipairs(SPELLS) do
    if known(id) then
      any = true
      add(spellName(id) or tostring(id), spellIcon(id),
        function() return not (DB.hide and DB.hide[id]) end,
        function(v) DB.hide = DB.hide or {}; DB.hide[id] = (not v) or nil; layout() end)
    end
  end
  if not any then add(T("none"), nil, function() return false end, nil) end
  y = y - 8
  section(T("bar"))
  add(T("vertical"), nil, function() return DB.vertical end, function(v) DB.vertical = v; layout() end)
  add(T("large"), nil, function() return DB.large end, function(v) DB.large = v; layout() end)
  add(T("showTitle"), nil, function() return DB.grip end, function(v) DB.grip = v; layout() end)
  add(T("lock"), nil, function() return DB.locked end, function(v) DB.locked = v end)
  add(T("minimap"), nil, function() return DB.showMinimap end, function(v) DB.showMinimap = v; if TrackETAMinimapButton then TrackETAMinimapButton:SetShown(v) end end)

  for i = n + 1, #rowPool do rowPool[i]:Hide() end
  for i = h + 1, #heads do heads[i]:Hide() end
  local msg = pending and T("combat") or ""
  note:SetText(msg); note:ClearAllPoints()
  if msg ~= "" then
    note:SetPoint("TOPLEFT", SP, y - 6); note:SetPoint("RIGHT", S, "RIGHT", -SP, 0); note:Show(); y = y - 22
  else note:Hide() end
  sTitle:SetText(T("settings"))
  langBtn.text:SetText(T("langName"))
  doneBtn.text:SetText(T("done"))
  S:SetHeight(-y + 14 + 24 + 16)
end
S:SetScript("OnShow", function() S.build() end)
langBtn:SetScript("OnClick", function() DB.lang = (DB.lang == "da") and "en" or "da"; S.build() end)

openSettings = function()
  if S:IsShown() then S:Hide() else S:Show() end
end

-- ---------- minimap-knap (som i LevelETA) ----------
local mmb = CreateFrame("Button", "TrackETAMinimapButton", Minimap)
mmb:SetSize(31, 31); mmb:SetFrameStrata("MEDIUM"); mmb:SetFrameLevel(8)
mmb:RegisterForClicks("LeftButtonUp", "RightButtonUp"); mmb:RegisterForDrag("LeftButton")
mmb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
do
  local bg = mmb:CreateTexture(nil, "BACKGROUND"); bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = mmb:CreateTexture(nil, "ARTWORK"); icon:SetSize(21, 21); icon:SetPoint("TOPLEFT", 5, -5); icon:SetTexture(TEX .. "Logo")
  local border = mmb:CreateTexture(nil, "OVERLAY"); border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
end
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function placeButton()
  local a = math.rad(DB and DB.mmAngle or 220)
  local rad = (Minimap:GetWidth() / 2) + 5
  mmb:ClearAllPoints(); mmb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * rad, math.sin(a) * rad)
end
mmb:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local sc = Minimap:GetEffectiveScale()
    DB.mmAngle = math.deg(atan2(py / sc - my, px / sc - mx))
    placeButton()
  end)
end)
mmb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mmb:SetScript("OnClick", function(_, btn)
  if not DB then return end
  if btn == "RightButton" then openSettings(); return end
  if combat() then print("|cffffd24aTrackETA|r: " .. T("combat")); return end
  DB.hidden = not DB.hidden; layout()
end)
mmb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("TrackETA", 1, 0.82, 0.3)
  GameTooltip:AddLine(T("mmTip"), 0.6, 0.6, 0.6)
  GameTooltip:Show()
end)
mmb:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------- haendelser ----------
local E = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
  "MINIMAP_UPDATE_TRACKING", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED", "SKILL_LINES_CHANGED" }) do
  pcall(E.RegisterEvent, E, ev)
end
E:SetScript("OnEvent", function(_, ev, a1)
  if ev == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    TrackETADB = TrackETADB or {}
    DB = TrackETADB
    for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
    DB.hide = DB.hide or {}
    placeButton(); mmb:SetShown(DB.showMinimap)
    if type(DB.point) == "table" and DB.point[1] then
      bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.point[1], DB.point[2])
    end
  elseif ev == "PLAYER_ENTERING_WORLD" or ev == "SPELLS_CHANGED" or ev == "LEARNED_SPELL_IN_TAB" or ev == "SKILL_LINES_CHANGED" then
    layout()
    if S:IsShown() then S.build() end
  elseif ev == "PLAYER_REGEN_ENABLED" then
    if pending then layout() end
    if S:IsShown() then S.build() end
  elseif ev == "MINIMAP_UPDATE_TRACKING" or ev == "SPELL_UPDATE_COOLDOWN" then
    refresh()
  end
end)

-- ---------- kommandoer ----------
SLASH_TRACKETA1 = "/teta"
SLASH_TRACKETA2 = "/tracketa"
SlashCmdList.TRACKETA = function(msg)
  msg = string.lower(string.match(msg or "", "^%s*(.-)%s*$") or "")
  if not DB then return end
  if msg == "" or msg == "config" or msg == "settings" then openSettings()
  elseif msg == "lock" then DB.locked = not DB.locked; print("|cffffd24aTrackETA|r: " .. T(DB.locked and "locked" or "unlocked"))
  elseif msg == "hide" then DB.hidden = not DB.hidden; layout()
  elseif msg == "show" then DB.hidden = false; layout()
  elseif msg == "reset" then
    if combat() then print("|cffffd24aTrackETA|r: " .. T("combat")); return end
    DB.point = nil; bar:ClearAllPoints(); bar:SetPoint("TOP", UIParent, "TOP", 0, -150)
  elseif msg == "da" or msg == "en" then DB.lang = msg; if S:IsShown() then S.build() end
  else print("|cffffd24aTrackETA|r: " .. T("help")) end
end

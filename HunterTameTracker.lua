-- File: Interface/AddOns/HunterTameTracker/HunterTameTracker.lua
-- Addon: Hunter Tame Tracker (HTT)
-- Slash: /htt, /huntertame, /huntertametracker
--
-- .toc should include:
-- ## SavedVariables: HTT_DB
-- ## Version: 1.0.0

HTT_DB = HTT_DB or {}

------------------------------------------------------------
-- ADDON NAME + VERSION (Retail-safe: C_AddOns fallback)
------------------------------------------------------------
local ADDON_NAME = select(1, ...) or "HunterTameTracker"

local function GetAddonMetadata(addon, field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(addon, field)
  end
  if GetAddOnMetadata then
    return GetAddOnMetadata(addon, field)
  end
  return nil
end

local function GetAddonVersion()
  local v = GetAddonMetadata(ADDON_NAME, "Version")
  if v and v ~= "" then return v end
  v = GetAddonMetadata("HunterTameTracker", "Version")
  if v and v ~= "" then return v end
  return "dev"
end

local ADDON_VERSION = GetAddonVersion()

------------------------------------------------------------
-- SAVED VARS
------------------------------------------------------------
local function GetDB()
  HTT_DB = HTT_DB or {}
  HTT_DB.ui = HTT_DB.ui or {}
  return HTT_DB.ui
end

------------------------------------------------------------
-- WOWHEAD URL BUILDERS
------------------------------------------------------------
local function WowheadItemURL(itemID)
  if type(itemID) ~= "number" then return nil end
  return ("https://www.wowhead.com/item=%d"):format(itemID)
end

local function WowheadSpellURL(spellID)
  if type(spellID) ~= "number" then return nil end
  return ("https://www.wowhead.com/spell=%d"):format(spellID)
end

------------------------------------------------------------
-- UNLOCK CHECKS (quest OR spell)
------------------------------------------------------------
local function IsQuestDone(questID)
  if type(questID) ~= "number" then return false end
  if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
  return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
end

local function HasSpell(spellID)
  if type(spellID) ~= "number" then return false end
  if not IsPlayerSpell then return false end
  return IsPlayerSpell(spellID) and true or false
end

local function IsUnlocked(unlock)
  if type(unlock) ~= "table" then return false end

  if type(unlock.quests) == "table" then
    for _, q in ipairs(unlock.quests) do
      if IsQuestDone(q) then return true end
    end
  end

  if type(unlock.spells) == "table" then
    for _, s in ipairs(unlock.spells) do
      if HasSpell(s) then return true end
    end
  end

  return false
end

local function StatusText(ok)
  return ok and "|cff00ff00Unlocked|r" or "|cffff3b3bMissing|r"
end

local function StatusRGB(ok)
  if ok then return 0, 1, 0 end
  return 1, 0, 0
end

------------------------------------------------------------
-- SEARCH (normalized + alias-safe)
------------------------------------------------------------
local function SafeLower(s)
  if type(s) ~= "string" then return "" end
  return string.lower(s)
end

local function NormalizeSearchQuery(q)
  q = SafeLower(q or "")
  q = q:gsub("[%.%,%-%_%(%)]", " ")
  q = q:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return q
end

local function BuildQueryVariants(q)
  q = NormalizeSearchQuery(q)
  if q == "" then return { "" } end

  local variants = { q }

  local function add(v)
    v = NormalizeSearchQuery(v)
    if v == "" then return end
    for _, existing in ipairs(variants) do
      if existing == v then return end
    end
    table.insert(variants, v)
  end

  local function swap(from, to)
    if q:find(from, 1, true) then
      add((q:gsub(from, to)))
    end
  end

  swap("battle for azeroth", "bfa")
  swap("bfa", "battle for azeroth")

  swap("mists of pandaria", "mop")
  swap("mop", "mists of pandaria")

  swap("mists of panderia", "mop")
  swap("mop", "mists of panderia")

  if q == "mop" then
    add("mists of pandaria")
    add("mists of panderia")
  end
  if q == "bfa" then
    add("battle for azeroth")
  end

  return variants
end

local function MatchesAnyQuery(hay, queries)
  if not hay or hay == "" then return false end
  for _, q in ipairs(queries) do
    if q == "" or hay:find(q, 1, true) then return true end
  end
  return false
end

local function ExpansionAliases(expansion, expansionFull)
  local e = NormalizeSearchQuery(expansion or "")
  local f = NormalizeSearchQuery(expansionFull or "")

  local alias = {}
  if e == "mists of pandaria" or f == "mists of pandaria" then
    alias[#alias + 1] = "mop"
  end
  if e == "bfa" or f == "battle for azeroth" then
    alias[#alias + 1] = "bfa"
    alias[#alias + 1] = "battle for azeroth"
  end
  return table.concat(alias, " ")
end

------------------------------------------------------------
-- ICONS (safe; no '?')
------------------------------------------------------------
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local iconCache, pendingItemLoads = {}, {}

local function RequestItemLoad(itemID, refreshFn)
  if not itemID or pendingItemLoads[itemID] then return end
  if not Item or not Item.CreateFromItemID then return end

  pendingItemLoads[itemID] = true
  local it = Item:CreateFromItemID(itemID)
  it:ContinueOnItemLoad(function()
    pendingItemLoads[itemID] = nil
    iconCache[itemID] = nil
    if refreshFn then refreshFn() end
  end)
end

local function GetItemIconSafe(itemID, refreshFn)
  if not itemID then return nil end
  if iconCache[itemID] ~= nil then return iconCache[itemID] end

  local tex
  if C_Item and C_Item.GetItemIconByID then
    tex = C_Item.GetItemIconByID(itemID)
  elseif GetItemIcon then
    tex = GetItemIcon(itemID)
  end

  if not tex or tex == 0 then
    RequestItemLoad(itemID, refreshFn)
    iconCache[itemID] = nil
    return nil
  end

  iconCache[itemID] = tex
  return tex
end

local function GetSpellIconSafe(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellTexture then
    local tex = C_Spell.GetSpellTexture(spellID)
    if tex and tex ~= 0 then return tex end
  end
  if GetSpellTexture then
    local tex = GetSpellTexture(spellID)
    if tex and tex ~= 0 then return tex end
  end
  return nil
end

local function GetBestIcon(entry, refreshFn)
  if entry.iconOverride and entry.iconOverride ~= "" then
    return entry.iconOverride
  end

  local itemTex = GetItemIconSafe(entry.itemID, refreshFn)
  if itemTex then return itemTex end

  if entry.unlock and type(entry.unlock.spells) == "table" then
    for _, sid in ipairs(entry.unlock.spells) do
      local sTex = GetSpellIconSafe(sid)
      if sTex then return sTex end
    end
  end

  return FALLBACK_ICON
end

------------------------------------------------------------
-- SAFE COPY POPUP (no auto-copy -> avoids blocked action)
------------------------------------------------------------
local function EnsureCopyPopup()
  if HTT_CopyFrame then return end

  local f = CreateFrame("Frame", "HTT_CopyFrame", UIParent, "BackdropTemplate")
  f:SetSize(560, 140)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
  f:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("Copy (Ctrl+C)")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  eb:SetPoint("TOPLEFT", 16, -48)
  eb:SetPoint("TOPRIGHT", -16, -48)
  eb:SetHeight(24)
  eb:SetAutoFocus(true)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnEnterPressed", function() f:Hide() end)

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 2, -10)
  hint:SetText("Ctrl+C to copy. Enter/Esc to close.")

  f.editBox = eb
end

local function ShowCopyPopup(text)
  if not text or text == "" then return end
  EnsureCopyPopup()
  HTT_CopyFrame:Show()
  HTT_CopyFrame.editBox:SetText(text)
  HTT_CopyFrame.editBox:HighlightText()
  HTT_CopyFrame.editBox:SetFocus()
end

------------------------------------------------------------
-- TomTom detection (for showing Copy Waypoint button)
------------------------------------------------------------
local function HasTomTom()
  local tt = _G.TomTom
  return tt and type(tt.AddWaypoint) == "function"
end

------------------------------------------------------------
-- WAYPOINT FORMATTER (TomTom: NO ZONE in /way)
------------------------------------------------------------
local function FormatWaypoint(wp)
  if type(wp) ~= "table" then return nil end
  local x, y = tonumber(wp.x), tonumber(wp.y)
  if not x or not y then return nil end
  local label = wp.label or ""
  if label ~= "" then
    return ("/way %.1f %.1f %s"):format(x, y, label)
  end
  return ("/way %.1f %.1f"):format(x, y)
end

------------------------------------------------------------
-- DATA (11 entries)
------------------------------------------------------------
local LIST = {

  {
    keyName = "Direhorns",
    expansion = "Mists of Pandaria",
    tomeName = "Ancient Tome of Dinomancy",
    itemID = 94232,
    unlock = { spells = { 138430 } },
    guide =
      "Ancient Tome of Dinomancy (Direhorns)\n\n" ..
      "Source:\n" ..
      "- Isle of Giants drop\n\n" ..
      "Use:\n" ..
      "- Read the tome -> Direhorn taming unlocked.",
  },

  {
    keyName = "Mechanical",
    expansion = "Legion",
    tomeName = "Mecha-Bond Imprint Matrix",
    itemID = 134125,
    unlock = { spells = { 205154 } },
    waypoint = { x = 48.8, y = 13.6, label = "Xur'ios" },
    guide =
      "Mecha-Bond Imprint Matrix (Mechanical)\n\n" ..
      "Engineer:\n" ..
      "- Requires Legion Engineering\n" ..
      "- Recipe: Schematic: Mecha-Bond Imprint Matrix\n" ..
      "- Vendor: Xur'ios (Legion Dalaran)\n" ..
      "- Cost: 1 Curious Coin\n\n" ..
      "Waypoint (Legion Dalaran):\n" ..
      "/way 48.8 13.6 Xur'ios\n\n" ..
      "Fastest:\n" ..
      "- Buy from the Auction House\n\n" ..
      "Use:\n" ..
      "- Read the item -> Mechanical taming unlocked.",
  },

  {
    keyName = "Feathermanes",
    expansion = "Legion",
    tomeName = "Tome of the Hybrid Beast",
    itemID = 147580,
    unlock = { spells = { 242155 } },
    guide =
      "Tome of the Hybrid Beast (Feathermanes)\n\n" ..
      "Requirement:\n" ..
      "- A Glorious Campaign (Approx. 62 quests)\n" ..
      "- Breaching the Tomb (Approx. 18 quests)\n" ..
      "- Night of the Wilds (Hunter class mount questline)\n\n" ..
      "Source:\n" ..
      "- Sold by Pan the Kind Hand\n" ..
      "- Trueshot Lodge (Hunter Order Hall)\n\n" ..
      "Use:\n" ..
      "- Read the tome -> Feathermane taming unlocked.",
  },

  {
    keyName = "Blood Beasts",
    expansion = "BFA",
    expansionFull = "Battle for Azeroth",
    tomeName = "Blood-Soaked Tome of Dark Whispers",
    itemID = 166502,
    unlock = { quests = { 54753 } },
    guide =
      "Blood-Soaked Tome of Dark Whispers (Blood Beasts)\n\n" ..
      "Source:\n" ..
      "- Uldir (Zul) drop\n\n" ..
      "Use:\n" ..
      "- Read the tome -> Blood Beast taming unlocked.",
  },

  {
    keyName = "Gargon",
    expansion = "Shadowlands",
    tomeName = "Gargon Training Manual",
    itemID = 180705,
    unlock = { quests = { 61160 } },
    waypoint = { x = 61.89, y = 78.50, label = "Huntmaster Petrus" },
    guide =
      "Gargon Training Manual (Gargon)\n\n" ..
      "Source:\n" ..
      "- Drops from Huntmaster Petrus (Revendreth)\n\n" ..
      "Waypoint (Revendreth):\n" ..
      "/way 61.89 78.50 Huntmaster Petrus\n\n" ..
      "Use:\n" ..
      "- Read the manual -> Gargon taming unlocked.",
  },

  {
    keyName = "Cloud Serpents",
    expansion = "Mists of Pandaria",
    tomeName = "How to School Your Serpent",
    itemID = 183123,
    unlock = { quests = { 62254 } },
    waypoint = { x = 57.6, y = 44.8, label = "Elder Anli" },
    guide =
      "How to School Your Serpent (Cloud Serpents)\n\n" ..
      "Requirement:\n" ..
      "- Exalted with Order of the Cloud Serpent\n\n" ..
      "Fastest Reputation:\n" ..
      "- Timeless Isle: kill Crimsonscale Firestorms (flying)\n" ..
      "- Kill Huolon if up\n" ..
      "- Loot Quivering Firestorm Eggs\n" ..
      "- Turn eggs in to Elder Anli at The Arboretum\n\n" ..
      "Waypoint (The Jade Forest - Arboretum):\n" ..
      "/way 57.6 44.8 Elder Anli\n\n" ..
      "Use:\n" ..
      "- Buy the book and read it -> Cloud Serpent taming unlocked.",
  },

  {
    keyName = "Undead Beasts",
    expansion = "Shadowlands",
    tomeName = "Simple Tome of Bone-Binding",
    itemID = 183124,
    unlock = { quests = { 62255 } },
    waypoint = { x = 36.2, y = 50.1, label = "Lobber Jalrax" },
    guide =
      "Simple Tome of Bone-Binding (Undead Beasts)\n\n" ..
      "Source:\n" ..
      "- Maldraxxus rare and elite mobs\n" ..
      "- Plaguefall dungeon bosses\n\n" ..
      "Fastest Grind:\n" ..
      "- Spam Lobber Jalrax (fast respawn)\n\n" ..
      "Waypoint (Maldraxxus):\n" ..
      "/way 36.2 50.1 Lobber Jalrax\n\n" ..
      "Use:\n" ..
      "- Read the tome -> Undead beast taming unlocked.",
  },

  {
    keyName = "Dragonkin",
    expansion = "Dragonflight",
    tomeName = "How to Train a Dragonkin",
    itemID = 201791,
    unlock = { quests = { 72094 } },
    waypoint = { x = 46.8, y = 78.8, label = "Kaestrasz" },
    guide =
      "How to Train a Dragonkin (Dragonkin)\n\n" ..
      "Requirement:\n" ..
      "- Valdrakken Accord Renown 23\n\n" ..
      "Source:\n" ..
      "- Purchase from Kaestrasz (Valdrakken)\n\n" ..
      "Waypoint (Valdrakken):\n" ..
      "/way 46.8 78.8 Kaestrasz\n\n" ..
      "Use:\n" ..
      "- Read the book -> Lesser Dragonkin taming unlocked.",
  },

  {
    keyName = "Ottuks",
    expansion = "Dragonflight",
    tomeName = "Ottuk Taming",
    itemID = nil,
    iconOverride = "Interface\\Icons\\INV_Pet_Otter",
    wowheadOverride = WowheadSpellURL(390631),
    unlock = { quests = { 66444 }, spells = { 390631 } },
    guide =
      "Ottuk Taming (Ottuks)\n\n" ..
      "Requirement:\n" ..
      "- Iskaara Tuskarr Renown 11\n" ..
      "- Complete Ottuk quest chain\n\n" ..
      "Use:\n" ..
      "- Ottuk taming unlocked.",
  },

  {
    keyName = "Nah'qi",
    expansion = "Dragonflight",
    tomeName = "Cinder of Companionship",
    itemID = 211314,
    unlock = { quests = { 78842 } },
    waypoint = { x = 54.0, y = 65.0, label = "Nah'qi" },
    guide =
      "Cinder of Companionship (Nah'qi)\n\n" ..
      "Requirement:\n" ..
      "- Learn Reins of Anu'relos, Flame's Guidance (Mythic Fyrakk)\n" ..
      "- Learning it grants Cinder of Companionship (account-wide)\n\n" ..
      "Where:\n" ..
      "- Emerald Dream: flies very high around Amirdrassil canopy\n" ..
      "- Beast Mastery required\n\n" ..
      "Waypoint (Emerald Dream - near Amirdrassil):\n" ..
      "/way 54.0 65.0 Nah'qi\n\n" ..
      "Tip:\n" ..
      "- Wait near a trunk/branch and pull when her patrol passes close.\n\n" ..
      "Use:\n" ..
      "- Tame Nah'qi in the Emerald Dream.",
  },

  {
    keyName = "Florafaun",
    expansion = "Midnight",
    tomeName = "Trials of the Florafaun Hunter",
    itemID = 264895,
    unlock = { quests = { 1272785 } },
    guide =
      "Trials of the Florafaun Hunter (Florafaun)\n\n" ..
      "Source:\n" ..
      "- Drops from rares in Harandar\n\n" ..
      "Use:\n" ..
      "- Read the tome -> Florafaun taming unlocked.",
  },
}

------------------------------------------------------------
-- EXPANSION ORDER (sorting)
------------------------------------------------------------
local EXPANSION_ORDER = {
  ["Mists of Pandaria"] = 1,
  ["Legion"] = 2,
  ["BFA"] = 3,
  ["Battle for Azeroth"] = 3,
  ["Shadowlands"] = 4,
  ["Dragonflight"] = 5,
  ["Midnight"] = 6,
}

------------------------------------------------------------
-- UI STATE
------------------------------------------------------------
local UI = {
  frame = nil,
  scroll = nil,
  content = nil,
  rows = {},
  items = {},
  selected = nil,
  tab = "ALL",
  query = "",
  title = nil,
}

local function CreateSearchBox(parent)
  local eb
  if _G.SearchBoxTemplate then
    eb = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
  else
    eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  end
  eb:SetSize(260, 22)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return eb
end

local function EnsureResizeBounds(frame, minW, minH)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH)
  elseif frame.SetMinResize then
    frame:SetMinResize(minW, minH)
  end
end

local function EnsureMouseWheelScroll(scrollFrame)
  if not scrollFrame or not scrollFrame.GetVerticalScroll then return end
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local max = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
    local step = 30
    local nextVal = cur - (delta * step)
    if nextVal < 0 then nextVal = 0 end
    if nextVal > max then nextVal = max end
    self:SetVerticalScroll(nextVal)
  end)
end

------------------------------------------------------------
-- UI
------------------------------------------------------------
local function EnsureUI()
  if UI.frame then return end
  local db = GetDB()

  local f = CreateFrame("Frame", "HTT_Frame", UIParent, "BackdropTemplate")
  f:SetSize(db.w or 980, db.h or 560)
  f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    db.x, db.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
  end)

  EnsureResizeBounds(f, 820, 480)

  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
  f:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("Hunter Tame Tracker")
  UI.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local resize = CreateFrame("Button", nil, f)
  resize:SetPoint("BOTTOMRIGHT", -6, 6)
  resize:SetSize(18, 18)
  resize:EnableMouse(true)
  resize:SetScript("OnMouseDown", function()
    if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end
  end)
  resize:SetScript("OnMouseUp", function()
    if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    db.w, db.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
    UI.Refresh()
  end)
  local rt = resize:CreateTexture(nil, "OVERLAY")
  rt:SetAllPoints(resize)
  rt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

  local search = CreateSearchBox(f)
  search:SetPoint("TOPLEFT", 16, -42)

  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -90)
  sf:SetPoint("BOTTOMLEFT", 16, 16)
  sf:SetWidth(600)
  EnsureMouseWheelScroll(sf)

  local content = CreateFrame("Frame", nil, sf)
  content:SetPoint("TOPLEFT", 0, 0)
  content:SetPoint("TOPRIGHT", 0, 0)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)

  local guide = CreateFrame("Frame", nil, f, "BackdropTemplate")
  guide:SetPoint("TOPLEFT", sf, "TOPRIGHT", 18, 0)
  guide:SetPoint("BOTTOMRIGHT", -16, 16)
  guide:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  guide:SetBackdropColor(0, 0, 0, 0.80)

  local gTitle = guide:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  gTitle:SetPoint("TOPLEFT", 10, -10)
  gTitle:SetText("How to Get")

  local gSub = guide:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gSub:SetPoint("TOPLEFT", gTitle, "BOTTOMLEFT", 0, -8)
  gSub:SetTextColor(1, 1, 1, 0.95)
  gSub:SetText("Click a row on the left.")

  local copyWowheadBtn = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate")
  copyWowheadBtn:SetSize(140, 22)
  copyWowheadBtn:SetPoint("BOTTOMRIGHT", -10, 10)
  copyWowheadBtn:SetText("Copy Wowhead")
  copyWowheadBtn:Hide()

  local copyWaypointBtn = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate")
  copyWaypointBtn:SetSize(140, 22)
  copyWaypointBtn:SetPoint("RIGHT", copyWowheadBtn, "LEFT", -8, 0)
  copyWaypointBtn:SetText("Copy Waypoint")
  copyWaypointBtn:Hide()

  local gText = guide:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gText:SetPoint("TOPLEFT", gSub, "BOTTOMLEFT", 0, -10)
  gText:SetPoint("BOTTOMRIGHT", -10, 42)
  gText:SetJustifyH("LEFT")
  gText:SetJustifyV("TOP")
  gText:SetTextColor(1, 1, 1, 0.92)
  gText:SetText("|cffffff00Tip: Select an item to see its guide.|r")

  local progText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  progText:SetPoint("TOPRIGHT", -50, -44)
  progText:SetJustifyH("RIGHT")

  local bar = CreateFrame("StatusBar", nil, f, "BackdropTemplate")
  bar:SetSize(260, 10)
  bar:SetPoint("TOPRIGHT", -50, -64)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  bar:SetBackdropColor(0, 0, 0, 0.5)

  local ROW_H, GAP = 42, 4
  local POOL_ROWS = 16

  for i = 1, POOL_ROWS do
    local row = CreateFrame("Button", nil, content, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + GAP)))
    row:SetPoint("TOPRIGHT", 0, -((i - 1) * (ROW_H + GAP)))
    row:RegisterForClicks("LeftButtonUp")
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0, 0, 0, 0.25)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetAlpha(0.12)

    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetSize(6, ROW_H)
    row.stripe:SetPoint("LEFT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 10, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.text:SetPoint("RIGHT", -10, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("MIDDLE")
    row.text:SetWordWrap(false)
    if row.text.SetMaxLines then row.text:SetMaxLines(1) end

    row.sel = row:CreateTexture(nil, "OVERLAY")
    row.sel:SetAllPoints(row)
    row.sel:SetColorTexture(1, 1, 1, 0.06)
    row.sel:Hide()

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints(row)
    row.hl:SetColorTexture(1, 1, 1, 0.04)

    row:SetScript("OnClick", function(self)
      local item = self.data
      if not item then return end
      UI.selected = item
      UI.UpdateGuide()
      UI.RefreshSelection()
    end)

    UI.rows[i] = row
  end

  local function ResetSelectionForContextChange()
    UI.selected = nil
    UI.UpdateGuide()
    UI.RefreshSelection()
  end

  local function ScrollTop()
    if UI.scroll and UI.scroll.SetVerticalScroll then
      UI.scroll:SetVerticalScroll(0)
    end
  end

  local function MakeTab(text, key, anchor)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(92, 22)
    b:SetText(text)
    if anchor then
      b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    else
      b:SetPoint("LEFT", search, "RIGHT", 10, 0)
    end
    b:SetScript("OnClick", function()
      UI.tab = key
      ResetSelectionForContextChange()
      UI.Refresh()
      ScrollTop()
    end)
    return b
  end

  local tabAll = MakeTab("All", "ALL", nil)
  local tabMissing = MakeTab("Missing", "MISSING", tabAll)
  local tabUnlocked = MakeTab("Unlocked", "UNLOCKED", tabMissing)

  UI.frame = f
  UI.search = search
  UI.tabs = { all = tabAll, missing = tabMissing, unlocked = tabUnlocked }
  UI.progText = progText
  UI.progBar = bar
  UI.scroll = sf
  UI.content = content
  UI.guideTitle = gTitle
  UI.guideSub = gSub
  UI.guideText = gText
  UI.copyWowheadBtn = copyWowheadBtn
  UI.copyWaypointBtn = copyWaypointBtn
  UI.rowCfg = { rowH = ROW_H, gap = GAP }

  search:SetScript("OnTextChanged", function(self)
    UI.query = self:GetText() or ""
    ResetSelectionForContextChange()
    UI.Refresh()
    ScrollTop()
  end)

  copyWowheadBtn:SetScript("OnClick", function()
    if UI.selected and UI.selected.wowhead and UI.selected.wowhead ~= "" then
      ShowCopyPopup(UI.selected.wowhead)
    end
  end)

  copyWaypointBtn:SetScript("OnClick", function()
    if UI.selected and UI.selected.waypointText and UI.selected.waypointText ~= "" then
      ShowCopyPopup(UI.selected.waypointText)
    end
  end)

  function UI.ApplyTabStyles()
    local function SetActive(btn, active)
      btn:SetEnabled(not active)
      if active then
        btn:GetFontString():SetTextColor(1, 0.9, 0.2)
      else
        btn:GetFontString():SetTextColor(1, 1, 1)
      end
    end
    SetActive(UI.tabs.all, UI.tab == "ALL")
    SetActive(UI.tabs.missing, UI.tab == "MISSING")
    SetActive(UI.tabs.unlocked, UI.tab == "UNLOCKED")
  end

  local function ExpansionTag(expansion)
    if type(expansion) ~= "string" or expansion == "" then return "" end
    return " (" .. expansion .. ")"
  end

  function UI.UpdateGuide()
    local item = UI.selected
    if not item then
      UI.guideTitle:SetText("How to Get")
      UI.guideSub:SetText("Click a row on the left.")
      UI.guideText:SetText("|cffffff00Tip: Select an item to see its guide.|r")
      UI.copyWowheadBtn:Hide()
      UI.copyWaypointBtn:Hide()
      return
    end

    UI.guideTitle:SetText(item.tomeName)

    local fullExp = item.expansionFull or item.expansion or ""
    local fullTag = (fullExp ~= "") and (" (" .. fullExp .. ")") or ""
    UI.guideSub:SetText(string.format("%s%s — %s", item.keyName, fullTag, StatusText(item.ok)))

    UI.guideText:SetText(item.guide or "")

    if item.wowhead and item.wowhead ~= "" then
      UI.copyWowheadBtn:Show()
    else
      UI.copyWowheadBtn:Hide()
    end

    if HasTomTom() and item.waypointText and item.waypointText ~= "" then
      UI.copyWaypointBtn:Show()
    else
      UI.copyWaypointBtn:Hide()
    end
  end

  function UI.RefreshSelection()
    for _, row in ipairs(UI.rows) do
      if row.data and UI.selected and row.data.idx == UI.selected.idx then
        row.sel:Show()
      else
        row.sel:Hide()
      end
    end
  end

  function UI.BuildItems()
    local queries = BuildQueryVariants(UI.query or "")
    local wantMissing = UI.tab == "MISSING"
    local wantUnlocked = UI.tab == "UNLOCKED"

    local items = {}
    local unlockedCount = 0

    for idx, e in ipairs(LIST) do
      local ok = IsUnlocked(e.unlock)
      if ok then unlockedCount = unlockedCount + 1 end

      local passTab = true
      if wantMissing then passTab = (not ok) end
      if wantUnlocked then passTab = ok end

      if passTab then
        local alias = ExpansionAliases(e.expansion, e.expansionFull)
        local hay = NormalizeSearchQuery(
          (e.keyName or "") .. " "
            .. (e.tomeName or "") .. " "
            .. (e.expansion or "") .. " "
            .. (e.expansionFull or "") .. " "
            .. alias .. " "
            .. (e.guide or "")
        )

        if MatchesAnyQuery(hay, queries) then
          local wowhead = e.wowheadOverride
          if (not wowhead or wowhead == "") and e.itemID then
            wowhead = WowheadItemURL(e.itemID)
          end

          local waypointText = FormatWaypoint(e.waypoint)

          table.insert(items, {
            idx = idx,
            keyName = e.keyName,
            expansion = e.expansion,
            expansionFull = e.expansionFull,
            tomeName = e.tomeName,
            itemID = e.itemID,
            iconOverride = e.iconOverride,
            unlock = e.unlock,
            ok = ok,
            guide = e.guide,
            wowhead = wowhead,
            waypointText = waypointText,
          })
        end
      end
    end

    table.sort(items, function(a, b)
      local aOrder = EXPANSION_ORDER[a.expansion] or 99
      local bOrder = EXPANSION_ORDER[b.expansion] or 99
      if aOrder == bOrder then
        return a.idx < b.idx
      end
      return aOrder < bOrder
    end)

    for i, it in ipairs(items) do
      it.displayIdx = i
    end

    UI.items = items
    UI.unlockedCount = unlockedCount
    UI.totalCount = #LIST
  end

  function UI.RefreshHeader()
    local total = UI.totalCount or #LIST
    local unlocked = UI.unlockedCount or 0
    local pct = (total > 0) and (unlocked / total) or 0
    UI.progText:SetText(string.format("%d / %d unlocked (%.0f%%)", unlocked, total, pct * 100))
    UI.progBar:SetValue(pct)
  end

  local function GetScrollChildWidth()
    local w = UI.scroll:GetWidth() or 0
    return math.max(1, w - 28)
  end

  function UI.RefreshRows()
    local rowH, gap = UI.rowCfg.rowH, UI.rowCfg.gap

    UI.content:SetWidth(GetScrollChildWidth())
    UI.content:SetHeight(#UI.items * (rowH + gap))

    for i, row in ipairs(UI.rows) do
      local item = UI.items[i]
      if not item then
        row:Hide()
        row.data = nil
      else
        row:Show()
        row.data = item

        local icon = GetBestIcon(item, UI.Refresh)
        row.icon:SetTexture(icon)
        row.bg:SetTexture(icon)

        local r, g, b = StatusRGB(item.ok)
        row.stripe:SetColorTexture(r, g, b, 0.85)

        local expansionTag = ExpansionTag(item.expansion)

        local text
        if UI.tab == "ALL" then
          text = string.format(
            "%d. %s  |cff9aa0a6— %s%s —|r  %s",
            item.displayIdx or i,
            item.tomeName,
            item.keyName,
            expansionTag,
            StatusText(item.ok)
          )
        else
          text = string.format(
            "%s  |cff9aa0a6— %s%s —|r  %s",
            item.tomeName,
            item.keyName,
            expansionTag,
            StatusText(item.ok)
          )
        end

        row.text:SetText(text)
      end
    end

    UI.RefreshSelection()
  end

  function UI.Refresh()
    UI.ApplyTabStyles()
    UI.BuildItems()
    UI.RefreshHeader()
    UI.RefreshRows()
    UI.UpdateGuide()
  end
end

------------------------------------------------------------
-- TOGGLE
------------------------------------------------------------
local function ToggleUI()
  EnsureUI()

  if UI.frame:IsShown() then
    UI.frame:Hide()
    return
  end

  UI.tab = "ALL"
  UI.query = ""
  UI.selected = nil
  if UI.search then UI.search:SetText("") end

  if UI.title then
    UI.title:SetText("Hunter Tame Tracker")
  end

  UI.Refresh()

  if UI.scroll and UI.scroll.SetVerticalScroll then
    UI.scroll:SetVerticalScroll(0)
  end

  UI.frame:Show()
end

------------------------------------------------------------
-- VERSION PRINT
------------------------------------------------------------
local function PrintVersion()
  local msg = ("Hunter Tame Tracker v%s"):format(ADDON_VERSION)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  else
    print(msg)
  end
end

------------------------------------------------------------
-- SLASH COMMANDS
------------------------------------------------------------
SLASH_HTT1 = "/htt"
SLASH_HTT2 = "/huntertame"
SLASH_HTT3 = "/huntertametracker"
SlashCmdList.HTT = function(msg)
  msg = NormalizeSearchQuery(msg or "")
  if msg == "version" or msg == "ver" or msg == "v" then
    PrintVersion()
    return
  end
  ToggleUI()
end

-- modules/equipment_info.lua
local ADDON_NAME, NS = ...
local Kaldo = NS.Kaldo

local L = NS.L
local DB = NS.DB

local M = {}
local TIP_NAME = "KaldoTVScanTooltip"
local TIP_TEXTLEFT_PREFIX = TIP_NAME .. "TextLeft"
local ILVL_DEFAULTS_CHECKPOINT = "12.0.1"

M.events = {
  "PLAYER_LOGIN",
  "ADDON_LOADED",
  "PLAYER_EQUIPMENT_CHANGED",
  "UNIT_INVENTORY_CHANGED",
  "SOCKET_INFO_UPDATE",
  "PLAYER_ENTERING_WORLD",
  "INSPECT_READY",
  "GET_ITEM_INFO_RECEIVED",
  "KALDOTV_CHARACTERFRAME_OPENED",
  "KALDOTV_INSPECTFRAME_OPENED",
}

M.displayName = L.EQUIPMENT_INFO

local defaults = {
  font_family = "Fonts\\FRIZQT__.TTF",
  font_size_ilvl = 16,
  font_size_enchant = 10,
  enchants_display = 2, -- 1 only missing, 2 missing+low, 3 all
  show_inspect = false,
  show_inspect_avg = true,
  low_ilvl = 305,
  medium_ilvl = 318,
  high_ilvl = 331,

  -- colors (rgba)
  color_low   = {1, 0, 0, 1},
  color_med   = {1, 1, 0, 1},
  color_high  = {0, 1, 0, 1},
  color_vhigh = {0.69, 0.30, 1, 1},

  display_sockets = true,

  -- enchants toggles
  enchant_1=true,enchant_2=false,enchant_3=true,enchant_15=false,enchant_5=true,enchant_9=false,
  enchant_10=false,enchant_6=false,enchant_7=true,enchant_8=true,enchant_11=true,enchant_12=true,
  enchant_13=false,enchant_14=false,enchant_16=true,enchant_17=true,

  -- sockets expected
  sockets_1=1,sockets_2=1,sockets_3=0,sockets_15=0,sockets_5=0,sockets_9=1,sockets_10=0,sockets_6=1,
  sockets_7=0,sockets_8=0,sockets_11=1,sockets_12=1,sockets_13=0,sockets_14=0,sockets_16=0,sockets_17=0,
}

local function applyDefaults(db)
  DB:ApplyDefaults(db, defaults)
end
local function applyFixedSlotRequirements(db)
  for k, v in pairs(defaults) do
    if type(k) == "string" and (k:find("^enchant_") or k:find("^sockets_")) then
      db[k] = v
    end
  end
end

local function applyIlvlDefaultsCheckpoint(db)
  if db.ilvl_defaults_checkpoint == ILVL_DEFAULTS_CHECKPOINT then return end
  db.low_ilvl = defaults.low_ilvl
  db.medium_ilvl = defaults.medium_ilvl
  db.high_ilvl = defaults.high_ilvl
  db.ilvl_defaults_checkpoint = ILVL_DEFAULTS_CHECKPOINT
end

local function makeIdSet(ids)
  local set = {}
  for _, id in ipairs(ids) do
    set[id] = true
  end
  return set
end

local MAX_RANK_ENCHANT_IDS = makeIdSet({
  7935, 7937, 7939, 7949, 7957, 7959, 7961, 7963, 7965, 7967, 7969,
  7971, 7973, 7975, 7977, 7979, 7981, 7983, 7985, 7987, 7989, 7991,
  7993, 7995, 7997, 7999, 8001, 8003, 8005, 8007, 8009, 8011, 8013,
  8015, 8017, 8019, 8021, 8023, 8025, 8027, 8029, 8031, 8033, 8035,
  8037, 8039, 8041, 8159, 8161, 8163, 8613, 8615, 8689, 8820,
})

local MAX_RANK_GEM_IDS = makeIdSet({
  240906, 240904, 240908, 240888, 240912, 240892, 240890, 240916,
  240914, 240896, 240910, 240900, 240894, 240898, 240967, 240918,
  240902, 240971, 240969, 240983, 241142, 241143, 241144
})

local function findQualityTierInTooltipInfo(info)
  if type(info) ~= "table" or type(info.lines) ~= "table" then
    return nil
  end

  local function scanValue(value)
    if type(value) == "string" then
      local tier = value:match("Professions%-ChatIcon%-Quality%-Tier(%d)")
      if tier then
        return tonumber(tier)
      end
    elseif type(value) == "table" then
      for _, nested in pairs(value) do
        local tier = scanValue(nested)
        if tier then
          return tier
        end
      end
    end
    return nil
  end

  for _, line in ipairs(info.lines) do
    local tier = scanValue(line)
    if tier then
      return tier
    end
  end

  return nil
end

local function getItemEnchantId(link)
  if type(link) ~= "string" then return nil end
  local enchantId = link:match("item:%-?%d+:(%-?%d+)")
  return enchantId and tonumber(enchantId) or nil
end

local function isLowRankEnchant(link)
  local enchantId = getItemEnchantId(link)
  -- The explicit list is authoritative for known maximum-rank enchants.
  -- Some new enchants expose their profession quality as tier 2 even though
  -- rank 2 is the highest available rank for that enchant.
  if enchantId and MAX_RANK_ENCHANT_IDS[enchantId] then
    return false
  end

  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local info = C_TooltipInfo.GetHyperlink(link)
    local tier = findQualityTierInTooltipInfo(info)
    if tier then
      return tier < 3
    end
  end

  if enchantId == nil then
    return nil
  end
  return true
end

local function getItemIdFromLink(link)
  if type(link) ~= "string" then return nil end
  local itemId = link:match("item:(%-?%d+)")
  return itemId and tonumber(itemId) or nil
end

local function isLowRankGem(link)
  local itemId = getItemIdFromLink(link)
  if itemId and MAX_RANK_GEM_IDS[itemId] then
    return false
  end

  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local info = C_TooltipInfo.GetHyperlink(link)
    local tier = findQualityTierInTooltipInfo(info)
    if tier then
      return tier < 3
    end
  end

  return true
end

local function getEquippedAverageItemLevel()
  if not GetAverageItemLevel then return nil end
  local avgItemLevel, avgEquipped = GetAverageItemLevel()
  if avgEquipped and avgEquipped > 0 then
    return avgEquipped
  end
  return avgItemLevel
end

local slots = {
  { id=1,  frame="CharacterHeadSlot" },
  { id=2,  frame="CharacterNeckSlot" },
  { id=3,  frame="CharacterShoulderSlot" },
  { id=15, frame="CharacterBackSlot" },
  { id=5,  frame="CharacterChestSlot" },
  { id=9,  frame="CharacterWristSlot" },
  { id=10, frame="CharacterHandsSlot" },
  { id=6,  frame="CharacterWaistSlot" },
  { id=7,  frame="CharacterLegsSlot" },
  { id=8,  frame="CharacterFeetSlot" },
  { id=11, frame="CharacterFinger0Slot" },
  { id=12, frame="CharacterFinger1Slot" },
  { id=13, frame="CharacterTrinket0Slot" },
  { id=14, frame="CharacterTrinket1Slot" },
  { id=16, frame="CharacterMainHandSlot" },
  { id=17, frame="CharacterSecondaryHandSlot" },
}

local inspectSlots = {
  { id=1,  frame="InspectHeadSlot" },
  { id=2,  frame="InspectNeckSlot" },
  { id=3,  frame="InspectShoulderSlot" },
  { id=15, frame="InspectBackSlot" },
  { id=5,  frame="InspectChestSlot" },
  { id=9,  frame="InspectWristSlot" },
  { id=10, frame="InspectHandsSlot" },
  { id=6,  frame="InspectWaistSlot" },
  { id=7,  frame="InspectLegsSlot" },
  { id=8,  frame="InspectFeetSlot" },
  { id=11, frame="InspectFinger0Slot" },
  { id=12, frame="InspectFinger1Slot" },
  { id=13, frame="InspectTrinket0Slot" },
  { id=14, frame="InspectTrinket1Slot" },
  { id=16, frame="InspectMainHandSlot" },
  { id=17, frame="InspectSecondaryHandSlot" },
}

function M:EnsureDB()
  local db = DB:EnsureModuleState("EquipmentInfo", defaults)
  applyDefaults(db)
  applyFixedSlotRequirements(db)
  applyIlvlDefaultsCheckpoint(db)
  return db
end

function M:ResetDB()
  local db = DB:ResetModuleState("EquipmentInfo", defaults)
  applyFixedSlotRequirements(db)
  self.db = db
  self:InvalidateRenderCache()
  self:UpdateDisplay()
end

local function wrapText(text, maxLen)
  local out, lineLen, lineNum = "", 0, 1
  for word in text:gmatch("%S+") do
    local wl = #word
    if lineLen + wl > maxLen then
      if lineNum == 3 then return out end
      out = out .. "\n" .. word .. " "
      lineLen = wl + 1
      lineNum = lineNum + 1
    else
      out = out .. word .. " "
      lineLen = lineLen + wl + 1
    end
  end
  return out
end

local function colorToHex(c)
  if type(c) ~= "table" then return "|cFFFFFFFF" end
  local r = math.floor((c[1] or 1) * 255 + 0.5)
  local g = math.floor((c[2] or 1) * 255 + 0.5)
  local b = math.floor((c[3] or 1) * 255 + 0.5)
  return string.format("|cFF%02X%02X%02X", r, g, b)
end

local function ilvlColor(db, ilvl)
  if ilvl < db.low_ilvl then return colorToHex(db.color_low)
  elseif ilvl < db.medium_ilvl then return colorToHex(db.color_med)
  elseif ilvl < db.high_ilvl then return colorToHex(db.color_high)
  else return colorToHex(db.color_vhigh) end
end

local function buildItemLevelPattern()
  local s = ITEM_LEVEL or "Item Level %d"
  s = s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  s = s:gsub("%%d", "(%%d+)")
  return s
end

local ITEM_LEVEL_PATTERN = buildItemLevelPattern()

local function getItemLevelFromTooltip(tip, unit, slotId)
  if not (tip and unit and slotId) then return nil end
  tip:ClearLines()
  tip:SetInventoryItem(unit, slotId)
  for line = 2, tip:NumLines() do
    local fs = _G[TIP_TEXTLEFT_PREFIX .. line]
    local txt = fs and fs:GetText()
    if txt then
      local n = txt:match(ITEM_LEVEL_PATTERN)
      if n then return tonumber(n) end
    end
  end
  return nil
end

local function getItemLevelFromTooltipInfo(unit, slotId)
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem and unit and slotId) then
    return nil
  end
  local info = C_TooltipInfo.GetInventoryItem(unit, slotId)
  if not info or not info.lines then return nil end
  for _, line in ipairs(info.lines) do
    local text = line.leftText or line.rightText
    if text then
      local n = text:match(ITEM_LEVEL_PATTERN)
      if n then return tonumber(n) end
    end
  end
  return nil
end

local function getItemLevelFromHyperlink(link)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and link) then
    return nil
  end
  local info = C_TooltipInfo.GetHyperlink(link)
  if not info or not info.lines then return nil end
  for _, line in ipairs(info.lines) do
    local text = line.leftText or line.rightText
    if text then
      local n = text:match(ITEM_LEVEL_PATTERN)
      if n then return tonumber(n) end
    end
  end
  return nil
end

local function getItemLevelFromHyperlinkTooltip(tip, link)
  if not (tip and link) then return nil end
  local ok = pcall(function()
    tip:ClearLines()
    tip:SetHyperlink(link)
  end)
  if not ok then return nil end
  for line = 2, tip:NumLines() do
    local fs = _G[TIP_TEXTLEFT_PREFIX .. line]
    local txt = fs and fs:GetText()
    if txt then
      local n = txt:match(ITEM_LEVEL_PATTERN)
      if n then return tonumber(n) end
    end
  end
  return nil
end

local function requestItemData(self, itemId)
  if not (self and itemId and C_Item and C_Item.RequestLoadItemDataByID) then return end
  if C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemId) then return end
  self.pendingInspect = self.pendingInspect or {}
  if not self.pendingInspect[itemId] then
    self.pendingInspect[itemId] = true
    C_Item.RequestLoadItemDataByID(itemId)
  end
end

local function getSafeItemLevel(link, slotId, unit, tip, itemId, self)
  if not link then return nil end
  if unit == "player" and C_Item and C_Item.GetCurrentItemLevel and ItemLocation and slotId then
    local loc = ItemLocation:CreateFromEquipmentSlot(slotId)
    if loc and loc:IsValid() then
      local cur = C_Item.GetCurrentItemLevel(loc)
      if cur and cur > 0 then return cur end
    end
  end
  local _, _, _, ilvl = C_Item.GetItemInfo(link)
  local detailed = (C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or nil
  local tipLevel = getItemLevelFromTooltipInfo(unit, slotId)
    or getItemLevelFromHyperlink(link)
    or getItemLevelFromHyperlinkTooltip(tip, link)
    or getItemLevelFromTooltip(tip, unit, slotId)
  if unit ~= "player" and tipLevel and tipLevel > 0 then
    return tipLevel
  end
  if (ilvl and ilvl > 300) or (detailed and detailed > 300) then
    if tipLevel and tipLevel > 0 then
      if ilvl and detailed then
        return math.min(ilvl, detailed, tipLevel)
      elseif ilvl then
        return math.min(ilvl, tipLevel)
      elseif detailed then
        return math.min(detailed, tipLevel)
      end
      return tipLevel
    end
    if unit ~= "player" then
      if itemId then requestItemData(self, itemId) end
      return nil
    end
  end
  if detailed and detailed > 0 and ilvl and ilvl > 0 then
    if ilvl > 300 or detailed > 300 then
      return math.min(ilvl, detailed)
    end
  end
  if unit ~= "player" and detailed and detailed > 0 then
    return detailed
  end
  return detailed or ilvl
end

local function getAverageItemLevelForSlots(self, unit, slotList)
  if not (self and unit and slotList) then return nil end
  local total, count = 0, 0
  local guid = unit ~= "player" and UnitGUID and UnitGUID(unit) or nil

  for _, slot in ipairs(slotList) do
    local link = GetInventoryItemLink(unit, slot.id)
    if link then
      local itemId = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link) or nil
      local dataLevel = nil
      if unit ~= "player" and C_Inspect and C_Inspect.GetInspectItemsData and guid then
        local data = C_Inspect.GetInspectItemsData(guid)
        local itemData = data and data[slot.id]
        if itemData and itemData.itemLevel and itemData.itemLevel > 0 then
          dataLevel = itemData.itemLevel
        end
      end
      local ilvl = getSafeItemLevel(link, slot.id, unit, self.tip, itemId, self)
      if unit ~= "player" and not ilvl and dataLevel and dataLevel > 0 then
        ilvl = dataLevel
      end
      if ilvl and ilvl > 0 then
        total = total + ilvl
        count = count + 1
      end
    end
  end

  if count == 0 then return nil end
  return total / count
end

local function getInspectDefaultAvgText()
  local candidates = {
    _G.InspectPaperDollItemsFrame and _G.InspectPaperDollItemsFrame.ItemLevelText,
    _G.InspectPaperDollItemsFrame and _G.InspectPaperDollItemsFrame.itemLevelText,
    _G.InspectItemLevelText,
  }
  for _, fs in ipairs(candidates) do
    if fs and fs.SetText then
      return fs
    end
  end
  return nil
end

local function getCharacterDefaultAvgText()
  local candidates = {
    _G.CharacterStatsPane and _G.CharacterStatsPane.ItemLevelFrame and _G.CharacterStatsPane.ItemLevelFrame.Value,
    _G.CharacterStatsPane and _G.CharacterStatsPane.ItemLevelCategory and _G.CharacterStatsPane.ItemLevelCategory.Value,
    _G.PaperDollFrame and _G.PaperDollFrame.ItemLevelFrame and _G.PaperDollFrame.ItemLevelFrame.Value,
    _G.PaperDollFrame and _G.PaperDollFrame.itemLevelFrame and _G.PaperDollFrame.itemLevelFrame.Value,
    _G.CharacterItemLevelText,
  }
  for _, fs in ipairs(candidates) do
    if fs and fs.SetText then
      return fs
    end
  end
  return nil
end

local styleAvgText

local function setManagedAvgText(fs, text, fontPath, fontSize)
  if not fs then return end
  if not fs._kaldoManaged then
    hooksecurefunc(fs, "SetText", function(frame, newText)
      if frame._kaldoApplyingText then return end
      if not frame._kaldoDesiredText or frame._kaldoDesiredText == "" then return end
      if newText == frame._kaldoDesiredText then return end
      frame._kaldoApplyingText = true
      frame:SetText(frame._kaldoDesiredText)
      frame._kaldoApplyingText = nil
    end)
    fs:HookScript("OnShow", function(frame)
      if frame._kaldoDesiredText and frame._kaldoDesiredText ~= "" then
        frame._kaldoApplyingText = true
        frame:SetText(frame._kaldoDesiredText)
        frame._kaldoApplyingText = nil
      end
    end)
    fs._kaldoManaged = true
  end
  fs._kaldoDesiredText = text
  styleAvgText(fs, fontPath, fontSize)
  fs._kaldoApplyingText = true
  fs:SetText(text or "")
  fs._kaldoApplyingText = nil
  fs:SetAlpha(1)
  if text and text ~= "" then
    fs:Show()
  else
    fs:Hide()
  end
end

styleAvgText = function(fs, fontPath, fontSize)
  if not fs then return end
  fs:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", fontSize or 18, "OUTLINE")
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  fs:SetJustifyH("CENTER")
end

function M:GetOptions()
  return {
    { type="header", text=L.DISPLAY },
    { type="select", key="font_family", label=(L and L.FONT) or "Font", values=function() return Kaldo.Media:GetFonts() end },
    { type="number", key="font_size_ilvl", label=L.SIZE_ILVL, min=6, max=30, step=1 },
    { type="number", key="font_size_enchant", label=L.ENCHANT_SIZE, min=6, max=30, step=1 },
    { type="toggle", key="show_inspect", label=(L and L.SHOW_INSPECT) or "Show inspect iLvl" },
    { type="toggle", key="show_inspect_avg", label=(L and L.SHOW_INSPECT_AVG) or "Show inspect average iLvl" },
    { type="select", key="enchants_display", label=L.DISPLAY_ENCHANTS,
      values={{1,L.MISSING},{2,L.MISSING_LOW_TIER},{3,L.ALL}} },

    { type="header", text=L.ILVL_TRESHOLDS },
    { type="number", key="low_ilvl", label=L.LOW .. " < ...", min=100, max=350, step=1 },
    { type="number", key="medium_ilvl", label=L.MEDIUM .. " < ...", min=100, max=350, step=1 },
    { type="number", key="high_ilvl", label=L.HIGH .. " < ...", min=100, max=350, step=1 },

    { type="header", text=L.ILVL_COLORS },
    { type="color", key="color_low", label=L.LOW },
    { type="color", key="color_med", label=L.MEDIUM },
    { type="color", key="color_high", label=L.HIGH },
    { type="color", key="color_vhigh", label=L.VERY_HIGH },

    { type="header", text=L.SOCKETS },
    { type="toggle", key="display_sockets", label=L.DISPLAY_SOCKETS },
  }
end

function M:OnOptionChanged(key, _)
  if key == "show_inspect" then
    if self.db and self.db.show_inspect and C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_InspectUI")
    end
  end
  self:InvalidateRenderCache()
  self:UpdateDisplay()
end

function M:OnRegister(core)
  self.db = nil
  self.fontsIL = {}
  self.fontsEN = {}
  self.fontsILInspect = {}
  self.fontsENInspect = {}
  self.lastUpdate = 0
  self.playerSlotCache = {}
  self.inspectSlotCache = {}
  self._cacheRevision = 0

  self.tip = _G[TIP_NAME]
  if not self.tip then
    self.tip = CreateFrame("GameTooltip", TIP_NAME, nil, "GameTooltipTemplate")
    self.tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  end

  if CharacterFrame and not self.hooked then
    hooksecurefunc(CharacterFrame, "Show", function()
      core:Dispatch("KALDOTV_CHARACTERFRAME_OPENED")
    end)
    self.hooked = true
  end

  if InspectFrame and not self.inspectHooked then
    hooksecurefunc(InspectFrame, "Show", function()
      local unit = InspectFrame and InspectFrame.unit
      if unit and UnitExists(unit) then
        core:Dispatch("KALDOTV_INSPECTFRAME_OPENED")
      end
    end)
    self.inspectHooked = true
  end

  if not self.inspectShowHooked and _G.InspectFrame_Show then
    hooksecurefunc("InspectFrame_Show", function()
      local unit = InspectFrame and InspectFrame.unit
      if unit and UnitExists(unit) then
        core:Dispatch("KALDOTV_INSPECTFRAME_OPENED")
      end
    end)
    self.inspectShowHooked = true
  end
end

function M:InvalidateRenderCache(scope)
  if not scope or scope == "player" then
    self.playerSlotCache = {}
    self.playerSlotItems = {}
  end

  if not scope or scope == "inspect" then
    self.inspectSlotCache = {}
    self.inspectSlotItems = {}
  end
end

function M:EnsureFonts(slotList, ilTable, enTable)
  for i, slot in ipairs(slotList) do
    local parent = _G[slot.frame]
    if parent and not ilTable[i] then
      ilTable[i] = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      enTable[i] = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      ilTable[i]:SetDrawLayer("OVERLAY", 7)
      enTable[i]:SetDrawLayer("OVERLAY", 7)
    end
  end
end

function M:ClearFonts(ilTable, enTable, count)
  for i=1,count do
    local a,b = ilTable[i], enTable[i]
    if a then a:Hide(); a:SetText(""); a:ClearAllPoints() end
    if b then b:Hide(); b:SetText(""); b:ClearAllPoints() end
  end
end

local function isLeftAnchoredSlot(slotId)
  return slotId == 1 or slotId == 2 or slotId == 3 or slotId == 15
    or slotId == 5 or slotId == 9 or slotId == 17
end

function M:PrepareSlotTexts(parent, slotId, fsIL, fsEN, db)
  fsIL:ClearAllPoints()
  fsEN:ClearAllPoints()
  fsIL:SetText("")
  fsEN:SetText("")
  fsIL:SetFont(db.font_family, db.font_size_ilvl, "OUTLINE")
  fsEN:SetFont(db.font_family, db.font_size_enchant, "OUTLINE")
  fsIL:SetPoint("CENTER", parent, "CENTER", 2, -2)

  if isLeftAnchoredSlot(slotId) then
    fsEN:SetJustifyH("LEFT")
    if slotId == 17 then
      fsEN:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, -20)
    else
      fsEN:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, -4)
    end
  else
    fsEN:SetJustifyH("RIGHT")
    if slotId == 16 then
      fsEN:SetPoint("TOPRIGHT", parent, "TOPLEFT", -4, -20)
    else
      fsEN:SetPoint("TOPRIGHT", parent, "TOPLEFT", -4, -4)
    end
  end
end

function M:GetInspectSlotData(unit, slotId)
  if unit == "player" or not (C_Inspect and C_Inspect.GetInspectItemsData) then
    return nil, nil
  end

  local guid = UnitGUID(unit)
  if not guid then
    return nil, nil
  end

  local data = C_Inspect.GetInspectItemsData(guid)
  if not (data and data[slotId]) then
    return nil, nil
  end

  return data[slotId].link, data[slotId].level
end

function M:GetSocketDisplayText(unit, db, slotId, link)
  if unit ~= "player" then
    return ""
  end

  if not (db.display_sockets and db["sockets_" .. slotId]) then
    return ""
  end

  local itemId = tonumber(link:match("item:(%d+):"))
  if itemId == 228411 then
    return ""
  end

  local stats = C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link) or nil
  local totalSockets = 0
  if stats then
    totalSockets =
      (stats["EMPTY_SOCKET_RED"] or 0) +
      (stats["EMPTY_SOCKET_BLUE"] or 0) +
      (stats["EMPTY_SOCKET_YELLOW"] or 0) +
      (stats["EMPTY_SOCKET_PRISMATIC"] or 0) +
      (stats["EMPTY_SOCKET_META"] or 0) +
      (stats["EMPTY_SOCKET_COGWHEEL"] or 0) +
      (stats["EMPTY_SOCKET_TINKER"] or 0)
  end

  local lines = {}
  if totalSockets < db["sockets_" .. slotId] then
    lines[#lines + 1] = "|cFFFF0000" .. L.MISSING_SOCKETS .. "|r"
  end

  local hasMaxRankGems, missingGems, gemCount = true, false, 0
  if totalSockets >= 1 then
    for gemid = 1, totalSockets do
      local _, socketedGemLink = C_Item.GetItemGem(link, gemid)
      if socketedGemLink then
        local gemItemID = getItemIdFromLink(socketedGemLink)
        if gemItemID and self.playerSlotItems and self.playerSlotItems[slotId] then
          self.playerSlotItems[slotId][gemItemID] = true
          requestItemData(self, gemItemID)
        end
        local isLowRank = isLowRankGem(socketedGemLink)
        if isLowRank == true then
          hasMaxRankGems = false
        end
      else
        missingGems = true
      end
      gemCount = gemCount + 1
    end
  end

  if gemCount < totalSockets or missingGems then
    lines[#lines + 1] = "|cFFFF0000" .. L.EMPTY_SOCKETS .. "|r"
  end
  if not hasMaxRankGems then
    lines[#lines + 1] = "|cFFFFFF00" .. L.LOW_QUALITY_GEMS .. "|r"
  end

  return table.concat(lines, "\n")
end

function M:GetEnchantDisplayText(db, slotId, unit, link, itemType, itemSubtype, playerClass)
  if unit ~= "player" or not db["enchant_" .. slotId] then
    return ""
  end

  self.tip:ClearLines()
  self.tip:SetInventoryItem(unit, slotId)

  local enchantPrefix = ENCHANTED_TOOLTIP_LINE and ENCHANTED_TOOLTIP_LINE:match("^(.-):")
  local enchantLine

  for line = 2, self.tip:NumLines() do
    local fs = _G[TIP_TEXTLEFT_PREFIX .. line]
    local txt = fs and fs:GetText()
    if txt and enchantPrefix and txt:find("^" .. enchantPrefix .. ":") then
      enchantLine = txt
      break
    end
  end

  local skipOffhandShield = (slotId == 17 and itemType == 4 and (itemSubtype == 6 or itemSubtype == 0))
  if skipOffhandShield then
    return ""
  end

  local isDKWeapon = (playerClass == "DEATHKNIGHT" and (slotId == 16 or slotId == 17))
  if not enchantLine then
    return "|cFFFF0000" .. L.MISSING_ENCHANT .. "|r"
  end

  local clean = enchantLine:match("^[^:]+:%s*(.+)$") or enchantLine
  local wrapped = wrapText(clean, 25)
  if isDKWeapon then
    if db.enchants_display == 3 then
      return "|cFF66CCFF" .. wrapped .. "|r"
    end
    return ""
  end

  local isLowRank = isLowRankEnchant(link)
  local color = isLowRank and "|cFFFFFF00" or "|cFF00FF00"
  if db.enchants_display == 3 or (db.enchants_display == 2 and isLowRank) then
    return color .. wrapped .. "|r"
  end

  return ""
end

function M:BuildSlotDisplay(unit, slotId, link, db, itemType, itemSubtype, playerClass)
  if not link then
    return ""
  end

  local parts = {}
  local socketText = self:GetSocketDisplayText(unit, db, slotId, link)
  if socketText ~= "" then
    parts[#parts + 1] = socketText
  end

  local enchantText = self:GetEnchantDisplayText(db, slotId, unit, link, itemType, itemSubtype, playerClass)
  if enchantText ~= "" then
    parts[#parts + 1] = enchantText
  end

  return table.concat(parts, "\n")
end

function M:RenderSlot(unit, slot, fsIL, fsEN, db, playerClass)
  local parent = _G[slot.frame]
  if not (parent and fsIL and fsEN) then
    if fsIL then fsIL:Hide() end
    if fsEN then fsEN:Hide() end
    return
  end

  self:PrepareSlotTexts(parent, slot.id, fsIL, fsEN, db)
  if not parent:IsVisible() then
    fsIL:Hide()
    fsEN:Hide()
    return
  end

  local link = GetInventoryItemLink(unit, slot.id)
  local itemsKey = unit == "player" and "playerSlotItems" or "inspectSlotItems"
  self[itemsKey] = self[itemsKey] or {}
  if not link then
    self[itemsKey][slot.id] = nil
    local inventoryID = GetInventoryItemID and GetInventoryItemID(unit, slot.id)
    if inventoryID then
      self[itemsKey][slot.id] = { [inventoryID] = true }
      requestItemData(self, inventoryID)
    end
  end
  local displayText = ""
  local cache = (unit == "player") and self.playerSlotCache or self.inspectSlotCache
  local dataLink, dataLevel, itemId
  if link then
    itemId = tonumber(link:match("item:(%d+):"))
    dataLink, dataLevel = self:GetInspectSlotData(unit, slot.id)
    local signature = table.concat({
      tostring(unit),
      tostring(slot.id),
      tostring(link),
      tostring(dataLink or ""),
      tostring(dataLevel or ""),
    }, "|")

    local cached = cache and cache[slot.id]
    if cached and cached.signature == signature then
      fsIL:SetText(cached.ilvlText or "")
      fsEN:SetText(cached.displayText or "")
      fsIL:Show()
      fsEN:Show()
      return
    end

    local dependencies = {}
    self[itemsKey][slot.id] = dependencies
    if itemId then
      dependencies[itemId] = true
      requestItemData(self, itemId)
    end
    local _, _, _, _, _, _, _, _, _, _, _, itemType, itemSubtype = C_Item.GetItemInfo(link)

    local linkForTip = dataLink or link
    local ilvl = getSafeItemLevel(linkForTip, slot.id, unit, self.tip, itemId, self)
    local ilvlText = ""
    if unit ~= "player" and not ilvl and dataLevel and dataLevel > 0 then
      ilvl = dataLevel
    end
    if ilvl then
      ilvlText = ilvlColor(db, ilvl) .. ilvl .. "|r"
      fsIL:SetText(ilvlText)
    elseif unit ~= "player" then
      self:ScheduleInspectRetry()
    end

    displayText = self:BuildSlotDisplay(unit, slot.id, link, db, itemType, itemSubtype, playerClass)
    if cache and ilvl then
      cache[slot.id] = {
        signature = signature,
        ilvlText = ilvlText,
        displayText = displayText,
      }
    end
  end

  fsIL:Show()
  fsEN:SetText(displayText)
  fsEN:Show()
end

function M:UpdateDisplayFor(unit, slotList, ilTable, enTable)
  if not unit then return end

  local db = self.db or self:EnsureDB()
  self.db = db
  local _, playerClass = UnitClass("player")
  if unit ~= "player" and C_Inspect and C_Inspect.GetInspectItemsData then
    local guid = UnitGUID(unit)
    if guid then
      self.inspectData = self.inspectData or {}
      if not self.inspectData[guid] then
        self.inspectData[guid] = true
        C_Inspect.RequestInspectItemsData(guid)
      end
    end
  end
  self:EnsureFonts(slotList, ilTable, enTable)

  for i, slot in ipairs(slotList) do
    self:RenderSlot(unit, slot, ilTable[i], enTable[i], db, playerClass)
  end
end

function M:UpdateSlotFor(unit, slotId, slotList, ilTable, enTable)
  if not unit or not slotId then return end
  local slotIndex
  for i, slot in ipairs(slotList) do
    if slot.id == slotId then
      slotIndex = i
      break
    end
  end
  if not slotIndex then return end

  local db = self.db or self:EnsureDB()
  self.db = db
  self:EnsureFonts(slotList, ilTable, enTable)
  local _, playerClass = UnitClass("player")

  local i = slotIndex
  local slot = slotList[i]
  self:RenderSlot(unit, slot, ilTable[i], enTable[i], db, playerClass)
end

function M:UpdateDisplay()
  local db = self.db or self:EnsureDB()
  self.db = db

  if CharacterFrame and CharacterFrame:IsShown() then
    self:UpdateDisplayFor("player", slots, self.fontsIL, self.fontsEN)
    local playerAvg = getEquippedAverageItemLevel()
    if not playerAvg or playerAvg <= 0 then
      playerAvg = getAverageItemLevelForSlots(self, "player", slots)
    end
    local defaultAvgText = getCharacterDefaultAvgText()
    if not self.characterAvgText then
      self.characterAvgText = CharacterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      self.characterAvgText:SetDrawLayer("OVERLAY", 7)
      if defaultAvgText then
        self.characterAvgText:SetPoint("CENTER", defaultAvgText, "CENTER", 0, 0)
      elseif CharacterStatsPane then
        self.characterAvgText:SetPoint("TOP", CharacterStatsPane, "TOP", 0, -52)
      else
        self.characterAvgText:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -135, -86)
      end
    end
    local avgFontSize = math.max(18, db.font_size_ilvl + 2)
    if playerAvg and playerAvg > 0 then
      local avgColored = string.format("%s%.1f|r", ilvlColor(db, playerAvg), playerAvg)
      if defaultAvgText then
        setManagedAvgText(defaultAvgText, avgColored, db.font_family, avgFontSize)
        self.characterAvgText:Hide()
      else
        styleAvgText(self.characterAvgText, db.font_family, avgFontSize)
        self.characterAvgText:SetText(avgColored)
        self.characterAvgText:Show()
      end
    else
      if defaultAvgText then
        setManagedAvgText(defaultAvgText, "", db.font_family, avgFontSize)
      end
      if self.characterAvgText then self.characterAvgText:Hide() end
    end
  else
    self:ClearFonts(self.fontsIL, self.fontsEN, #slots)
    if self.characterAvgText then self.characterAvgText:Hide() end
    local defaultAvgText = getCharacterDefaultAvgText()
    if defaultAvgText then
      setManagedAvgText(defaultAvgText, "", db.font_family, math.max(18, db.font_size_ilvl + 2))
    end
  end

  if db.show_inspect and InspectFrame and InspectFrame:IsShown() then
    local unit = self.inspectUnit or (InspectFrame and InspectFrame.unit) or "target"
    if UnitExists(unit) then
      self:UpdateDisplayFor(unit, inspectSlots, self.fontsILInspect, self.fontsENInspect)
      if db.show_inspect_avg then
        if not self.inspectAvgText then
          self.inspectAvgText = InspectFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          self.inspectAvgText:SetDrawLayer("OVERLAY", 7)
        end
        self.inspectAvgText:ClearAllPoints()
        self.inspectAvgText:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", 0, -22)
        styleAvgText(self.inspectAvgText, db.font_family, math.max(14, db.font_size_ilvl))
        local avg = getAverageItemLevelForSlots(self, unit, inspectSlots)
        if (not avg or avg <= 0) and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
          local inspectAvg = C_PaperDollInfo.GetInspectItemLevel(unit)
          if inspectAvg and inspectAvg > 0 then
            avg = inspectAvg
          end
        end
        if avg and avg > 0 then
          local avgColored = string.format("%s%.1f|r", ilvlColor(db, avg), avg)
          local defaultAvgText = getInspectDefaultAvgText()
          if defaultAvgText then defaultAvgText:Hide() end
          self.inspectAvgText:SetText(avgColored)
          self.inspectAvgText:Show()
        else
          local defaultAvgText = getInspectDefaultAvgText()
          if defaultAvgText then defaultAvgText:Hide() end
          if self.inspectAvgText then self.inspectAvgText:Hide() end
        end
      elseif self.inspectAvgText then
        self.inspectAvgText:Hide()
        local defaultAvgText = getInspectDefaultAvgText()
        if defaultAvgText then defaultAvgText:Hide() end
      end
    else
      self:ClearFonts(self.fontsILInspect, self.fontsENInspect, #inspectSlots)
      if self.inspectAvgText then self.inspectAvgText:Hide() end
      local defaultAvgText = getInspectDefaultAvgText()
      if defaultAvgText then defaultAvgText:Hide() end
    end
  else
    self:ClearFonts(self.fontsILInspect, self.fontsENInspect, #inspectSlots)
    if self.inspectAvgText then self.inspectAvgText:Hide() end
    local defaultAvgText = getInspectDefaultAvgText()
    if defaultAvgText then defaultAvgText:Hide() end
  end
end

function M:ScheduleInspectRetry()
  if self._inspectRetryTimer then return end
  self._inspectRetryCount = (self._inspectRetryCount or 0) + 1
  if self._inspectRetryCount > 6 then return end
  self._inspectRetryTimer = true
  C_Timer.After(0.2, function()
    self._inspectRetryTimer = nil
    if self.db and self.db.enabled and InspectFrame and InspectFrame:IsShown() then
      self:UpdateDisplay()
    end
  end)
end

function M:OnEvent(event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == "Blizzard_CharacterUI" then
      self:InvalidateRenderCache("player")
      self:UpdateDisplay()
    end
    if addon == "Blizzard_InspectUI" and InspectFrame and not self.inspectHooked then
      hooksecurefunc(InspectFrame, "Show", function()
        local unit = InspectFrame and InspectFrame.unit
        if unit and UnitExists(unit) then
          Kaldo:Dispatch("KALDOTV_INSPECTFRAME_OPENED")
        end
      end)
      self.inspectHooked = true
    end
    if addon == "Blizzard_InspectUI" and not self.inspectShowHooked and _G.InspectFrame_Show then
      hooksecurefunc("InspectFrame_Show", function()
        local unit = InspectFrame and InspectFrame.unit
        if unit and UnitExists(unit) then
          Kaldo:Dispatch("KALDOTV_INSPECTFRAME_OPENED")
        end
      end)
      self.inspectShowHooked = true
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    self.db = self:EnsureDB()
    self:InvalidateRenderCache()
    if C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_CharacterUI")
      if self.db.show_inspect then
        C_AddOns.LoadAddOn("Blizzard_InspectUI")
      end
    end
    return
  end

  if event == "PLAYER_EQUIPMENT_CHANGED" then
    local slotId = ...
    if self.playerSlotCache then
      self.playerSlotCache[slotId] = nil
    end
    self:UpdateSlotFor("player", slotId, slots, self.fontsIL, self.fontsEN)
    return
  elseif event == "UNIT_INVENTORY_CHANGED" and (... == "player") then
    self:InvalidateRenderCache("player")
    self:UpdateDisplay()
    return
  elseif event == "SOCKET_INFO_UPDATE" then
    self:InvalidateRenderCache("player")
    self:UpdateDisplay()
    return
  elseif event == "KALDOTV_CHARACTERFRAME_OPENED" or event == "PLAYER_ENTERING_WORLD" then
    self:InvalidateRenderCache("player")
    self:UpdateDisplay()
    return
  end

  if event == "KALDOTV_INSPECTFRAME_OPENED" then
    if C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_InspectUI")
    end
    local unit = InspectFrame and InspectFrame.unit
    if not (unit and UnitExists(unit)) then return end
    self.inspectUnit = unit
    self.inspectData = {}
    self:InvalidateRenderCache("inspect")
    if NotifyInspect then NotifyInspect(unit) end
    self._inspectRetryCount = 0
    C_Timer.After(0, function()
      if InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and UnitExists(InspectFrame.unit) then
        self:UpdateDisplay()
      end
    end)
  end
  if event == "INSPECT_READY" then
    if InspectFrame and InspectFrame:IsShown() then
      local unit = self.inspectUnit or (InspectFrame and InspectFrame.unit)
      if UnitExists(unit) then
        self.inspectUnit = unit
      end
    end
    self:InvalidateRenderCache("inspect")
  end
  if event == "GET_ITEM_INFO_RECEIVED" then
    local itemId = ...
    if self.pendingInspect and itemId and self.pendingInspect[itemId] then
      self.pendingInspect[itemId] = nil
    end
    local relevant = false
    for _, scope in ipairs({ "player", "inspect" }) do
      for slotId, items in pairs(self[scope .. "SlotItems"] or {}) do
        if items[itemId] then
          local cache = self[scope .. "SlotCache"]
          if cache then cache[slotId] = nil end
          relevant = true
        end
      end
    end
    if not relevant or self._itemUpdateQueued then return end
    self._itemUpdateQueued = true
    C_Timer.After(0.1, function()
      self._itemUpdateQueued = nil
      if self.db and self.db.enabled then self:UpdateDisplay() end
    end)
    return
  end
  if event == "KALDOTV_INSPECTFRAME_OPENED" or event == "INSPECT_READY" then
    self:UpdateDisplay()
    return
  end

  local now = GetTime()
  if now - (self.lastUpdate or 0) > 1 then
    self.lastUpdate = now
    self:UpdateDisplay()
  end
end

Kaldo:RegisterModule("EquipmentInfo", M)

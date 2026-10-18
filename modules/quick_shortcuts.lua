-- modules/quick_shortcuts.lua
local _, NS = ...
local Kaldo, L, DB = NS.Kaldo, NS.L, NS.DB
local MacroUtils = NS.MacroUtils

local M = {}
M.displayName = (L and L.QUICK_SHORTCUTS) or "Quick shortcuts"
M.events = {
  "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
  "NEW_TOY_ADDED", "TOYS_UPDATED", "COMPANION_LEARNED", "MOUNT_JOURNAL_USABILITY_CHANGED",
  "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
}

local SPOREBEARER = 1313788
local REPAIR_MOUNTS = { yak = 122708, bear = 457485, hearthkeeper = 142515, sporebearer = SPOREBEARER }
local AH_MOUNTS = { caravan = 264058, gilded = 465235, sporebearer = SPOREBEARER }
local ARCANTINA_TOY = 253629
local ASTRAL_RECALL = 556
local MAGE_SILVERMOON = { teleport = 1259190, portal = 1259194 } -- Midnight
local HEARTHSTONE_TOYS = {
  263933, 264367, 265100, 245970, 246565, 257736, 235016, 54452, 64488,
  93672, 162973, 163045, 165669, 165670, 165802, 166746, 166747, 168907,
  172179, 188952, 190196, 190237, 193588, 200630, 206195, 208704, 209035,
  212337, 228940, 236687, 263489, 210455, 184353, 183716, 180290, 182773,
}
local defaults = {
  enabled = false,
  notify = true,
  create_macros = false,
  repair_selected = {},
  auction_selected = {},
  hearth_random = true,
  hearth_selected = {},
  hearth_mage = false,
  hearth_astral = true,
  hearth_arcantina = true,
  repair_macro_name = "KaldoRepairMt",
  auction_macro_name = "KaldoBruto",
  hearth_macro_name = "KaldoHearth",
  bindings = { repair = "", auction = "", hearth = "" },
}

local function knownSpell(spellID)
  return (IsSpellKnown and IsSpellKnown(spellID)) or (IsPlayerSpell and IsPlayerSpell(spellID))
    or (C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(spellID))
end

local function learnedMounts(spells, selected)
  local found = {}
  if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return found end
  local wanted = {}
  for key, spellID in pairs(spells) do wanted[spellID] = key end
  for _, mountID in ipairs(C_MountJournal.GetMountIDs() or {}) do
    local _, spellID, _, _, _, _, _, _, _, hideForCharacter, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    local key = wanted[spellID]
    if key and not hideForCharacter and (isCollected or knownSpell(spellID))
      and (not selected or selected[key]) then found[#found + 1] = spellID end
  end
  table.sort(found)
  return found
end

local function hasToy(itemID)
  if PlayerHasToy then return PlayerHasToy(itemID) end
  return C_ToyBox and C_ToyBox.PlayerHasToy and C_ToyBox.PlayerHasToy(itemID) or false
end

local function hearthstoneToyItems()
  local found, seen = {}, {}
  local function addIfAvailable(itemID)
    if seen[itemID] then return end
    local available = itemID == 6948 or hasToy(itemID)
    if available and itemID ~= 6948 and C_ToyBox and C_ToyBox.IsToyUsable then
      local usable = C_ToyBox.IsToyUsable(itemID)
      if issecretvalue and issecretvalue(usable) then usable = nil end
      if usable == false then available = false end
    end
    if available then seen[itemID] = true; found[#found + 1] = itemID end
  end

  addIfAvailable(6948)
  for _, itemID in ipairs(HEARTHSTONE_TOYS) do addIfAvailable(itemID) end
  table.sort(found)
  return found
end

local function listMacro(ids, command, random)
  if #ids == 0 then return nil end
  local tokens = {}
  for _, id in ipairs(ids) do
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    tokens[#tokens + 1] = name or tostring(id)
  end
  if random and #ids > 1 then
    return "#showtooltip\n/castrandom " .. table.concat(tokens, ",")
  end
  return "#showtooltip " .. tokens[1] .. "\n" .. command .. " " .. tokens[1]
end

function M:EnsureDB()
  local db = DB:EnsureModuleState("QuickShortcuts", defaults)
  -- Migrate fixed/random choices once, including mounts not yet collected.
  for category, mounts in pairs({ repair = REPAIR_MOUNTS, auction = AH_MOUNTS }) do
    local field, legacy = category .. "_selected", category .. "_mode"
    if type(db[field]) ~= "table" then db[field] = {} end
    for key in pairs(mounts) do
      if db[field][key] == nil then
        db[field][key] = key ~= "sporebearer" and
          (db[legacy] == nil or db[legacy] == "random" or db[legacy] == key)
      end
    end
    db[legacy] = nil
  end
  return db
end

function M:GetOptions()
  self:EnsureDB()
  local options = {
    { type="header", text=(L and L.QUICK_SHORTCUTS_MOUNTS) or "Utility mounts" },
    { type="keybind", key="bindings.repair", buttonName="KaldoQuickRepairButton", label=(L and L.QUICK_SHORTCUTS_BIND_REPAIR) or "Repair mount shortcut" },
    { type="keybind", key="bindings.auction", buttonName="KaldoQuickAuctionButton", label=(L and L.QUICK_SHORTCUTS_BIND_AUCTION) or "Auction mount shortcut" },
  }
  local mountLabels = {
    yak = (L and L.QUICK_SHORTCUTS_YAK) or "Grand Expedition Yak",
    bear = (L and L.QUICK_SHORTCUTS_BEAR) or "Grizzly Hills Packmaster",
    hearthkeeper = (L and L.QUICK_SHORTCUTS_HEARTHKEEPER) or "Hearthkeeper's Wandering Caravan",
    caravan = (L and L.QUICK_SHORTCUTS_OLD_BRUTO) or "Mighty Caravan Brutosaur",
    gilded = (L and L.QUICK_SHORTCUTS_GILDED_BRUTO) or "Trader's Gilded Brutosaur",
    sporebearer = (L and L.QUICK_SHORTCUTS_SPOREBEARER) or "Sporebearer Fungal Strider",
  }
  for _, category in ipairs({ "repair", "auction" }) do
    local mounts = category == "repair" and REPAIR_MOUNTS or AH_MOUNTS
    options[#options + 1] = { type="label", text=category == "repair" and
      ((L and L.QUICK_SHORTCUTS_REPAIR_MODE) or "Repair mount") or
      ((L and L.QUICK_SHORTCUTS_AUCTION_MODE) or "Auction house mount") }
    options[#options + 1] = { type="label", text=(L and L.QUICK_SHORTCUTS_MOUNT_LIST_HINT) or "Randomly choose from checked mounts. Uncheck all to disable this shortcut." }
    for _, spellID in ipairs(learnedMounts(mounts)) do
      for key, id in pairs(mounts) do
        if id == spellID then
          options[#options + 1] = { type="toggle", key=category .. "_selected." .. key,
            label=mountLabels[key], tooltip=key == "sporebearer" and
              ((L and L.QUICK_SHORTCUTS_SPOREBEARER_HINT) or "Enable only if the matching NPC is assigned to this mount.") or nil }
        end
      end
    end
    options[#options + 1] = { type="input", key=category .. "_macro_name", label=category == "repair" and
      ((L and L.QUICK_SHORTCUTS_REPAIR_MACRO) or "Repair macro name") or
      ((L and L.QUICK_SHORTCUTS_AUCTION_MACRO) or "Auction macro name") }
  end
  local hearthOptions = {
    { type="header", text=(L and L.QUICK_SHORTCUTS_HEARTH) or "Hearthstone" },
    { type="keybind", key="bindings.hearth", buttonName="KaldoQuickHearthButton", label=(L and L.QUICK_SHORTCUTS_BIND_HEARTH) or "Hearthstone shortcut" },
    { type="toggle", key="hearth_mage", label=(L and L.QUICK_SHORTCUTS_MAGE_PRIORITY) or "Mage: Silvermoon City (Midnight) first (Teleport solo / Portal in a group)" },
    { type="toggle", key="hearth_random", label=(L and L.QUICK_SHORTCUTS_HEARTH_RANDOM) or "Randomly choose from checked hearthstones" },
    { type="toggle", key="hearth_astral", label=(L and L.QUICK_SHORTCUTS_ASTRAL) or "Shaman Astral Recall fallback" },
    { type="toggle", key="hearth_arcantina", label=(L and L.QUICK_SHORTCUTS_ARCANTINA) or "Personal Key to the Arcantina fallback" },
    { type="input", key="hearth_macro_name", label=(L and L.QUICK_SHORTCUTS_HEARTH_MACRO) or "Hearthstone macro name" },
    { type="header", text=(L and L.QUICK_SHORTCUTS_HEARTH_LIST) or "Included hearthstones" },
    { type="label", text=(L and L.QUICK_SHORTCUTS_HEARTH_LIST_HINT) or "Choose which collected hearthstone toys may be used." },
  }
  for _, option in ipairs(hearthOptions) do options[#options + 1] = option end
  local names = { [6948] = (L and L.QUICK_SHORTCUTS_HOME_HEARTH) or "Hearthstone" }
  for _, itemID in ipairs(hearthstoneToyItems()) do
    local name
    if C_ToyBox and C_ToyBox.GetToyInfo then _, name = C_ToyBox.GetToyInfo(itemID) end
    if not name and C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(itemID) end
    options[#options + 1] = {
      type="toggle", key="hearth_selected." .. tostring(itemID),
      label=itemID == 6948 and names[itemID] or name or ("Item " .. tostring(itemID)),
    }
  end
  options[#options + 1] = { type="header", text=(L and L.QUICK_SHORTCUTS_MISC) or "Miscellaneous" }
  options[#options + 1] = { type="toggle", key="create_macros", label=(L and L.QUICK_SHORTCUTS_CREATE_MACROS) or "Also create optional macros" }
  options[#options + 1] = { type="toggle", key="notify", label=(L and L.QUICK_SHORTCUTS_NOTIFY) or "Notify macro updates" }
  return options
end

function M:OnRegister()
  self.db = self:EnsureDB()
  self.last = {}
  self.buttons = {
    repair = CreateFrame("Button", "KaldoQuickRepairButton", UIParent, "SecureActionButtonTemplate"),
    auction = CreateFrame("Button", "KaldoQuickAuctionButton", UIParent, "SecureActionButtonTemplate"),
    hearth = CreateFrame("Button", "KaldoQuickHearthButton", UIParent, "SecureActionButtonTemplate"),
  }
  self.bindingOwner = CreateFrame("Frame", "KaldoQuickShortcutsBindingOwner", UIParent, "SecureFrameTemplate")
  for action, button in pairs(self.buttons) do
    button:SetSize(1, 1)
    button:SetPoint("CENTER", UIParent, "CENTER", 0, -10000)
    button:SetAlpha(0)
    button:EnableMouse(false)
    button:RegisterForClicks("AnyDown")
    if action ~= "hearth" then
      button:SetAttribute("type", "macro")
      button:SetAttribute("type1", "macro")
    end
    button:SetAttribute("pressAndHoldAction", true)
    button:Show()
  end
  self.buttons.hearth:SetScript("PreClick", function(button)
    self:PrepareHearthAction(button)
  end)
end

local function selectedHearthstones(db)
  local selected = {}
  for _, itemID in ipairs(hearthstoneToyItems()) do
    if db.hearth_selected[tostring(itemID)] ~= false then selected[#selected + 1] = itemID end
  end
  return selected
end

local function cooldownReady(startTime, duration, enabled, modRate)
  if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)
    or issecretvalue(enabled) or issecretvalue(modRate)) then return false end
  if enabled == false or enabled == 0 then return false end
  if type(startTime) ~= "number" or type(duration) ~= "number" then return false end
  if startTime == 0 or duration == 0 then return true end
  return startTime + duration / (modRate or 1) <= GetTime()
end

local function itemReady(itemID)
  if itemID == 6948 then
    local getCount = C_Item and C_Item.GetItemCount or GetItemCount
    if not getCount then return false end
    local count = getCount(itemID)
    if issecretvalue and issecretvalue(count) then return false end
    if not count or count <= 0 then return false end
    local isUsable = C_Item and C_Item.IsUsableItem or IsUsableItem
    if isUsable then
      local usable = isUsable(itemID)
      if issecretvalue and issecretvalue(usable) then return false end
      if usable == false then return false end
    end
  else
    if not hasToy(itemID) then return false end
    if C_ToyBox and C_ToyBox.IsToyUsable then
      local usable = C_ToyBox.IsToyUsable(itemID)
      if issecretvalue and issecretvalue(usable) then return false end
      if usable == false then return false end
    end
  end
  local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
  if not getCooldown then return false end
  return cooldownReady(getCooldown(itemID))
end

local function spellReady(spellID)
  if not knownSpell(spellID) then return false end
  local isUsable = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
  if isUsable then
    local usable = isUsable(spellID)
    if issecretvalue and issecretvalue(usable) then return false end
    if usable == false then return false end
  end
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then return false end
    return cooldownReady(info.startTime, info.duration, info.isEnabled, info.modRate)
  elseif GetSpellCooldown then
    return cooldownReady(GetSpellCooldown(spellID))
  end
  return false
end

local function astralRecallReady(db)
  return db.hearth_astral and select(2, UnitClass("player")) == "SHAMAN" and spellReady(ASTRAL_RECALL)
end

local function magePrioritySpell(db)
  if db.hearth_mage ~= true then return nil end
  if select(2, UnitClass("player")) ~= "MAGE" then return nil end
  local spellID = IsInGroup and IsInGroup() and MAGE_SILVERMOON.portal or MAGE_SILVERMOON.teleport
  if spellID and spellReady(spellID) then return spellID end
end

local function chooseHearthstone(db)
  local choices = {}
  for _, itemID in ipairs(selectedHearthstones(db)) do
    if itemReady(itemID) then choices[#choices + 1] = itemID end
  end
  if #choices == 0 then return nil end
  if db.hearth_random and #choices > 1 then return choices[math.random(#choices)] end
  return choices[1]
end

function M:BuildHearthMacro()
  -- Click a direct item/toy/spell action so the macro uses the same selection
  -- as the keybind without chaining another macro.
  return "#showtooltip item:6948\n/click KaldoQuickHearthButton LeftButton 1"
end

function M:PrepareHearthAction(button)
  if InCombatLockdown and InCombatLockdown() then return end
  local db = self.db or self:EnsureDB()
  local actionType, itemID, spellID
  if db.enabled then
    spellID = magePrioritySpell(db)
    if not spellID then itemID = chooseHearthstone(db) end
    if spellID then
      actionType = "spell"
    elseif itemID then
      actionType = itemID == 6948 and "item" or "toy"
    elseif astralRecallReady(db) then
      actionType, spellID = "spell", ASTRAL_RECALL
    elseif db.hearth_arcantina and itemReady(ARCANTINA_TOY) then
      actionType, itemID = "toy", ARCANTINA_TOY
    end
  end
  button:SetAttribute("type", actionType)
  button:SetAttribute("type1", actionType)
  button:SetAttribute("item", actionType == "item" and ("item:" .. tostring(itemID)) or nil)
  button:SetAttribute("toy", actionType == "toy" and itemID or nil)
  button:SetAttribute("spell", spellID)
end

function M:Apply(name, body)
  if not body or #body > 255 or self.last[name] == body then return end
  local ok, action = MacroUtils.CreateOrUpdateMacro(name, body)
  if ok then
    self.last[name] = body
    if self.db.notify and DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cff7fd1ffKaldo Tweaks:|r " .. string.format(
        action == "created" and ((L and L.AUTO_MACROS_CREATED_FMT) or "Macro '%s' created.")
          or ((L and L.AUTO_MACROS_UPDATED_FMT) or "Macro '%s' updated."), name))
    end
  end
end

function M:UpdateMacros()
  local db = self:EnsureDB()
  if not db.enabled then
    if InCombatLockdown and InCombatLockdown() then self.pending = true; return end
    if ClearOverrideBindings then ClearOverrideBindings(self.bindingOwner) end
    for _, button in pairs(self.buttons) do
      button:SetAttribute("type", nil)
      button:SetAttribute("type1", nil)
      button:SetAttribute("macrotext", nil)
      button:SetAttribute("macrotext1", nil)
    end
    return
  end
  local repair = learnedMounts(REPAIR_MOUNTS, db.repair_selected)
  local auction = learnedMounts(AH_MOUNTS, db.auction_selected)
  local repairBody = listMacro(repair, "/cast", true)
  local auctionBody = listMacro(auction, "/cast", true)

  if InCombatLockdown and InCombatLockdown() then self.pending = true; return end
  local function setSecure(button, body)
    button:SetAttribute("type", body and "macro" or nil)
    button:SetAttribute("type1", body and "macro" or nil)
    button:SetAttribute("macrotext", body)
    button:SetAttribute("macrotext1", body)
  end
  setSecure(self.buttons.repair, repairBody)
  setSecure(self.buttons.auction, auctionBody)
  self:PrepareHearthAction(self.buttons.hearth)
  if ClearOverrideBindings then ClearOverrideBindings(self.bindingOwner) end
  if SetOverrideBindingClick then
    local bindings = db.bindings or {}
    for action, buttonName in pairs({
      repair = "KaldoQuickRepairButton",
      auction = "KaldoQuickAuctionButton",
      hearth = "KaldoQuickHearthButton",
    }) do
      local key = bindings[action]
      if key and key ~= "" then SetOverrideBindingClick(self.bindingOwner, true, key, buttonName, "LeftButton") end
    end
  end
  if db.create_macros then
    self:Apply(MacroUtils.NormalizeMacroName(db.repair_macro_name, "KaldoRepairMt"), repairBody or "#showtooltip")
    self:Apply(MacroUtils.NormalizeMacroName(db.auction_macro_name, "KaldoBruto"), auctionBody or "#showtooltip")
    self:Apply(MacroUtils.NormalizeMacroName(db.hearth_macro_name, "KaldoHearth"), self:BuildHearthMacro())
  end
end

function M:QueueUpdate()
  if InCombatLockdown and InCombatLockdown() then self.pending = true; return end
  self.pending = false
  self:UpdateMacros()
end

function M:OnOptionChanged()
  self.db = self:EnsureDB()
  self:QueueUpdate()
end

function M:OnEvent(event)
  if event == "PLAYER_REGEN_ENABLED" and not self.pending then return end
  self.db = self:EnsureDB()
  self:QueueUpdate()
end

function M:GetBindingMacros()
  return {
    { name="KALDO_QUICK_REPAIR", label=(L and L.QUICK_SHORTCUTS_BIND_REPAIR) or "Repair mount" },
    { name="KALDO_QUICK_AUCTION", label=(L and L.QUICK_SHORTCUTS_BIND_AUCTION) or "Auction mount" },
    { name="KALDO_QUICK_HEARTH", label=(L and L.QUICK_SHORTCUTS_BIND_HEARTH) or "Hearthstone" },
  }
end

Kaldo:RegisterModule("QuickShortcuts", M)

-- modules/mm_keys.lua
local ADDON_NAME, NS = ...
local Kaldo = NS.Kaldo
local L = NS.L
local DB = NS.DB
local MacroUtils = NS.MacroUtils

local M = {}
local tryHookChallengesFrame
local tryHookCommunitiesFrame
local ensureChallengesUILoaded
local isLikelySeasonBestButton
local isLikelySeasonBestFallbackButton
local refreshScorePercentileOverlay
M.displayName = (L and L.MM_KEYS) or "MM+ Keys"
M.events = {
  "PLAYER_LOGIN",
  "ADDON_LOADED",
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "GROUP_LEFT",
  "PLAYER_ROLES_ASSIGNED",
  "PARTY_LEADER_CHANGED",
  "PLAYER_SPECIALIZATION_CHANGED",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "CHALLENGE_MODE_START",
  "CHALLENGE_MODE_COMPLETED",
  "CHALLENGE_MODE_RESET",
  "CHALLENGE_MODE_MAPS_UPDATE",
  "SPELLS_CHANGED",
  "READY_CHECK",
  "READY_CHECK_CONFIRM",
  "READY_CHECK_FINISHED",
  "LFG_LIST_APPLICATION_STATUS_UPDATED",
  "LFG_LIST_JOINED_GROUP",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local C_MythicPlus = C_MythicPlus or {}

-- Keystone item IDs (historical + current)
local KEYSTONE_ITEM_IDS = {
  [138019] = true, -- Legion (older)
  [151086] = true, -- Legion (older)
  [158923] = true, -- BFA
  [180653] = true, -- SL/DF/TWW
}

-- Fill this table with your preferred dungeon acronyms keyed by mapChallengeModeID.
local DUNGEON_ACRONYMS = {
  -- Midnight Season 2
  [249] = "KR",
  [250] = "TOS",
  [399] = "RLP",
  [584] = "BV",
  [585] = "VSA",
  [586] = "DON",
  [587] = "MR",
  [588] = "AOF",

  -- Midnight Season 1
  [402] = "AA",
  [556] = "POS",
  [558] = "MT",
  [161] = "SR",
  [557] = "WS",
  [559] = "NPX",
  [560] = "MC",
  [239] = "SEAT",
}

local DUNGEON_TELEPORT_SPELLS = {
  -- Midnight Season 2
  [249] = 1286831, -- King's Rest
  [250] = 1286828, -- Temple of Sethraliss
  [399] = 393256, -- Ruby Life Pools
  [584] = 1286801, -- The Blinding Vale
  [585] = 1286804, -- Voidscar Arena
  [586] = 1286807, -- Den of Nalorakk
  [587] = 1286809, -- Murder Row
  [588] = 1286812, -- Altar of Fangs

  -- Midnight Season 1
  [161] = 159898, -- Skyreach
  [239] = 1254551, -- Seat of the Triumvirate
  [402] = 393273, -- Algeth'ar Academy
  [556] = 1254555, -- Pit of Saron
  [557] = 1254400, -- Windrunner Spire
  [558] = 1254572, -- Magisters' Terrace
  [559] = 1254563, -- Nexus-Point Xenas
  [560] = 1254559, -- Maisara Caverns
}

local FOCUS_KICK_MACRO_NAME = "KaldoFocusKick"
local FOCUS_KICK_MARKERS = {
  { name = "Star", label = "MM_KEYS_MARKER_STAR" },
  { name = "Circle", label = "MM_KEYS_MARKER_CIRCLE" },
  { name = "Diamond", label = "MM_KEYS_MARKER_DIAMOND" },
  { name = "Triangle", label = "MM_KEYS_MARKER_TRIANGLE" },
  { name = "Moon", label = "MM_KEYS_MARKER_MOON" },
  { name = "Square", label = "MM_KEYS_MARKER_SQUARE" },
  { name = "Cross", label = "MM_KEYS_MARKER_CROSS" },
  { name = "Skull", label = "MM_KEYS_MARKER_SKULL" },
}

local function getFocusKickMarker(icon)
  local index = tonumber(icon)
  if not index or index % 1 ~= 0 or not FOCUS_KICK_MARKERS[index] then index = 6 end
  return index, FOCUS_KICK_MARKERS[index]
end

local function getFocusKickMarkerOptions()
  local values = {}
  for index, marker in ipairs(FOCUS_KICK_MARKERS) do
    values[#values + 1] = { index, string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16:16|t %s",
      index, L[marker.label] or marker.name) }
  end
  return values
end

-- Edit these rules directly in code. Highest matching minLevel wins.
local KEY_LEVEL_COLOR_RULES = {
  { minLevel = 12, color = { 0.85, 0.60, 1.00, 1.00 } },
  { minLevel = 10, color = { 0.29, 0.95, 0.55, 1.00 } },
  { minLevel = 0, color = { 1.00, 0.95, 0.84, 1.00 } },
}

local DEFAULT_OVERLAY_FONT = "Fonts\\FRIZQT__.TTF"
local GUILD_DUNGEON_SCORE_COLUMN_INDEX = 5
local CURRENT_MM_SEASON_START = { year = 2026, month = 8, day = 19, hour = 0, min = 0, sec = 0 }

local defaults = {
  enabled = false,
  auto_insert = true,
  respond_keys = true,
  hide_stale_guild_scores = true,
  accept_reminder_chat = true,
  accept_reminder_screen = false,
  accept_teleport_prompt = true,
  focus_kick_enabled = false,
  focus_kick_icon = 6,
  season_best_overlay = true,
  score_percentiles = true,
  score_color = { 1.00, 0.82, 0.00, 1.00 },
  timer_color_in_time = { 0.82, 0.92, 1.00, 1.00 },
  timer_color_over_time = { 1.00, 0.43, 0.43, 1.00 },
  acronym_font = DEFAULT_OVERLAY_FONT,
  acronym_size = 11,
  level_font = DEFAULT_OVERLAY_FONT,
  level_size = 18,
  score_font = DEFAULT_OVERLAY_FONT,
  score_size = 11,
  timer_font = DEFAULT_OVERLAY_FONT,
  timer_size = 10,
}

local BUILTIN_MM_PERCENTILES = {
  source = "Raider.IO fallback",
  season = "season-mn-2",
  regions = {
    eu = {
      points = {
        { score = 3178, topPercent = 0.100 },
        { score = 3005, topPercent = 1.000 },
        { score = 2915, topPercent = 2.100 },
        { score = 2676, topPercent = 10.000 },
        { score = 2558, topPercent = 18.700 },
        { score = 2368, topPercent = 25.000 },
        { score = 2199, topPercent = 31.200 },
        { score = 1898, topPercent = 40.000 },
        { score = 1475, topPercent = 49.900 },
        { score = 1238, topPercent = 56.200 },
        { score = 999, topPercent = 62.300 },
        { score = 0, topPercent = 100.000 },
      },
    },
    world = {
      points = {
        { score = 3178, topPercent = 0.100 },
        { score = 3005, topPercent = 0.741 },
        { score = 2915, topPercent = 1.566 },
        { score = 2824, topPercent = 3.865 },
        { score = 2676, topPercent = 7.849 },
        { score = 2642, topPercent = 10.148 },
        { score = 2619, topPercent = 11.628 },
        { score = 2558, topPercent = 15.094 },
        { score = 2368, topPercent = 21.040 },
        { score = 2199, topPercent = 26.865 },
        { score = 1898, topPercent = 35.500 },
        { score = 1680, topPercent = 40.487 },
        { score = 1475, topPercent = 45.954 },
        { score = 1237, topPercent = 52.680 },
        { score = 999, topPercent = 59.204 },
        { score = 0, topPercent = 100.000 },
      },
    },
  },
}

local function chatLine(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd1ffKaldo Tweaks:|r " .. tostring(message))
  end
end

local function applyDefaults(db)
  DB:ApplyDefaults(db, defaults)
end

function M:EnsureDB()
  return DB:EnsureModuleState("MMKeys", defaults)
end

function M:ResetDB()
  self.db = DB:ResetModuleState("MMKeys", defaults)
  self:ClearAcceptedGroupState()
  self:UpdateFocusKickMacro()
end

local function getKeystoneLinkFromBags()
  if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
  for bag = 0, NUM_BAG_FRAMES do
    local slots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and KEYSTONE_ITEM_IDS[info.itemID] then
        local link = C_Container.GetContainerItemLink(bag, slot)
        if link then return link end
      end
    end
  end
  return nil
end

local function getOwnedKeystoneLink()
  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLink then
    local link = C_MythicPlus.GetOwnedKeystoneLink()
    if link then return link end
  end
  return getKeystoneLinkFromBags()
end

local function normalizeMsg(msg)
  if type(msg) ~= "string" then return nil end
  msg = msg:lower()
  msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
  return msg
end

local function shouldSuppressKeysChat()
  if InCombatLockdown and InCombatLockdown() then
    return true
  end

  if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
    return true
  end

  local currentRunID = C_MythicPlus.GetCurrentRunID and C_MythicPlus.GetCurrentRunID()
  if currentRunID then
    return true
  end

  if GetInstanceInfo then
    local _, instanceType = GetInstanceInfo()
    if instanceType == "pvp" or instanceType == "arena" then
      return true
    end
  end

  return false
end

local function isKeysCommand(msg)
  if shouldSuppressKeysChat() then return end
  if type(msg) ~= "string" then return false end
  if msg:find("|", 1, true) or msg:find("[%c\r\n]") then
    return false
  end
  msg = normalizeMsg(msg)
  if not msg or #msg > 5 then
    return false
  end
  return msg == "!key" or msg == "!keys"
end

local function isTrustedKeysSender(author)
  return type(author) == "string" and author ~= ""
end

local guildScoreFilterUnsafe = false

local function isGuildScoreFilterBlocked()
  return shouldSuppressKeysChat() == true
end

local function isGuildScoreFilterEnabled(db)
  return db and db.enabled and db.hide_stale_guild_scores and not isGuildScoreFilterBlocked()
end

local function safeGuildScoreCall(fn, ...)
  if guildScoreFilterUnsafe then return false end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then
    guildScoreFilterUnsafe = true
    return false
  end
  return true, a, b, c, d
end

local function getCurrentMMSeasonStartTime()
  if not time then return nil end
  return time({
    year = CURRENT_MM_SEASON_START.year,
    month = CURRENT_MM_SEASON_START.month,
    day = CURRENT_MM_SEASON_START.day,
    hour = CURRENT_MM_SEASON_START.hour,
    min = CURRENT_MM_SEASON_START.min,
    sec = CURRENT_MM_SEASON_START.sec,
  })
end

local function getApproxOfflineSeconds(memberInfo)
  if type(memberInfo) ~= "table" then return nil end
  local ok, years, months, days, hours = safeGuildScoreCall(function()
    if not memberInfo.lastOnlineYear then return nil end
    return tonumber(memberInfo.lastOnlineYear) or 0,
      tonumber(memberInfo.lastOnlineMonth) or 0,
      tonumber(memberInfo.lastOnlineDay) or 0,
      tonumber(memberInfo.lastOnlineHour) or 0
  end)
  if not ok or not years then return nil end
  return ((((years * 12) + months) * 30 + days) * 24 + hours) * 3600
end

local function shouldHideGuildDungeonScore(memberInfo, db)
  if guildScoreFilterUnsafe then return false end
  if not isGuildScoreFilterEnabled(db) then return false end
  if type(memberInfo) ~= "table" then return false end
  local ok, score, presence = safeGuildScoreCall(function()
    return tonumber(memberInfo.KaldoOriginalOverallDungeonScore or memberInfo.overallDungeonScore), memberInfo.presence
  end)
  if not ok or not score then return false end
  local isOfflineOk, isOffline = safeGuildScoreCall(function()
    return Enum and Enum.ClubMemberPresence and presence == Enum.ClubMemberPresence.Offline
  end)
  if not isOfflineOk or not isOffline then return false end

  local seasonStart = getCurrentMMSeasonStartTime()
  local now = GetServerTime and GetServerTime() or (time and time()) or nil
  if not seasonStart or not now or now <= seasonStart then return false end

  local offlineSeconds = getApproxOfflineSeconds(memberInfo)
  if not offlineSeconds then return false end
  return (now - offlineSeconds) < seasonStart
end

local function applyGuildDungeonScoreFilterToMember(memberInfo, db)
  if guildScoreFilterUnsafe then return end
  if type(memberInfo) ~= "table" then return end
  local restored = safeGuildScoreCall(function()
    if memberInfo.KaldoOriginalOverallDungeonScore ~= nil then
      memberInfo.overallDungeonScore = memberInfo.KaldoOriginalOverallDungeonScore
      memberInfo.KaldoOriginalOverallDungeonScore = nil
    end
  end)
  if not restored then return end

  if shouldHideGuildDungeonScore(memberInfo, db) then
    safeGuildScoreCall(function()
      memberInfo.KaldoOriginalOverallDungeonScore = memberInfo.overallDungeonScore
      memberInfo.overallDungeonScore = nil
    end)
  end
end

local function applyGuildDungeonScoreFilter(memberList, db)
  if guildScoreFilterUnsafe then return end
  local seen = {}
  local function applyList(list)
    if type(list) ~= "table" then return end
    local ok, count = safeGuildScoreCall(function() return #list end)
    if not ok then return end
    for index = 1, count do
      local memberOk, memberInfo = safeGuildScoreCall(function() return list[index] end)
      if not memberOk then return end
      if type(memberInfo) == "table" and not seen[memberInfo] then
        seen[memberInfo] = true
        applyGuildDungeonScoreFilterToMember(memberInfo, db)
      end
    end
  end
  applyList(memberList and memberList.allMemberList)
  applyList(memberList and memberList.sortedMemberList)
end

local function getGuildDungeonSortScore(memberInfo, db)
  if guildScoreFilterUnsafe then return 0 end
  if shouldHideGuildDungeonScore(memberInfo, db) then
    return 0
  end
  local ok, score = safeGuildScoreCall(function()
    return tonumber(memberInfo and memberInfo.overallDungeonScore)
  end)
  if ok and score then return score end
  return 0
end

local function isGuildDungeonScoreSort(memberList, columnIndex)
  if guildScoreFilterUnsafe then return false end
  local ok, isScoreColumn = safeGuildScoreCall(function()
    return memberList and memberList.GetGuildColumnIndex and memberList:GetGuildColumnIndex() == GUILD_DUNGEON_SCORE_COLUMN_INDEX
  end)
  if not ok or not isScoreColumn then return false end

  local columnOk, isSortableExtraColumn = safeGuildScoreCall(function()
    return memberList.columnInfo and columnIndex and columnIndex > #memberList.columnInfo
  end)
  return columnOk and isSortableExtraColumn
end

local function applyGuildDungeonScoreSort(memberList, db)
  if guildScoreFilterUnsafe then return end
  if type(memberList and memberList.sortedMemberList) ~= "table" then return end
  safeGuildScoreCall(table.sort, memberList.sortedMemberList, function(lhs, rhs)
    if memberList.reverseActiveColumnSort then
      lhs, rhs = rhs, lhs
    end
    return getGuildDungeonSortScore(lhs, db) < getGuildDungeonSortScore(rhs, db)
  end)
end

function M:RefreshGuildRosterScores()
  if guildScoreFilterUnsafe then return end
  if isGuildScoreFilterBlocked() then return end
  if not (CommunitiesFrame and CommunitiesFrame.MemberList and CommunitiesFrame.MemberList.RefreshListDisplay) then return end
  local memberList = CommunitiesFrame.MemberList
  applyGuildDungeonScoreFilter(memberList, self.db or self:EnsureDB())
  local ok, isScoreColumn = safeGuildScoreCall(function()
    return memberList.GetGuildColumnIndex and memberList:GetGuildColumnIndex() == GUILD_DUNGEON_SCORE_COLUMN_INDEX
  end)
  if ok and isScoreColumn then
    local activeColumnSortIndex
    safeGuildScoreCall(function() activeColumnSortIndex = memberList.activeColumnSortIndex end)
    if activeColumnSortIndex and isGuildDungeonScoreSort(memberList, activeColumnSortIndex) then
      applyGuildDungeonScoreSort(memberList, self.db or self:EnsureDB())
    end
    safeGuildScoreCall(memberList.RefreshListDisplay, memberList)
  end
end

function M:UpdateGuildScoreFilterButton()
  local button = self._guildScoreFilterButton
  if not button then return end
  local db = self.db or self:EnsureDB()
  local blocked = isGuildScoreFilterBlocked()
  button:SetChecked(db.hide_stale_guild_scores == true)
  button:SetEnabled(not blocked)
  if button.Text then
    local offlineText = CommunitiesFrame and CommunitiesFrame.MemberList and CommunitiesFrame.MemberList.ShowOfflineButton
    offlineText = offlineText and offlineText.Text
    if blocked then
      button.Text:SetTextColor(0.5, 0.5, 0.5)
    elseif offlineText and offlineText.GetTextColor then
      button.Text:SetTextColor(offlineText:GetTextColor())
    else
      button.Text:SetTextColor(1, 1, 1)
    end
  end
end

function M:CreateGuildScoreFilterButton()
  local memberList = CommunitiesFrame and CommunitiesFrame.MemberList
  local offlineButton = memberList and memberList.ShowOfflineButton
  if not offlineButton or self._guildScoreFilterButton then return end

  local button = CreateFrame("CheckButton", nil, memberList, "UICheckButtonTemplate")
  local width, height = offlineButton:GetSize()
  button:SetSize(width > 0 and width or 20, height > 0 and height or 20)
  if offlineButton.Text then
    button:SetPoint("LEFT", offlineButton.Text, "RIGHT", 8, 0)
    local font, fontSize, fontFlags = offlineButton.Text:GetFont()
    if font then button.Text:SetFont(font, fontSize, fontFlags) end
  else
    button:SetPoint("LEFT", offlineButton, "RIGHT", 8, 0)
  end
  button.Text:SetText((L and L.MM_KEYS_HIDE_PREVIOUS_SEASONS) or "Hide previous seasons")
  button:SetScript("OnClick", function(clicked)
    if isGuildScoreFilterBlocked() then
      clicked:SetChecked((self.db or self:EnsureDB()).hide_stale_guild_scores == true)
      return
    end
    local db = self.db or self:EnsureDB()
    db.hide_stale_guild_scores = clicked:GetChecked() == true
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    self:RefreshGuildRosterScores()
  end)
  button:SetScript("OnEnter", function(clicked)
    if not isGuildScoreFilterBlocked() or not GameTooltip then return end
    GameTooltip:SetOwner(clicked, "ANCHOR_RIGHT")
    GameTooltip:SetText((L and L.MM_KEYS_GUILD_FILTER_BLOCKED) or "Unavailable during combat, Mythic+ and PvP.", 1, 0.82, 0, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  button:SetScript("OnShow", function() self:UpdateGuildScoreFilterButton() end)
  offlineButton:HookScript("OnShow", function() button:Show() end)
  offlineButton:HookScript("OnHide", function() button:Hide() end)
  button:SetShown(offlineButton:IsShown())
  self._guildScoreFilterButton = button
  self:UpdateGuildScoreFilterButton()
end

tryHookCommunitiesFrame = function(self)
  if not (CommunitiesMemberListMixin and CommunitiesMemberListEntryMixin and hooksecurefunc) then return end

  self:CreateGuildScoreFilterButton()

  local function afterSortByColumnIndex(memberList, columnIndex)
    if guildScoreFilterUnsafe then return end
    if isGuildScoreFilterBlocked() then return end
    if not isGuildDungeonScoreSort(memberList, columnIndex) then return end
    local db = self.db or self:EnsureDB()
    applyGuildDungeonScoreFilter(memberList, db)
    applyGuildDungeonScoreSort(memberList, db)
  end

  local function afterUpdateMemberList(memberList)
    if guildScoreFilterUnsafe then return end
    if isGuildScoreFilterBlocked() then return end
    local db = self.db or self:EnsureDB()
    applyGuildDungeonScoreFilter(memberList, db)
    local activeColumnSortIndex
    safeGuildScoreCall(function() activeColumnSortIndex = memberList and memberList.activeColumnSortIndex end)
    if not isGuildDungeonScoreSort(memberList, activeColumnSortIndex) then return end
    applyGuildDungeonScoreSort(memberList, db)
    if memberList and memberList.RefreshListDisplay then
      safeGuildScoreCall(memberList.RefreshListDisplay, memberList)
    end
  end

  if not self._communitiesMixinHooked then
    self._communitiesMixinHooked = true
    hooksecurefunc(CommunitiesMemberListMixin, "SortByColumnIndex", afterSortByColumnIndex)
    hooksecurefunc(CommunitiesMemberListMixin, "UpdateMemberList", afterUpdateMemberList)

    hooksecurefunc(CommunitiesMemberListEntryMixin, "RefreshExpandedColumns", function(entry)
      if guildScoreFilterUnsafe then return end
      if isGuildScoreFilterBlocked() then return end
      if not (entry and entry.guildColumnIndex == GUILD_DUNGEON_SCORE_COLUMN_INDEX and entry.GuildInfo and entry.GetMemberInfo) then return end
      local db = self.db or self:EnsureDB()
      local ok, memberInfo = safeGuildScoreCall(entry.GetMemberInfo, entry)
      if ok and shouldHideGuildDungeonScore(memberInfo, db) then
        safeGuildScoreCall(entry.GuildInfo.SetText, entry.GuildInfo, NO_ROSTER_ACHIEVEMENT_POINTS or "-")
      end
    end)
  end

  local memberList = CommunitiesFrame and CommunitiesFrame.MemberList
  if memberList and not memberList.KaldoStaleGuildScoreHooks then
    memberList.KaldoStaleGuildScoreHooks = true
    hooksecurefunc(memberList, "SortByColumnIndex", afterSortByColumnIndex)
    hooksecurefunc(memberList, "UpdateMemberList", afterUpdateMemberList)
  end
end

function M:GetOptions()
  return {
    { type="header", text=self.displayName },
    { type="toggle", key="auto_insert", label=(L and L.MM_KEYS_AUTO_INSERT) or "Auto insert keystone on frame open" },
    { type="toggle", key="respond_keys", label=(L and L.MM_KEYS_RESPOND) or "Respond to !key/!keys" },
    { type="header", text=L.MM_KEYS_FOCUS_KICK_HEADER },
    { type="toggle", key="focus_kick_enabled", label=L.MM_KEYS_FOCUS_KICK_ENABLED },
    { type="select", key="focus_kick_icon", label=L.MM_KEYS_FOCUS_KICK_ICON, values=getFocusKickMarkerOptions },
    { type="label", text=L.MM_KEYS_FOCUS_KICK_HINT },
    { type="header", text=(L and L.MM_KEYS_SEASON_OVERLAY_HEADER) or "Season best overlay" },
    { type="toggle", key="season_best_overlay", label=(L and L.MM_KEYS_SEASON_OVERLAY_ENABLED) or "Show overlay on dungeon tiles" },
    { type="toggle", key="score_percentiles", label=(L and L.MM_KEYS_SCORE_PERCENTILES) or "Show score percentiles" },
    { type="label", text=(L and L.MM_KEYS_LEVEL_RULES_HINT) or "Level colors are configured in modules/mm_keys.lua" },
    { type="select", key="acronym_font", label=(L and L.MM_KEYS_ACRONYM_FONT) or "Acronym font", values=function() return Kaldo.Media:GetFonts() end },
    { type="number", key="acronym_size", min=8, max=20, step=1, label=(L and L.MM_KEYS_ACRONYM_SIZE) or "Acronym size" },
    { type="select", key="level_font", label=(L and L.MM_KEYS_LEVEL_FONT) or "Level font", values=function() return Kaldo.Media:GetFonts() end },
    { type="number", key="level_size", min=10, max=28, step=1, label=(L and L.MM_KEYS_LEVEL_SIZE) or "Level size" },
    { type="select", key="score_font", label=(L and L.MM_KEYS_SCORE_FONT) or "Score font", values=function() return Kaldo.Media:GetFonts() end },
    { type="number", key="score_size", min=8, max=20, step=1, label=(L and L.MM_KEYS_SCORE_SIZE) or "Score size" },
    { type="select", key="timer_font", label=(L and L.MM_KEYS_TIMER_FONT) or "Timer font", values=function() return Kaldo.Media:GetFonts() end },
    { type="number", key="timer_size", min=8, max=20, step=1, label=(L and L.MM_KEYS_TIMER_SIZE) or "Timer size" },
    { type="color", key="score_color", label=(L and L.MM_KEYS_SCORE_COLOR) or "Fallback score color" },
    { type="color", key="timer_color_in_time", label=(L and L.MM_KEYS_TIMER_COLOR_INTIME) or "Timer color in time" },
    { type="color", key="timer_color_over_time", label=(L and L.MM_KEYS_TIMER_COLOR_OVERTIME) or "Timer color overtime" },
    { type="header", text=(L and L.MM_KEYS_ACCEPT_HEADER) or "Group accepted reminder" },
    { type="toggle", key="accept_reminder_chat", label=(L and L.MM_KEYS_ACCEPT_CHAT) or "Reminder in chat" },
    { type="toggle", key="accept_reminder_screen", label=(L and L.MM_KEYS_ACCEPT_SCREEN) or "Reminder on screen" },
    { type="toggle", key="accept_teleport_prompt", label=L.MM_KEYS_ACCEPT_TELEPORT },
  }
end

function M:HookFocusKickReadyCheck()
  if self._focusKickReadyCheckHooked or not hooksecurefunc
      or not (C_PartyInfo and C_PartyInfo.DoReadyCheck) then return end
  -- Retail /readycheck uses this namespaced API. Cover the local initiator
  -- after the API returns, as well as READY_CHECK events from other players.
  hooksecurefunc(C_PartyInfo, "DoReadyCheck", function()
    self:AnnounceFocusKick(true)
  end)
  self._focusKickReadyCheckHooked = true
end

function M:OnRegister()
  self.db = self:EnsureDB()
  self._hooked = false
  self._seasonBestHooked = false
  self._lastInsert = 0
  self._wasInGroup = IsInGroup and IsInGroup() or false
  self._pendingAcceptedGroupData = nil
  self._pendingAcceptedAt = 0
  self._lastTeleportPromptID = nil
  self._lastAcceptedGroupID = nil
  self._acceptedTeleportGroup = nil
  self._focusKickChallengeMapID = nil
  self._focusKickRunStarted = false
  self._focusKickReadyCheckHandled = false
  self._pendingFocusKickMacro = nil
  self._lastFocusKickAnnouncement = nil
  self._lastReminder = 0
  self._lastKeysResponseAt = 0
  self._seasonBestOverlays = {}
  self._scorePercentileOverlay = nil
  self._communitiesHooked = false
  self._guildScoreFilterButton = nil
  self:HookFocusKickReadyCheck()
end

function M:OnOptionChanged(key)
  self.db = self:EnsureDB()
  if key == "enabled" then
    self:ClearAcceptedGroupState()
    self._wasInGroup = IsInGroup and IsInGroup() or false
  end
  self:HookFocusKickReadyCheck()
  if not key or key == "enabled" or key == "focus_kick_enabled" or key == "focus_kick_icon" then
    self:UpdateFocusKickMacro()
  end
  self:RefreshAcceptedTeleportPrompt()
  tryHookChallengesFrame(self)
  tryHookCommunitiesFrame(self)
  self:UpdateGuildScoreFilterButton()
  self:RefreshSeasonBestOverlays()
  refreshScorePercentileOverlay(self)
  self:RefreshGuildRosterScores()
end

local function setFontSize(fs, size, flags)
  if not fs or not fs.GetFont or not fs.SetFont then return end
  local font, _, existingFlags = fs:GetFont()
  if not font then return end
  fs:SetFont(font, size, flags or existingFlags or "OUTLINE")
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
end

local function applyConfiguredFont(fs, fontPath, size, flags)
  if not fs or not fs.SetFont then return end
  local _, currentSize, currentFlags = fs:GetFont()
  local finalPath = fontPath or DEFAULT_OVERLAY_FONT
  local finalSize = tonumber(size) or currentSize or 12
  fs:SetFont(finalPath, finalSize, flags or currentFlags or "OUTLINE")
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
end

local function setTextColorFromRGBA(fs, rgba)
  if not fs then return end
  local r = type(rgba) == "table" and rgba[1] or 1
  local g = type(rgba) == "table" and rgba[2] or 1
  local b = type(rgba) == "table" and rgba[3] or 1
  local a = type(rgba) == "table" and rgba[4] or 1
  fs:SetTextColor(r, g, b, a)
end

local function setTextColorFromColorObject(fs, color, fallback)
  if not fs then return end
  if type(color) == "table" and color.r and color.g and color.b then
    fs:SetTextColor(color.r, color.g, color.b, color.a or 1)
    return
  end
  setTextColorFromRGBA(fs, fallback)
end

ensureChallengesUILoaded = function()
  if ChallengesFrame or ChallengesKeystoneFrame then
    return true
  end

  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_ChallengesUI")
  elseif UIParentLoadAddOn then
    pcall(UIParentLoadAddOn, "Blizzard_ChallengesUI")
  end

  return not not (ChallengesFrame or ChallengesKeystoneFrame)
end

local function buildDungeonAcronym(name)
  if type(name) ~= "string" or name == "" then return "?" end
  local words = {}
  for word in name:gmatch("[%a%d]+") do
    local lower = word:lower()
    if lower ~= "the" and lower ~= "of" and lower ~= "and" and lower ~= "de" and lower ~= "du" and lower ~= "des" and lower ~= "la" and lower ~= "le" and lower ~= "les" then
      words[#words + 1] = word
    end
  end

  if #words >= 2 then
    local out = {}
    for i = 1, math.min(3, #words) do
      out[#out + 1] = words[i]:sub(1, 1):upper()
    end
    return table.concat(out)
  end

  local compact = name:gsub("[%s%p]+", ""):upper()
  if compact == "" then
    return "?"
  end
  return compact:sub(1, math.min(3, #compact))
end

local function getDungeonAcronym(mapChallengeModeID, dungeonName)
  if mapChallengeModeID and DUNGEON_ACRONYMS[mapChallengeModeID] then
    return DUNGEON_ACRONYMS[mapChallengeModeID]
  end
  if mapChallengeModeID then
    return tostring(mapChallengeModeID)
  end
  return buildDungeonAcronym(dungeonName)
end

local function getLevelColor(level)
  level = tonumber(level) or 0
  for _, rule in ipairs(KEY_LEVEL_COLOR_RULES) do
    if level >= (tonumber(rule.minLevel) or 0) then
      return rule.color
    end
  end
  return { 1.00, 1.00, 1.00, 1.00 }
end

local function hideBaseTileText(frame, visited)
  if type(frame) ~= "table" then return end
  if frame.KaldoIsSeasonBestOverlay then return end
  visited = visited or {}
  if visited[frame] then return end
  visited[frame] = true

  if frame.GetRegions then
    for _, region in ipairs({ frame:GetRegions() }) do
      if region and region.GetObjectType and region:GetObjectType() == "FontString" then
        region:Hide()
        if region.SetAlpha then region:SetAlpha(0) end
      end
    end
  end

  if frame.GetChildren then
    for _, child in ipairs({ frame:GetChildren() }) do
      hideBaseTileText(child, visited)
    end
  end
end

local function trimNumber(value)
  local text = string.format("%.1f", tonumber(value) or 0)
  text = text:gsub("%.0$", "")
  return text
end

local function formatPercentile(value)
  value = tonumber(value)
  if not value then return nil end
  if value < 0.1 then
    return "<0.1%"
  end
  if value < 10 then
    return string.format("%.1f%%", value)
  end
  return string.format("%d%%", math.floor(value + 0.5))
end

local function interpolatePercentile(points, score)
  score = tonumber(score)
  if type(points) ~= "table" or not score or score <= 0 then return nil end
  if #points == 0 then return nil end

  local first = points[1]
  if type(first) == "table" and score >= (tonumber(first.score) or 0) then
    return tonumber(first.topPercent)
  end

  for i = 1, #points - 1 do
    local high = points[i]
    local low = points[i + 1]
    local highScore = tonumber(high and high.score)
    local lowScore = tonumber(low and low.score)
    local highPercent = tonumber(high and high.topPercent)
    local lowPercent = tonumber(low and low.topPercent)
    if highScore and lowScore and highPercent and lowPercent and highScore >= score and score >= lowScore then
      if highScore == lowScore then
        return highPercent
      end
      local ratio = (score - lowScore) / (highScore - lowScore)
      return lowPercent + ((highPercent - lowPercent) * ratio)
    end
  end

  local last = points[#points]
  return tonumber(last and last.topPercent)
end

local function getPlayerRegionKey()
  local regionID = GetCurrentRegion and GetCurrentRegion()
  if regionID == 1 then return "us" end
  if regionID == 2 then return "kr" end
  if regionID == 3 then return "eu" end
  if regionID == 4 then return "tw" end
  if regionID == 5 then return "cn" end
  return "eu"
end

local function estimateScorePercentiles(score)
  local data = NS.MMPercentiles or BUILTIN_MM_PERCENTILES
  if type(data) ~= "table" or type(data.regions) ~= "table" then return nil, nil end
  local regionData = data.regions[getPlayerRegionKey()]
  if not regionData then
    regionData = data.regions.eu
  end
  local worldData = data.regions.world
  local regional = regionData and interpolatePercentile(regionData.points, score) or nil
  local world = worldData and interpolatePercentile(worldData.points, score) or nil
  return regional, world
end

local function formatDurationSeconds(totalSeconds)
  totalSeconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
  local hours = math.floor(totalSeconds / 3600)
  local minutes = math.floor((totalSeconds % 3600) / 60)
  local seconds = totalSeconds % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
  end
  return string.format("%d:%02d", minutes, seconds)
end

local function getSpellCooldownRemaining(spellID)
  if not spellID then return nil end
  local startTime, duration, enabled, modRate
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and type(info) == "table" then
      startTime = tonumber(info.startTime)
      duration = tonumber(info.duration)
      enabled = info.isEnabled
      modRate = tonumber(info.modRate) or 1
    end
  elseif GetSpellCooldown then
    local ok, start, cooldownDuration, cooldownEnabled, cooldownModRate = pcall(GetSpellCooldown, spellID)
    if ok then
      startTime = tonumber(start)
      duration = tonumber(cooldownDuration)
      enabled = cooldownEnabled
      modRate = tonumber(cooldownModRate) or 1
    end
  end

  if enabled == false or enabled == 0 then return nil end
  if not startTime or not duration or startTime <= 0 or duration <= 1.5 then return nil end
  local now = GetTime and GetTime() or 0
  local remaining = (startTime + duration - now) / math.max(modRate or 1, 0.001)
  if remaining > 0 then
    return remaining
  end
  return nil
end

local function getMapTimeLimit(mapChallengeModeID)
  if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
  local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
  return tonumber(timeLimit)
end

local function chooseSeasonBestRun(mapChallengeModeID)
  if C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
    local affixScores = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(mapChallengeModeID)
    if type(affixScores) == "table" then
      local best
      for _, info in ipairs(affixScores) do
        if type(info) == "table" and tonumber(info.level) and tonumber(info.level) > 0 then
          if (not best)
            or (tonumber(info.level) > tonumber(best.level))
            or (tonumber(info.level) == tonumber(best.level) and (tonumber(info.score) or 0) > (tonumber(best.score) or 0))
            or (tonumber(info.level) == tonumber(best.level) and (tonumber(info.score) or 0) == (tonumber(best.score) or 0) and (tonumber(info.durationSec) or math.huge) < (tonumber(best.durationSec) or math.huge)) then
            best = info
          end
        end
      end
      if best then
        return {
          level = tonumber(best.level) or 0,
          score = tonumber(best.score) or 0,
          durationSec = tonumber(best.durationSec) or 0,
          overTime = not not best.overTime,
        }
      end
    end
  end

  if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
    local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapChallengeModeID)
    local chosen, overTime = nil, false
    local function consider(info, isOverTime)
      if type(info) ~= "table" or not tonumber(info.level) then return end
      if (not chosen)
        or (tonumber(info.level) > tonumber(chosen.level))
        or (tonumber(info.level) == tonumber(chosen.level) and (tonumber(info.dungeonScore) or 0) > (tonumber(chosen.dungeonScore) or 0))
        or (tonumber(info.level) == tonumber(chosen.level) and (tonumber(info.dungeonScore) or 0) == (tonumber(chosen.dungeonScore) or 0) and (tonumber(info.durationSec) or math.huge) < (tonumber(chosen.durationSec) or math.huge)) then
        chosen = info
        overTime = not not isOverTime
      end
    end
    consider(intimeInfo, false)
    consider(overtimeInfo, true)
    if chosen then
      return {
        level = tonumber(chosen.level) or 0,
        score = tonumber(chosen.dungeonScore) or 0,
        durationSec = tonumber(chosen.durationSec) or 0,
        overTime = overTime,
      }
    end
  end

  return nil
end

local function getScoreColor(score, fallback)
  if C_ChallengeMode and C_ChallengeMode.GetSpecificDungeonScoreRarityColor and tonumber(score) and tonumber(score) > 0 then
    return C_ChallengeMode.GetSpecificDungeonScoreRarityColor(score)
  end
  return fallback
end

local function getSpellName(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spellID)
    if type(info) == "table" and info.name then
      return info.name
    end
  end
  if GetSpellInfo then
    local name = GetSpellInfo(spellID)
    if name then return name end
  end
  return nil
end

local function isTeleportKnown(spellID)
  if not spellID then return false end
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, spellID)
    if ok and known then return true end
  end
  if IsPlayerSpell then
    local ok, known = pcall(IsPlayerSpell, spellID)
    if ok and known then return true end
  end
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
    if ok and known then return true end
  end
  if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
    local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
    if ok and known then return true end
  end
  return false
end

local teleportButtonCounter = 0

local function clearTeleportButton(button)
  if not button or (InCombatLockdown and InCombatLockdown()) then return end
  button:SetAttribute("type", nil)
  button:SetAttribute("spell", nil)
  button:SetAttribute("type1", nil)
  button:SetAttribute("spell1", nil)
end

local function hideTeleportButton(button)
  if not button or (InCombatLockdown and InCombatLockdown()) then return end
  button:Hide()
  button:ClearAllPoints()
  button:EnableMouse(false)
  clearTeleportButton(button)
end

local function createTeleportButton(overlay)
  teleportButtonCounter = teleportButtonCounter + 1
  local button = CreateFrame("Button", "KaldoMMTeleportButton" .. tostring(teleportButtonCounter), UIParent, "SecureActionButtonTemplate")
  button.KaldoSeasonBestOverlay = overlay
  button:SetFrameStrata("DIALOG")
  button:SetFrameLevel(500)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:EnableMouse(false)
  button:Hide()
  return button
end

local function positionTeleportButton(button, target, shouldShow)
  if not button then return end
  if not shouldShow then
    hideTeleportButton(button)
    return
  end
  if InCombatLockdown and InCombatLockdown() then return end
  if not (target and target.GetLeft and target.GetRight and target.GetTop and target.GetBottom) then
    hideTeleportButton(button)
    return
  end

  local left, right, top, bottom = target:GetLeft(), target:GetRight(), target:GetTop(), target:GetBottom()
  if not (left and right and top and bottom) then
    hideTeleportButton(button)
    return
  end

  local parent = button:GetParent() or UIParent
  local targetScale = (target.GetEffectiveScale and target:GetEffectiveScale()) or 1
  local parentScale = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
  if parentScale == 0 then parentScale = 1 end

  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", left * targetScale / parentScale, top * targetScale / parentScale)
  button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", right * targetScale / parentScale, bottom * targetScale / parentScale)
  button:SetFrameStrata("DIALOG")
  button:SetFrameLevel(500)
  button:EnableMouse(true)
  button:Show()
end

local function configureTeleportButton(overlay, mapChallengeModeID)
  if not overlay then return nil, false end
  local button = overlay.teleportButton
  if not button then return nil, false end
  local spellID = DUNGEON_TELEPORT_SPELLS[tonumber(mapChallengeModeID)]
  local known = isTeleportKnown(spellID)
  overlay.KaldoTeleportSpellID = spellID
  overlay.KaldoTeleportKnown = known
  overlay.KaldoTeleportName = getSpellName(spellID)
  button.KaldoTeleportSpellID = spellID
  button.KaldoTeleportKnown = known
  button.KaldoTeleportName = overlay.KaldoTeleportName

  if InCombatLockdown and InCombatLockdown() then
    return spellID, known
  end

  clearTeleportButton(button)

  if spellID and known then
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", spellID)
    button:SetAttribute("type1", "spell")
    button:SetAttribute("spell1", spellID)
  end

  return spellID, known
end

isLikelySeasonBestButton = function(frame)
  if type(frame) ~= "table" or not frame.GetObjectType then return false end
  local objectType = frame:GetObjectType()
  if objectType ~= "Button" and objectType ~= "Frame" then return false end
  if frame.IsForbidden and frame:IsForbidden() then return false end
  if frame.IsVisible and not frame:IsVisible() then return false end
  if (frame.GetWidth and frame:GetWidth() or 0) < 40 then return false end
  if (frame.GetHeight and frame:GetHeight() or 0) < 40 then return false end
  return true
end

isLikelySeasonBestFallbackButton = function(frame, parentLeft, parentRight, parentTop, parentBottom)
  if not isLikelySeasonBestButton(frame) then return false end
  local width = frame.GetWidth and frame:GetWidth() or 0
  local height = frame.GetHeight and frame:GetHeight() or 0
  if width > 96 or height > 96 then return false end

  local left = frame.GetLeft and frame:GetLeft() or nil
  local right = frame.GetRight and frame:GetRight() or nil
  local top = frame.GetTop and frame:GetTop() or nil
  local bottom = frame.GetBottom and frame:GetBottom() or nil
  if not (left and right and top and bottom and parentLeft and parentRight and parentTop and parentBottom) then
    return false
  end

  local parentWidth = parentRight - parentLeft
  local parentHeight = parentTop - parentBottom
  if parentWidth <= 0 or parentHeight <= 0 then
    return false
  end

  local centerX = (left + right) / 2
  local centerY = (top + bottom) / 2
  local relX = (centerX - parentLeft) / parentWidth
  local relY = (centerY - parentBottom) / parentHeight

  return relX >= 0.02 and relX <= 0.98 and relY >= 0.00 and relY <= 0.30
end

local function getPositionTarget(entry)
  if type(entry) == "table" and entry.frame then
    return entry.frame
  end
  return entry
end

local function sortFramesByPosition(frames)
  table.sort(frames, function(a, b)
    local aframe = getPositionTarget(a)
    local bframe = getPositionTarget(b)
    local atop = aframe and aframe.GetTop and aframe:GetTop() or 0
    local btop = bframe and bframe.GetTop and bframe:GetTop() or 0
    if math.abs((atop or 0) - (btop or 0)) > 4 then
      return (atop or 0) > (btop or 0)
    end
    local aleft = aframe and aframe.GetLeft and aframe:GetLeft() or 0
    local bleft = bframe and bframe.GetLeft and bframe:GetLeft() or 0
    return (aleft or 0) < (bleft or 0)
  end)
end

function M:GetSeasonBestRoot()
  if not ChallengesFrame then return nil end
  local candidates = {
    ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child and ChallengesFrame.WeeklyInfo.Child.SeasonBest,
    ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.SeasonBest,
    ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child,
    ChallengesFrame.WeeklyInfo,
    ChallengesFrame,
  }
  for _, frame in ipairs(candidates) do
    if type(frame) == "table" and frame.GetObjectType then
      local objectType = frame:GetObjectType()
      if objectType == "Frame" or objectType == "Button" or objectType == "ScrollFrame" then
        return frame
      end
    end
  end
  if ChallengesFrame.GetObjectType and ChallengesFrame:GetObjectType() == "Frame" then
    return ChallengesFrame
  end
  return nil
end

function M:ResolveSeasonBestButtons()
  local root = self:GetSeasonBestRoot() or ChallengesFrame
  if not root then return {} end

  local explicit, implicit, seenFrames, seenCandidates, usedMapIDs = {}, {}, {}, {}, {}
  local parentFrame = ChallengesFrame or root
  local parentLeft = parentFrame and parentFrame.GetLeft and parentFrame:GetLeft() or nil
  local parentRight = parentFrame and parentFrame.GetRight and parentFrame:GetRight() or nil
  local parentTop = parentFrame and parentFrame.GetTop and parentFrame:GetTop() or nil
  local parentBottom = parentFrame and parentFrame.GetBottom and parentFrame:GetBottom() or nil

  local function recurse(frame, depth)
    if not frame or seenFrames[frame] or depth > 4 then return end
    seenFrames[frame] = true

    if frame ~= root and isLikelySeasonBestButton(frame) then
      local mapChallengeModeID = frame.mapChallengeModeID or frame.challengeModeID or frame.challengeModeId or frame.mapID or frame.id
      if tonumber(mapChallengeModeID) and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local mapName = C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
        if mapName then
          explicit[#explicit + 1] = { frame = frame, mapChallengeModeID = tonumber(mapChallengeModeID) }
          usedMapIDs[tonumber(mapChallengeModeID)] = true
          seenCandidates[frame] = true
        end
      elseif not seenCandidates[frame] and isLikelySeasonBestFallbackButton(frame, parentLeft, parentRight, parentTop, parentBottom) then
        implicit[#implicit + 1] = frame
        seenCandidates[frame] = true
      end
    end

    if not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
      recurse(child, depth + 1)
    end
  end

  recurse(root, 0)
  if #implicit == 0 and ChallengesFrame and ChallengesFrame ~= root and ChallengesFrame.GetChildren then
    for _, child in ipairs({ ChallengesFrame:GetChildren() }) do
      if not seenCandidates[child] and isLikelySeasonBestFallbackButton(child, parentLeft, parentRight, parentTop, parentBottom) then
        implicit[#implicit + 1] = child
        seenCandidates[child] = true
      end
    end
  end
  sortFramesByPosition(implicit)

  local mapIDs = {}
  if C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local ids = C_ChallengeMode.GetMapTable()
    if type(ids) == "table" then
      for _, mapChallengeModeID in ipairs(ids) do
        if not usedMapIDs[mapChallengeModeID] then
          mapIDs[#mapIDs + 1] = mapChallengeModeID
        end
      end
    end
  end

  local out = {}
  for _, entry in ipairs(explicit) do
    out[#out + 1] = entry
  end
  for index, frame in ipairs(implicit) do
    if mapIDs[index] then
      out[#out + 1] = { frame = frame, mapChallengeModeID = mapIDs[index] }
    end
  end

  sortFramesByPosition(out)
  return out
end

function M:EnsureSeasonBestOverlay(button)
  if button.KaldoSeasonBestOverlay then
    return button.KaldoSeasonBestOverlay
  end

  hideBaseTileText(button)

  local overlay = CreateFrame("Frame", nil, button)
  overlay.KaldoIsSeasonBestOverlay = true
  overlay:SetAllPoints(button)
  overlay:SetFrameLevel(math.max((button.GetFrameLevel and button:GetFrameLevel() or 0) + 5, 5))
  overlay:EnableMouse(false)

  overlay.teleportButton = createTeleportButton(overlay)

  overlay.acronym = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  overlay.acronym:SetPoint("TOPLEFT", 4, -4)
  overlay.acronym:SetJustifyH("LEFT")
  applyConfiguredFont(overlay.acronym, DEFAULT_OVERLAY_FONT, 11, "OUTLINE")

  overlay.level = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  overlay.level:SetPoint("TOP", 0, -16)
  overlay.level:SetJustifyH("CENTER")
  applyConfiguredFont(overlay.level, DEFAULT_OVERLAY_FONT, 18, "THICKOUTLINE")

  overlay.score = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  overlay.score:SetPoint("BOTTOM", 0, 14)
  overlay.score:SetJustifyH("CENTER")
  applyConfiguredFont(overlay.score, DEFAULT_OVERLAY_FONT, 11, "OUTLINE")

  overlay.timer = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  overlay.timer:SetPoint("BOTTOM", 0, 3)
  overlay.timer:SetJustifyH("CENTER")
  applyConfiguredFont(overlay.timer, DEFAULT_OVERLAY_FONT, 10, "OUTLINE")

  button.KaldoSeasonBestOverlay = overlay
  self._seasonBestOverlays[button] = overlay
  return overlay
end

function M:HideSeasonBestOverlays()
  for _, overlay in pairs(self._seasonBestOverlays or {}) do
    overlay:Hide()
    hideTeleportButton(overlay.teleportButton)
  end
end

function M:RefreshSeasonBestOverlays()
  local db = self.db or self:EnsureDB()
  if not (db.enabled and db.season_best_overlay) then
    self:HideSeasonBestOverlays()
    return
  end

  if not ChallengesFrame or not ChallengesFrame:IsShown() then return end
  local buttons = self:ResolveSeasonBestButtons()
  if #buttons == 0 then
    self:HideSeasonBestOverlays()
    return
  end

  local active = {}
  for _, entry in ipairs(buttons) do
    local button = entry.frame
    local mapChallengeModeID = entry.mapChallengeModeID
    local mapName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
    local bestRun = mapName and chooseSeasonBestRun(mapChallengeModeID) or nil

    if button and mapName and bestRun and bestRun.level and bestRun.level > 0 then
      hideBaseTileText(button)
      local overlay = self:EnsureSeasonBestOverlay(button)
      overlay:Show()
      local teleportSpellID, teleportKnown = configureTeleportButton(overlay, mapChallengeModeID)
      positionTeleportButton(overlay.teleportButton, button, teleportSpellID ~= nil)

      applyConfiguredFont(overlay.acronym, db.acronym_font, db.acronym_size, "OUTLINE")
      applyConfiguredFont(overlay.level, db.level_font, db.level_size, "THICKOUTLINE")
      applyConfiguredFont(overlay.score, db.score_font, db.score_size, "OUTLINE")
      applyConfiguredFont(overlay.timer, db.timer_font, db.timer_size, "OUTLINE")

      overlay.acronym:SetText(getDungeonAcronym(mapChallengeModeID, mapName))
      overlay.level:SetText("+" .. tostring(bestRun.level))
      overlay.score:SetText(trimNumber(bestRun.score))
      overlay.timer:SetText(formatDurationSeconds(bestRun.durationSec))

      setTextColorFromRGBA(overlay.level, getLevelColor(bestRun.level))
      setTextColorFromColorObject(overlay.score, getScoreColor(bestRun.score, db.score_color), db.score_color)
      if bestRun.overTime then
        setTextColorFromRGBA(overlay.timer, db.timer_color_over_time)
      else
        setTextColorFromRGBA(overlay.timer, db.timer_color_in_time)
      end

      local timeLimit = getMapTimeLimit(mapChallengeModeID)
      local hoverFrame = overlay.teleportButton or overlay
      hoverFrame:SetScript("OnEnter", function(selfFrame)
        if not GameTooltip then return end
        local infoOverlay = selfFrame.KaldoSeasonBestOverlay or overlay
        GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(mapName, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(((L and L.MM_KEYS_TOOLTIP_LEVEL) or "Best level") .. ": +" .. tostring(bestRun.level), 1, 0.82, 0)
        GameTooltip:AddLine(((L and L.MM_KEYS_TOOLTIP_SCORE) or "Score gained") .. ": " .. trimNumber(bestRun.score), 1, 1, 1)
        if timeLimit then
          GameTooltip:AddLine(((L and L.MM_KEYS_TOOLTIP_TIMER) or "Timer") .. ": " .. formatDurationSeconds(bestRun.durationSec) .. " / " .. formatDurationSeconds(timeLimit), 0.85, 0.85, 0.85)
        else
          GameTooltip:AddLine(((L and L.MM_KEYS_TOOLTIP_TIMER) or "Timer") .. ": " .. formatDurationSeconds(bestRun.durationSec), 0.85, 0.85, 0.85)
        end
        if teleportSpellID then
          local teleportName = infoOverlay.KaldoTeleportName or getSpellName(teleportSpellID) or tostring(teleportSpellID)
          if teleportKnown then
            GameTooltip:AddLine(string.format((L and L.MM_KEYS_TOOLTIP_TELEPORT_CLICK_FMT) or "Click: %s", teleportName), 0.45, 0.85, 1)
            local cooldownRemaining = getSpellCooldownRemaining(teleportSpellID)
            if cooldownRemaining then
              GameTooltip:AddLine(((L and L.MM_KEYS_TOOLTIP_TELEPORT_COOLDOWN) or "Cooldown") .. ": " .. formatDurationSeconds(cooldownRemaining), 1, 0.65, 0.25)
            end
          else
            GameTooltip:AddLine(string.format((L and L.MM_KEYS_TOOLTIP_TELEPORT_UNKNOWN_FMT) or "Teleport not learned: %s", teleportName), 0.55, 0.55, 0.55)
          end
        end
        GameTooltip:Show()
      end)
      hoverFrame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
      end)

      active[button] = true
    elseif button and button.KaldoSeasonBestOverlay then
      button.KaldoSeasonBestOverlay:Hide()
      hideTeleportButton(button.KaldoSeasonBestOverlay.teleportButton)
    end
  end

  for button, overlay in pairs(self._seasonBestOverlays or {}) do
    if not active[button] then
      overlay:Hide()
      hideTeleportButton(overlay.teleportButton)
    end
  end
end

local function collectFrameCandidates(frame, out, visited, depth)
  if type(frame) ~= "table" or visited[frame] or depth > 5 then return end
  visited[frame] = true
  if frame.IsForbidden and frame:IsForbidden() then return end

  out[#out + 1] = frame
  if frame.GetChildren then
    for _, child in ipairs({ frame:GetChildren() }) do
      collectFrameCandidates(child, out, visited, depth + 1)
    end
  end
end

local function getDungeonScoreText()
  local scoreText = ChallengesFrame
    and ChallengesFrame.WeeklyInfo
    and ChallengesFrame.WeeklyInfo.Child
    and ChallengesFrame.WeeklyInfo.Child.DungeonScoreInfo
    and ChallengesFrame.WeeklyInfo.Child.DungeonScoreInfo.Score

  if type(scoreText) == "table"
    and scoreText.GetObjectType
    and scoreText:GetObjectType() == "FontString"
    and not (scoreText.IsForbidden and scoreText:IsForbidden()) then
    return scoreText
  end
  return nil
end

local function parseDisplayedScore(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  text = text:gsub(",", "")

  local best
  for candidate in text:gmatch("%d[%d%s]*") do
    local compact = candidate:gsub("%s+", "")
    local score = tonumber(compact)
    if score and score >= 500 and score <= 5000 and (not best or score > best) then
      best = score
    end
  end
  return best
end

local function readDisplayedOverallScore()
  if not ChallengesFrame then return nil, nil end

  local scoreText = getDungeonScoreText()
  if scoreText and scoreText.GetText then
    local score = parseDisplayedScore(scoreText:GetText())
    if score and score > 0 then
      return score, scoreText
    end
  end

  local frames = {}
  collectFrameCandidates(ChallengesFrame, frames, {}, 0)
  local bestScore, bestAnchor = nil, nil
  for _, frame in ipairs(frames) do
    if frame.GetRegions then
      for _, region in ipairs({ frame:GetRegions() }) do
        if region
          and region.GetObjectType
          and region:GetObjectType() == "FontString"
          and region.GetText then
          local score = parseDisplayedScore(region:GetText())
          if score and (not bestScore or score > bestScore) then
            bestScore = score
            bestAnchor = region
          end
        end
      end
    end
  end

  return bestScore, bestAnchor
end

local function getOverallDungeonScore()
  local displayedScore, displayedAnchor = readDisplayedOverallScore()
  if displayedScore then
    return displayedScore, displayedAnchor
  end

  if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local score = tonumber(C_ChallengeMode.GetOverallDungeonScore())
    if score and score > 0 then
      return score, nil
    end
  end
  return nil, nil
end

function M:EnsureScorePercentileOverlay()
  if self._scorePercentileOverlay then
    return self._scorePercentileOverlay
  end
  if not ChallengesFrame then return nil end

  local overlay = CreateFrame("Frame", nil, UIParent or ChallengesFrame)
  overlay:SetSize(58, 24)
  overlay:SetFrameStrata("DIALOG")
  overlay:SetFrameLevel(200)
  overlay:EnableMouse(true)

  overlay.regional = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  overlay.regional:SetPoint("TOPLEFT", 0, 0)
  overlay.regional:SetJustifyH("LEFT")
  applyConfiguredFont(overlay.regional, DEFAULT_OVERLAY_FONT, 9, "OUTLINE")

  overlay.world = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  overlay.world:SetPoint("TOPLEFT", overlay.regional, "BOTTOMLEFT", 0, -1)
  overlay.world:SetJustifyH("LEFT")
  applyConfiguredFont(overlay.world, DEFAULT_OVERLAY_FONT, 9, "OUTLINE")

  overlay:SetScript("OnEnter", function(selfFrame)
    if not GameTooltip then return end
    local data = NS.MMPercentiles or BUILTIN_MM_PERCENTILES or {}
    GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine((L and L.MM_KEYS_TOOLTIP_PERCENTILE_SOURCE) or "Top percentiles estimated from Raider.IO data", 1, 1, 1)
    if data.seasonName then
      GameTooltip:AddLine(tostring(data.seasonName), 0.85, 0.85, 0.85)
    end
    if data.updated then
      GameTooltip:AddLine(tostring(data.updated), 0.65, 0.65, 0.65)
    end
    if selfFrame.KaldoScore then
      GameTooltip:AddLine("Score: " .. tostring(selfFrame.KaldoScore), 0.65, 0.85, 1)
    end
    if selfFrame.KaldoDataStatus then
      GameTooltip:AddLine(selfFrame.KaldoDataStatus, 0.65, 0.65, 0.65)
    end
    GameTooltip:Show()
  end)
  overlay:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  self._scorePercentileOverlay = overlay
  return overlay
end

refreshScorePercentileOverlay = function(self)
  local db = self.db or self:EnsureDB()
  local scoreFrame = getDungeonScoreText()
  local scoreVisible = scoreFrame and scoreFrame.IsVisible and scoreFrame:IsVisible()
  if not (db.enabled and db.score_percentiles and ChallengesFrame and ChallengesFrame.IsVisible and ChallengesFrame:IsVisible() and scoreVisible) then
    if self._scorePercentileOverlay then self._scorePercentileOverlay:Hide() end
    return
  end

  local score, anchor = getOverallDungeonScore()
  anchor = anchor or scoreFrame

  local regional, world = estimateScorePercentiles(score)
  local regionalText = formatPercentile(regional) or "--"
  local worldText = formatPercentile(world) or "--"

  local overlay = self:EnsureScorePercentileOverlay()
  if not overlay then return end
  overlay.KaldoScore = score
  overlay.KaldoDataStatus = (NS.MMPercentiles and NS.MMPercentiles.regions and NS.MMPercentiles.regions.world)
    and "Percentile data loaded"
    or "Using built-in percentile fallback"
  overlay:ClearAllPoints()
  if anchor then
    local textHalfWidth = anchor.GetStringWidth and (anchor:GetStringWidth() / 2) or 28
    overlay:SetPoint("LEFT", anchor, "CENTER", textHalfWidth + 3, 0)
  else
    overlay:SetPoint("TOP", ChallengesFrame, "TOP", 68, -175)
  end

  applyConfiguredFont(overlay.regional, db.score_font, 9, "OUTLINE")
  applyConfiguredFont(overlay.world, db.score_font, 9, "OUTLINE")
  overlay.regional:SetText(((L and L.MM_KEYS_PERCENTILE_REGIONAL) or "REG") .. " " .. regionalText)
  overlay.world:SetText(((L and L.MM_KEYS_PERCENTILE_WORLD) or "WORLD") .. " " .. worldText)
  overlay.regional:SetTextColor(0.82, 0.92, 1.00, 1)
  overlay.world:SetTextColor(0.78, 0.78, 0.78, 1)
  overlay:Show()
end

function M:DebugScorePercentiles()
  local db = self.db or self:EnsureDB()
  local scoreText = getDungeonScoreText()
  local rawText = scoreText and scoreText.GetText and scoreText:GetText() or nil
  local parsedScore, anchor = getOverallDungeonScore()
  local regionKey = getPlayerRegionKey()
  local data = NS.MMPercentiles or BUILTIN_MM_PERCENTILES
  local externalData = NS.MMPercentiles
  local regions = type(data) == "table" and data.regions or nil
  local regionData = type(regions) == "table" and regions[regionKey] or nil
  local worldData = type(regions) == "table" and regions.world or nil
  local regional, world = estimateScorePercentiles(parsedScore)

  refreshScorePercentileOverlay(self)

  chatLine("MM percentile debug")
  chatLine("enabled=" .. tostring(db.enabled) .. " option=" .. tostring(db.score_percentiles) .. " challengesShown=" .. tostring(ChallengesFrame and ChallengesFrame:IsShown()))
  chatLine("scoreFrame=" .. tostring(scoreText ~= nil) .. " anchor=" .. tostring(anchor ~= nil))
  chatLine("rawScore=" .. tostring(rawText) .. " parsedScore=" .. tostring(parsedScore))
  chatLine("externalDataLoaded=" .. tostring(type(externalData) == "table") .. " fallbackDataLoaded=" .. tostring(data == BUILTIN_MM_PERCENTILES) .. " season=" .. tostring(data and data.season) .. " updated=" .. tostring(data and data.updated))
  chatLine("region=" .. tostring(regionKey) .. " regionPoints=" .. tostring(regionData and regionData.points and #regionData.points) .. " worldPoints=" .. tostring(worldData and worldData.points and #worldData.points))
  chatLine("regional=" .. tostring(regional) .. " world=" .. tostring(world))
end

local function trim(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

local function textHasKeystoneHint(s)
  if type(s) ~= "string" then return false end
  return s:find("%+%s*%d+") ~= nil
end

local function extractKeystoneLevel(s)
  if type(s) ~= "string" then return nil end
  local lvl = s:match("%+%s*(%d+)")
  if not lvl then return nil end
  lvl = tonumber(lvl)
  if not lvl then return nil end
  return lvl
end

local function getSearchResultInfoByID(searchResultID)
  if not (searchResultID and C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
  local ri = C_LFGList.GetSearchResultInfo(searchResultID)
  if type(ri) == "table" then return ri end
  return nil
end

-- Resolve from Blizzard activity/map IDs rather than the group leader's text.
local function getAcceptedChallengeMapID(ri)
  if not (type(ri) == "table" and C_LFGList and C_LFGList.GetActivityInfoTable
      and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
  local activityIDs = ri.activityIDs or { ri.activityID }
  local challengeMapID
  for _, activityID in ipairs(activityIDs) do
    local activity = C_LFGList.GetActivityInfoTable(activityID)
    if activity and activity.isMythicPlusActivity and activity.mapID and activity.mapID > 0 then
      local match
      for mapID in pairs(DUNGEON_TELEPORT_SPELLS) do
        local _, _, _, _, _, instanceMapID = C_ChallengeMode.GetMapUIInfo(mapID)
        if instanceMapID == activity.mapID then match = mapID; break end
      end
      -- A listing with multiple different dungeons has no single destination.
      if not match or (challengeMapID and challengeMapID ~= match) then return nil end
      challengeMapID = match
    end
  end
  return challengeMapID
end

local function getActivityNameFromInfo(ri)
  if type(ri) ~= "table" then return nil end
  local activityID = ri.activityID
  if (not activityID) and type(ri.activityIDs) == "table" then
    activityID = ri.activityIDs[1]
  end
  if not (activityID and C_LFGList and C_LFGList.GetActivityInfoTable) then return nil end
  local ai = C_LFGList.GetActivityInfoTable(activityID)
  if type(ai) ~= "table" then return nil end
  return ai.fullName or ai.shortName or ai.name
end

local function extractKeyLabel(name, ri)
  local comment = type(ri) == "table" and ri.comment or nil
  local activityName = getActivityNameFromInfo(ri)

  -- Prefer real dungeon/activity name for key label.
  if type(activityName) == "string" and activityName ~= "" then
    local lvl = extractKeystoneLevel(comment) or extractKeystoneLevel(name)
    if lvl then
      return string.format("%s +%d", activityName, lvl)
    end
    return activityName
  end

  if textHasKeystoneHint(comment) then return comment end
  if textHasKeystoneHint(name) then return name end

  -- Fallback: use comment if author wrote key details there even without '+'.
  if type(comment) == "string" and comment ~= "" then return comment end
  return nil
end

local function getGroupDataFromSearchResultID(searchResultID, fallbackGroupName)
  local ri = getSearchResultInfoByID(searchResultID)
  if not ri then return nil end

  local groupName = trim(fallbackGroupName) or ri.name
  if not groupName or groupName == "" then return nil end

  return {
    groupName = groupName,
    keyLabel = extractKeyLabel(groupName, ri),
    searchResultID = searchResultID,
    mapChallengeModeID = getAcceptedChallengeMapID(ri),
  }
end

local function getAcceptedGroupDataFromEventArgs(searchResultID, status, nameFromEvent)
  local function isAccepted(st)
    return st == "invited" or st == "inviteaccepted"
  end
  if not isAccepted(status) then return nil end

  local evName = trim(nameFromEvent)
  local fromSearch = getGroupDataFromSearchResultID(searchResultID, evName)
  if fromSearch then
    if (not fromSearch.keyLabel or fromSearch.keyLabel == "") and evName then
      fromSearch.keyLabel = evName
    end
    return fromSearch
  end

  -- Fallback when searchResultID lookup is unavailable.
  if evName then
    return {
      groupName = evName,
      keyLabel = evName,
      searchResultID = searchResultID,
    }
  end

  return nil
end

function M:UpdateFocusKickMacro()
  local db = self.db or self:EnsureDB()
  if not (db.enabled and db.focus_kick_enabled) then
    self._pendingFocusKickMacro = nil
    self._focusKickReadyCheckHandled = false
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    self._pendingFocusKickMacro = true
    return false
  end
  self._pendingFocusKickMacro = nil
  local icon = getFocusKickMarker(db.focus_kick_icon)
  local body = "/stopmacro [noexists][help][dead]\n/focus\n/tm !" .. tostring(icon)
  -- Macro icons use a file ID. The full .blp path is needed for path lookup;
  -- a valid question-mark icon keeps the macro draggable if lookup fails.
  local path = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. tostring(icon) .. ".blp"
  local texture = GetFileIDFromPath and GetFileIDFromPath(path)
  if not texture or texture <= 0 then texture = 134400 end
  local index = GetMacroIndexByName and GetMacroIndexByName(FOCUS_KICK_MACRO_NAME) or 0
  if index > 0 then
    local currentBody = GetMacroBody and GetMacroBody(index) or self._focusKickMacroBody
    local currentIcon
    if C_Macro and C_Macro.GetSelectedMacroIcon then
      currentIcon = C_Macro.GetSelectedMacroIcon(index)
    elseif GetMacroInfo then
      local _, savedIcon = GetMacroInfo(index)
      currentIcon = savedIcon
    else
      currentIcon = self._focusKickMacroIcon
    end
    if currentBody == body and currentIcon == texture then return true end
  end
  local ok, result = MacroUtils.CreateOrUpdateMacro(FOCUS_KICK_MACRO_NAME, body, texture)
  if ok then
    self._focusKickMacroBody = body
    self._focusKickMacroIcon = texture
    self._focusKickMacroError = nil
    return true
  end
  if self._focusKickMacroError ~= result then
    self._focusKickMacroError = result
    chatLine(string.format(L.MM_KEYS_FOCUS_KICK_MACRO_ERROR, FOCUS_KICK_MACRO_NAME))
  end
  return false
end

local function challengeMapMatchesInstance(challengeMapID, instanceID)
  if not (challengeMapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return false end
  local _, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(challengeMapID)
  return mapID ~= nil and mapID == instanceID
end

function M:IsFocusKickDungeon()
  if not (IsInInstance and IsInInstance() and GetInstanceInfo) then return false end
  local _, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
  if instanceType ~= "party" or difficultyID ~= 23 then return false end
  -- Before starting a key, Mythic+ and Mythic 0 share the same difficulty.
  -- Require the joined Mythic+ listing or an inserted keystone, never just M0.
  if challengeMapMatchesInstance(self._focusKickChallengeMapID, instanceID) then return true end
  if C_ChallengeMode and C_ChallengeMode.GetSlottedKeystoneInfo then
    local mapID = C_ChallengeMode.GetSlottedKeystoneInfo()
    if challengeMapMatchesInstance(mapID, instanceID) then return true end
  end
  if C_LFGList and C_LFGList.GetActiveEntryInfo then
    local entry = C_LFGList.GetActiveEntryInfo()
    local mapID = getAcceptedChallengeMapID(entry)
    if challengeMapMatchesInstance(mapID, instanceID) then return true end
  end
  return false
end

function M:AnnounceFocusKick(localStart)
  if self._focusKickReadyCheckHandled then return end
  local db = self.db or self:EnsureDB()
  if not (db.enabled and db.focus_kick_enabled) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
  if self._focusKickRunStarted then return end
  if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then return end
  if C_PartyInfo and C_PartyInfo.IsChallengeModeActive and C_PartyInfo.IsChallengeModeActive() then return end
  if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return end
  if not self:IsFocusKickDungeon() then return end
  -- A rejected DoReadyCheck request must not announce anything. Read the
  -- timer only after combat/chat lockdown checks because it can be secret.
  if localStart then
    local timeLeft = GetReadyCheckTimeLeft and GetReadyCheckTimeLeft()
    if not timeLeft or (issecretvalue and issecretvalue(timeLeft)) or timeLeft <= 0 then return end
  end
  local now = GetTime()
  if self._lastFocusKickAnnouncement and (now - self._lastFocusKickAnnouncement) < 5 then return end
  if not self:UpdateFocusKickMacro() then return end
  local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
  if not send then return end
  local icon, marker = getFocusKickMarker(db.focus_kick_icon)
  -- Deliberately English so the convention is readable in international groups.
  local message = string.format("[Kaldo Tweaks] My focus kick marker is {rt%d} (%s).", icon, marker.name)
  local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and "INSTANCE_CHAT" or "PARTY"
  send(message, channel)
  -- Only a sent announcement consumes the check. A local READY_CHECK may
  -- arrive inside DoReadyCheck before its post-hook can inspect the state.
  self._focusKickReadyCheckHandled = true
  self._lastFocusKickAnnouncement = now
end

function M:DismissAcceptedTeleportPrompt()
  self._acceptedTeleportGroup = nil
  if self._acceptedTeleportPrompt and not (InCombatLockdown and InCombatLockdown()) then
    self._acceptedTeleportPrompt:Hide()
    clearTeleportButton(self._acceptedTeleportPrompt.teleportButton)
  end
end

function M:CreateAcceptedTeleportPrompt()
  if self._acceptedTeleportPrompt then return self._acceptedTeleportPrompt end
  if InCombatLockdown and InCombatLockdown() then return nil end

  local frame = CreateFrame("Frame", "KaldoMMAcceptedTeleportPrompt", UIParent, "BackdropTemplate")
  frame:SetSize(340, 210)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  frame:SetBackdropColor(0.03, 0.04, 0.045, 0.96)
  frame:SetBackdropBorderColor(0.12, 0.39, 0.35, 1)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(f)
    if not (InCombatLockdown and InCombatLockdown()) then f:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function(f)
    if not (InCombatLockdown and InCombatLockdown()) then f:StopMovingOrSizing() end
  end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("Kaldo Tweaks - MM+")
  title:SetTextColor(0, 0.86, 0.7)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() self:DismissAcceptedTeleportPrompt() end)

  frame.keyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.keyLabel:SetPoint("TOP", 0, -48)
  frame.keyLabel:SetSize(300, 44)
  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.status:SetPoint("TOP", 0, -98)
  frame.status:SetWidth(300)

  local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  button:SetSize(260, 30)
  button:SetPoint("TOP", 0, -128)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetText(L.MM_KEYS_TELEPORT_BUTTON)
  frame.teleportButton = button

  local checkbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  checkbox:SetSize(24, 24)
  checkbox:SetPoint("BOTTOMLEFT", 16, 14)
  checkbox.Text:SetText(L.MM_KEYS_TELEPORT_DONT_SHOW)
  checkbox:SetScript("OnClick", function(clicked)
    local db = self.db or self:EnsureDB()
    db.accept_teleport_prompt = not clicked:GetChecked()
    if not db.accept_teleport_prompt then self:DismissAcceptedTeleportPrompt() end
    if NS.UI and NS.UI.RefreshModuleOptions then NS.UI:RefreshModuleOptions("MMKeys") end
  end)
  frame.dontShow = checkbox

  -- Keep this listener alive if the module is disabled while its secure child
  -- prevents hiding the window in combat. It also closes after a successful TP.
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      if unit == "player" and spellID == button.KaldoTeleportSpellID then
        self:DismissAcceptedTeleportPrompt()
      end
    else
      if not (IsInGroup and IsInGroup()) then self:DismissAcceptedTeleportPrompt() end
      self:RefreshAcceptedTeleportPrompt()
    end
  end)
  local elapsedSinceUpdate = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < 1 then return end
    elapsedSinceUpdate = 0
    self:UpdateAcceptedTeleportStatus()
  end)
  frame:Hide()
  self._acceptedTeleportPrompt = frame
  return frame
end

function M:UpdateAcceptedTeleportStatus()
  local frame = self._acceptedTeleportPrompt
  if not frame then return end
  if InCombatLockdown and InCombatLockdown() then
    frame.status:SetText(L.MM_KEYS_TELEPORT_COMBAT)
    return
  end
  local button = frame.teleportButton
  local known = isTeleportKnown(button.KaldoTeleportSpellID)
  local remaining = known and getSpellCooldownRemaining(button.KaldoTeleportSpellID)
  button:SetEnabled(known and not remaining)
  if not known then
    frame.status:SetText(L.MM_KEYS_TELEPORT_NOT_LEARNED)
  elseif remaining then
    frame.status:SetText(L.MM_KEYS_TOOLTIP_TELEPORT_COOLDOWN .. ": " .. formatDurationSeconds(remaining))
  else
    frame.status:SetText(L.MM_KEYS_TELEPORT_READY)
  end
end

function M:RefreshAcceptedTeleportPrompt()
  local db = self.db or self:EnsureDB()
  local data = self._acceptedTeleportGroup
  if not (db.enabled and db.accept_teleport_prompt and data) then
    self:DismissAcceptedTeleportPrompt()
    return
  end
  if InCombatLockdown and InCombatLockdown() then return end
  if IsInInstance and IsInInstance() and GetInstanceInfo and C_ChallengeMode then
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local _, _, _, _, _, dungeonInstanceID = C_ChallengeMode.GetMapUIInfo(data.mapChallengeModeID)
    if instanceID == dungeonInstanceID then self:DismissAcceptedTeleportPrompt(); return end
  end
  local frame = self:CreateAcceptedTeleportPrompt()
  local spellID = DUNGEON_TELEPORT_SPELLS[data.mapChallengeModeID]
  clearTeleportButton(frame.teleportButton)
  frame.teleportButton.KaldoTeleportSpellID = spellID
  if isTeleportKnown(spellID) then
    frame.teleportButton:SetAttribute("type1", "spell")
    frame.teleportButton:SetAttribute("spell1", spellID)
  end
  frame.keyLabel:SetText(data.keyLabel or C_ChallengeMode.GetMapUIInfo(data.mapChallengeModeID))
  frame.dontShow:SetChecked(false)
  self:UpdateAcceptedTeleportStatus()
  frame:Show()
end

function M:ShowAcceptedTeleportPrompt(groupData)
  local db = self.db or self:EnsureDB()
  if not (db.enabled and db.accept_teleport_prompt and type(groupData) == "table"
      and DUNGEON_TELEPORT_SPELLS[groupData.mapChallengeModeID]) then return end
  local identity = tostring(groupData.searchResultID or groupData.groupName)
  if self._lastTeleportPromptID == identity then return end
  self._lastTeleportPromptID = identity
  self._acceptedTeleportGroup = groupData
  self:RefreshAcceptedTeleportPrompt()
end

function M:AnnounceAcceptedGroup(groupData)
  local groupName = type(groupData) == "table" and groupData.groupName or groupData
  if not groupName or groupName == "" then return end
  local identity = tostring(type(groupData) == "table" and groupData.searchResultID or groupName)
  if self._lastAcceptedGroupID == identity then return end
  self._lastAcceptedGroupID = identity
  -- Keep the Mythic+ destination even after the teleport popup is dismissed.
  self._focusKickChallengeMapID = type(groupData) == "table" and groupData.mapChallengeModeID or nil
  local db = self.db or self:EnsureDB()
  self:ShowAcceptedTeleportPrompt(groupData)
  if not (db.accept_reminder_chat or db.accept_reminder_screen) then return end
  local keyLabel = type(groupData) == "table" and groupData.keyLabel or nil

  local now = GetTime()
  if (now - (self._lastReminder or 0)) < 2 then return end
  self._lastReminder = now

  local msg
  if keyLabel and keyLabel ~= "" then
    local fmtWithKey = (L and L.MM_KEYS_ACCEPTED_WITH_KEY_FMT) or "Accepted in group: %s | Key: %s"
    msg = string.format(fmtWithKey, tostring(groupName), tostring(keyLabel))
  else
    local fmt = (L and L.MM_KEYS_ACCEPTED_FMT) or "Accepted in group: %s"
    msg = string.format(fmt, tostring(groupName))
  end

  if db.accept_reminder_chat and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd1ffKaldo Tweaks:|r " .. msg)
  end

  if db.accept_reminder_screen then
    if RaidNotice_AddMessage and RaidWarningFrame then
      local info = ChatTypeInfo and (ChatTypeInfo["RAID_WARNING"] or ChatTypeInfo["SYSTEM"])
      if not info then info = { r = 1.0, g = 0.82, b = 0.0 } end
      RaidNotice_AddMessage(RaidWarningFrame, msg, info)
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
      UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 2.0)
    end
  end
end

function M:ClearAcceptedGroupState()
  self:DismissAcceptedTeleportPrompt()
  self._lastTeleportPromptID = nil
  self._lastAcceptedGroupID = nil
  self._focusKickChallengeMapID = nil
  self._pendingAcceptedGroupData = nil
  self._pendingAcceptedAt = 0
end

function M:CheckGroupJoinReminder()
  local inGroup = IsInGroup and IsInGroup() or false
  if self._wasInGroup == nil then
    self._wasInGroup = inGroup
    return
  end

  if inGroup and not self._wasInGroup then
    local now = GetTime and GetTime() or 0
    local isFreshPending = self._pendingAcceptedGroupData
      and self._pendingAcceptedGroupData.inviteAccepted
      and self._pendingAcceptedAt
      and (now - self._pendingAcceptedAt) <= 30

    local groupData = nil
    if isFreshPending then
      groupData = self._pendingAcceptedGroupData
    end

    if groupData then
      self:AnnounceAcceptedGroup(groupData)
    end
    self._pendingAcceptedGroupData = nil
    self._pendingAcceptedAt = 0
  elseif not inGroup and self._wasInGroup then
    self:ClearAcceptedGroupState()
  end

  self._wasInGroup = inGroup
end

tryHookChallengesFrame = function(self)
  ensureChallengesUILoaded()

  if not self._hooked and ChallengesKeystoneFrame then
    self._hooked = true

    ChallengesKeystoneFrame:HookScript("OnShow", function()
      local db = self.db or self:EnsureDB()
      if not (db.enabled and db.auto_insert) then return end

      DEFAULT_CHAT_FRAME:AddMessage("|cff7fd1ffKaldo Tweaks:|r " .. L.AUTOINSERT_MESSAGE)
      if self._lastInsert and (GetTime() - self._lastInsert) < 1.0 then return end
      self._lastInsert = GetTime()

      if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID and C_Container.UseContainerItem) then
        return
      end

      for bag = 0, NUM_BAG_FRAMES do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
          local id = C_Container.GetContainerItemID(bag, slot)
          if id and KEYSTONE_ITEM_IDS[id] then
            C_Container.UseContainerItem(bag, slot)
            return
          end
        end
      end
    end)
  end

  if self._seasonBestHooked then return end
  if not ChallengesFrame then return end

  self._seasonBestHooked = true
  ChallengesFrame:HookScript("OnShow", function() self:QueueChallengesRefresh() end)
  ChallengesFrame:HookScript("OnHide", function()
    self:HideSeasonBestOverlays()
    if self._scorePercentileOverlay then self._scorePercentileOverlay:Hide() end
  end)

  if ChallengesFrame.Update and hooksecurefunc then
    hooksecurefunc(ChallengesFrame, "Update", function() self:QueueChallengesRefresh() end)
  end
  self:QueueChallengesRefresh()
end


function M:QueueChallengesRefresh()
  if not self.db or not self.db.enabled or not ChallengesFrame or not ChallengesFrame:IsShown() then return end
  if self._challengesRefreshQueued then return end
  self._challengesRefreshQueued = true
  C_Timer.After(0, function()
    self._challengesRefreshQueued = nil
    if not self.db or not self.db.enabled or not ChallengesFrame or not ChallengesFrame:IsShown() then return end
    self:RefreshSeasonBestOverlays()
    refreshScorePercentileOverlay(self)
  end)
end

function M:RespondKeys(event)
  local db = self.db or self:EnsureDB()
  if not db.respond_keys then return end
  if IsInRaid and IsInRaid() then return end
  if shouldSuppressKeysChat() then return end

  local now = GetTime and GetTime() or 0
  if (now - (self._lastKeysResponseAt or 0)) < 1.5 then
    return
  end

  local channel
  if event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
    channel = "PARTY"
  elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
    channel = "INSTANCE_CHAT"
  end
  if not channel then return end

  local link = getOwnedKeystoneLink()
  if not link then
    self._lastKeysResponseAt = now
    SendChatMessage((L and L.MM_KEYS_NONE) or "[Kaldo Tweaks] No keystone.", channel)
    return
  end

  self._lastKeysResponseAt = now
  SendChatMessage("[Kaldo Tweaks] " .. link, channel)
end

function M:OnEvent(event, ...)
  if event == "GROUP_LEFT" then
    local category = ...
    if not category or category == (LE_PARTY_CATEGORY_HOME or 1) then
      self:ClearAcceptedGroupState()
      self._wasInGroup = false
    end
    return
  end
  if event == "READY_CHECK" then
    self:AnnounceFocusKick()
    return
  end
  if event == "READY_CHECK_CONFIRM" then
    local unit, isReady = ...
    -- The initiator is automatically ready. This also covers server-side
    -- confirmation arriving after the local API hook, before its timer exists.
    if unit == "player" and isReady then self:AnnounceFocusKick() end
    return
  end
  if event == "READY_CHECK_FINISHED" then
    self._focusKickReadyCheckHandled = false
    return
  end
  if event == "CHALLENGE_MODE_MAPS_UPDATE" or event == "SPELLS_CHANGED" then
    self:QueueChallengesRefresh()
    if event == "SPELLS_CHANGED" then self:RefreshAcceptedTeleportPrompt() end
    return
  end
  if event == "PLAYER_LOGIN" then
    self.db = self:EnsureDB()
    self:HookFocusKickReadyCheck()
    self:UpdateFocusKickMacro()
    tryHookChallengesFrame(self)
    tryHookCommunitiesFrame(self)
    self._wasInGroup = IsInGroup and IsInGroup() or false
    return
  end

  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == "Blizzard_ChallengesUI" then
      tryHookChallengesFrame(self)
    elseif addon == "Blizzard_Communities" then
      tryHookCommunitiesFrame(self)
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD"
    or event == "GROUP_ROSTER_UPDATE"
    or event == "PLAYER_ROLES_ASSIGNED"
    or event == "PARTY_LEADER_CHANGED"
    or event == "PLAYER_SPECIALIZATION_CHANGED" then
    self:CheckGroupJoinReminder()
    if event == "PLAYER_ENTERING_WORLD" then
      self:RefreshAcceptedTeleportPrompt()
      self:UpdateFocusKickMacro()
      if not (IsInInstance and IsInInstance()) then self._focusKickRunStarted = false end
    end
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    self:UpdateGuildScoreFilterButton()
    return
  end

  if event == "CHALLENGE_MODE_START"
    or event == "CHALLENGE_MODE_COMPLETED"
    or event == "CHALLENGE_MODE_RESET" then
    self:QueueChallengesRefresh()
    self:UpdateGuildScoreFilterButton()
    if event == "CHALLENGE_MODE_START" then
      self._focusKickRunStarted = true
      self:DismissAcceptedTeleportPrompt()
    elseif event == "CHALLENGE_MODE_RESET" then
      self._focusKickRunStarted = false
    end
    if event ~= "CHALLENGE_MODE_START" then
      self:RefreshGuildRosterScores()
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    if self._pendingFocusKickMacro then self:UpdateFocusKickMacro() end
    if not (IsInGroup and IsInGroup()) then self:DismissAcceptedTeleportPrompt() end
    self:RefreshAcceptedTeleportPrompt()
    self:RefreshSeasonBestOverlays()
    refreshScorePercentileOverlay(self)
    self:UpdateGuildScoreFilterButton()
    self:RefreshGuildRosterScores()
    return
  end

  if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
    -- The third argument is OLD status, not pending status. An invitation
    -- being cancelled must never be stored as a fresh accepted application.
    local searchResultID, status, _, groupName = ...
    local data = getAcceptedGroupDataFromEventArgs(searchResultID, status, groupName)
    if data and data.groupName and data.groupName ~= "" then
      data.inviteAccepted = status == "inviteaccepted"
      self._pendingAcceptedGroupData = data
      self._pendingAcceptedAt = GetTime and GetTime() or 0
    elseif self._pendingAcceptedGroupData
        and self._pendingAcceptedGroupData.searchResultID == searchResultID then
      self._pendingAcceptedGroupData = nil
      self._pendingAcceptedAt = 0
    end
    return
  end

  if event == "LFG_LIST_JOINED_GROUP" then
    local searchResultID, groupName = ...
    local data = getGroupDataFromSearchResultID(searchResultID, groupName)
    local pending = self._pendingAcceptedGroupData
    if not data and pending and pending.searchResultID == searchResultID
        and (GetTime() - (self._pendingAcceptedAt or 0)) <= 30 then
      data = pending
    end
    if data and data.groupName and data.groupName ~= "" then
      self._pendingAcceptedGroupData = data
      self._pendingAcceptedAt = GetTime and GetTime() or 0
      self:AnnounceAcceptedGroup(data)
      self._pendingAcceptedGroupData = nil
      self._pendingAcceptedAt = 0
    end
    return
  end

  if event == "CHAT_MSG_PARTY"
    or event == "CHAT_MSG_PARTY_LEADER"
    or event == "CHAT_MSG_INSTANCE_CHAT"
    or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
    if shouldSuppressKeysChat() then
      return
    end
    local msg, author = ...
    if isTrustedKeysSender(author) and isKeysCommand(msg) then
      self:RespondKeys(event)
    end
  end
end

Kaldo:RegisterModule("MMKeys", M)

SLASH_KALDOMMDEBUG1 = "/kaldommdebug"
SlashCmdList["KALDOMMDEBUG"] = function()
  ensureChallengesUILoaded()
  M:DebugScorePercentiles()
end

-- Run from the repository root with Lua 5.1 or newer.
local state, module, NS
local function noOp() end
local function textRegion()
  return {
    SetText = function(self, text) self.text = text end,
    SetTextColor = noOp, SetPoint = noOp, SetSize = noOp, SetWidth = noOp,
  }
end
local function protectedChange(frame)
  local current = frame
  while current do
    assert(not (state.combat and current.protected), 'Protected UI changed in combat')
    current = current.parent
  end
end
CreateFrame = function(kind, name, parent, template)
  assert(not state.combat, 'Prompt created in combat')
  local frame = { scripts = {}, events = {}, attributes = {}, parent = parent, shown = true }
  if template and template:find('SecureActionButtonTemplate', 1, true) then
    local current = frame
    while current do current.protected = true; current = current.parent end
  end
  frame.Text = textRegion()
  frame.CreateFontString = function() return textRegion() end
  frame.SetScript = function(self, event, callback) self.scripts[event] = callback end
  frame.RegisterEvent = function(self, event) self.events[event] = true end
  frame.RegisterUnitEvent = function(self, event, unit) self.events[event] = unit end
  frame.SetAttribute = function(self, key, value)
    protectedChange(self)
    self.attributes[key] = value
  end
  frame.Show = function(self) protectedChange(self); self.shown = true end
  frame.Hide = function(self) protectedChange(self); self.shown = false end
  frame.IsShown = function(self) return self.shown end
  frame.SetEnabled = function(self, enabled) protectedChange(self); self.enabled = not not enabled end
  frame.SetText = function(self, text) self.text = text end
  frame.SetChecked = function(self, checked) self.checked = checked end
  frame.GetChecked = function(self) return self.checked end
  for _, method in ipairs({ 'SetSize', 'SetPoint', 'SetFrameStrata', 'SetBackdrop',
    'SetBackdropColor', 'SetBackdropBorderColor', 'EnableMouse', 'SetMovable',
    'RegisterForDrag', 'RegisterForClicks', 'StartMoving', 'StopMovingOrSizing' }) do
    frame[method] = function(self) protectedChange(self) end
  end
  state.frames[#state.frames + 1] = frame
  return frame
end
SlashCmdList = {}
UIParent = { parent = nil }
GetLocale = function() return 'frFR' end
GetTime = function() return state.now end
InCombatLockdown = function() return state.combat end
IsInGroup = function(category)
  if category == 2 then return state.instanceGroup end
  return state.inGroup
end
IsInRaid = function() return state.inRaid end
IsInInstance = function() return state.instance ~= nil end
GetInstanceInfo = function()
  assert(not state.chatLocked, 'Instance data inspected while chat was locked')
  return 'Dungeon', state.instanceType, state.difficulty, '', 5, false, false, state.instance
end
IsSpellKnown = function(id) return state.known[id] == true end
C_Spell = {
  GetSpellCooldown = function(id)
    assert(not state.combat, 'Cooldown inspected during combat')
    return state.cooldowns[id] or { startTime = 0, duration = 0, isEnabled = true }
  end,
}
C_ChallengeMode = {
  IsChallengeModeActive = function() return state.runActive end,
  GetSlottedKeystoneInfo = function() return state.slottedMapID end,
  GetMapUIInfo = function(id)
  if id == 399 then return 'Bassins de l\'Essence rubis', 399, 1800, nil, 1, 2521 end
  if id == 250 then return 'Temple de Sephraliss', 250, 1800, nil, 1, 1877 end
end }
C_LFGList = {
  GetActiveEntryInfo = function() return state.activeEntry end,
  GetSearchResultInfo = function(id) return state.results[id] end,
  GetActivityInfoTable = function(id) return state.activities[id] end,
  GetApplications = function() return { 10 } end,
  GetApplicationInfo = function()
    if state.applicationTable then
      return { searchResultID = 10, applicationStatus = 'invited' }
    end
    return 10, 'invited', nil
  end,
}
C_MythicPlus = { GetCurrentRunID = function() return state.runID end }
C_ChatInfo = {
  InChatMessagingLockdown = function() return state.chatLocked end,
  SendChatMessage = function(message, channel)
    assert(not state.combat and not state.chatLocked and not state.runActive, 'Forbidden announcement')
    state.messages[#state.messages + 1] = { message = message, channel = channel }
  end,
}
GetFileIDFromPath = function(path)
  local marker = path:match('UI%-RaidTargetingIcon_(%d)%.blp$')
  assert(marker, 'Macro icon lookup needs the complete BLP path')
  if state.iconLookupFails then return 0 end
  return 900000 + tonumber(marker) -- fake client file IDs, not marker indices
end
C_Macro = { GetSelectedMacroIcon = function(index)
  assert(index == 1)
  return state.macros.KaldoFocusKick and state.macros.KaldoFocusKick.icon
end }
GetMacroInfo = function(index)
  assert(index == 1)
  local macro = state.macros.KaldoFocusKick
  if macro then return 'KaldoFocusKick', macro.icon, macro.body end
end
GetMacroIndexByName = function(name) return state.macros[name] and 1 or 0 end
GetMacroBody = function() return state.macros.KaldoFocusKick and state.macros.KaldoFocusKick.body end
CreateMacro = function(name, icon, body, perCharacter)
  assert(not state.combat, 'Macro created in combat')
  if state.macrosFull then error('No macro slots') end
  assert(name == 'KaldoFocusKick' and perCharacter == 1)
  assert(type(icon) == 'number' and icon > 0, 'Macro created without a valid numeric icon')
  state.macros[name] = { icon = icon, body = body }
  state.macroWrites = state.macroWrites + 1
  return 1
end
EditMacro = function(index, name, icon, body)
  assert(index == 1 and not state.combat, 'Macro edited in combat')
  assert(type(icon) == 'number' and icon > 0, 'Macro edited without a valid numeric icon')
  state.macros[name] = { icon = icon, body = body }
  state.macroWrites = state.macroWrites + 1
  return 1
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) state.localMessages[#state.localMessages + 1] = text end }
GetReadyCheckTimeLeft = function()
  assert(not state.chatLocked, 'Ready-check timer read during chat lockdown')
  return state.readyTimeLeft or 0
end
hooksecurefunc = function(target, method, callback)
  assert(type(target) == 'table' and method == 'DoReadyCheck', 'Unexpected secure hook')
  local original = target[method]
  state.readyHookCount = (state.readyHookCount or 0) + 1
  target[method] = function(...)
    original(...)
    callback(...)
  end
end
local function reset()
  state = { now = 100, frames = {}, known = { [393256] = true }, cooldowns = {},
    inGroup = false, combat = false, refreshes = 0, difficulty = 23, instanceType = 'party',
    macros = {}, macroWrites = 0, messages = {}, localMessages = {},
    results = { [10] = { name = 'Weekly +10', activityIDs = { 100 }, comment = '+12' } },
    activities = { [100] = { fullName = 'Bassins de l\'Essence rubis', isMythicPlusActivity = true, mapID = 2521 },
      [200] = { fullName = 'Temple', isMythicPlusActivity = true, mapID = 1877 } },
  }
  C_PartyInfo = {
    IsChallengeModeActive = function() return state.partyRunActive end,
    DoReadyCheck = function()
    state.readyRequests = (state.readyRequests or 0) + 1
    if state.readyRequestRejected then return end
    state.readyTimeLeft = state.localReadyTimerDelayed and 0 or 30
    if state.localReadyEvent then
      local wasLocked = state.chatLocked
      if state.localReadyEventLocked then state.chatLocked = true end
      module:OnEvent('READY_CHECK', 'player', 30)
      state.chatLocked = wasLocked
    end
  end }
  UIParent.protected = nil
  KaldoDB = nil
  NS = { Kaldo = { RegisterModule = function(_, _, value) module = value end },
    UI = { RefreshModuleOptions = function(_, name)
      assert(name == 'MMKeys'); state.refreshes = state.refreshes + 1
    end } }
  assert(loadfile('locales.lua'))('kaldo_tweaks', NS)
  assert(loadfile('db.lua'))('kaldo_tweaks', NS)
  assert(loadfile('macro_utils.lua'))('kaldo_tweaks', NS)
  assert(loadfile('modules/mm_keys.lua'))('kaldo_tweaks', NS)
  module:OnRegister()
  module.db.enabled = true
  module.db.accept_reminder_chat = false
  module.db.accept_reminder_screen = false
end
local function join()
  state.inGroup = true
  module:OnEvent('LFG_LIST_JOINED_GROUP', 10, 'Weekly +10')
  return module._acceptedTeleportPrompt
end
local function leave()
  module._wasInGroup = true
  state.inGroup = false
  module:OnEvent('GROUP_ROSTER_UPDATE')
end

reset()
assert(module.db.accept_teleport_prompt == true)
local hasOption = false
for _, option in ipairs(module:GetOptions()) do
  if option.key == 'accept_teleport_prompt' then hasOption = true end
end
assert(hasOption, 'Config toggle missing')
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'invited', 'applied', 'Weekly +10')
assert(not module._acceptedTeleportPrompt, 'Popup appeared before joining')
local frame = join()
assert(frame and frame:IsShown(), 'Popup should work without chat/screen reminders')
assert(frame.keyLabel.text:find('+12', 1, true))
assert(frame.teleportButton.attributes.type1 == 'spell' and frame.teleportButton.attributes.spell1 == 393256)
assert(frame.teleportButton.enabled and frame.dontShow.Text.text == 'Ne plus afficher')
module:DismissAcceptedTeleportPrompt()
state.now = 105
join()
assert(not frame:IsShown(), 'Repeated join events reopened a dismissed popup')
leave()
assert(join():IsShown(), 'A new join did not reset dismissal')

-- The checkbox persists the same preference as the Kaldo config toggle.
frame.dontShow:SetChecked(true)
frame.dontShow.scripts.OnClick(frame.dontShow)
assert(not module.db.accept_teleport_prompt and not frame:IsShown() and state.refreshes == 1)
assert(module:EnsureDB().accept_teleport_prompt == false, 'Defaults overwrote opt-out')
leave()
join()
assert(not frame:IsShown())
module.db.accept_teleport_prompt = true
leave()
join()
assert(frame:IsShown())

reset()
state.known = {}
frame = join()
assert(frame:IsShown() and not frame.teleportButton.enabled and not frame.teleportButton.attributes.type1)
assert(frame.status.text == NS.L.MM_KEYS_TELEPORT_NOT_LEARNED)
state.known[393256] = true
module:OnEvent('SPELLS_CHANGED')
assert(frame.teleportButton.attributes.spell1 == 393256 and frame.teleportButton.enabled)
state.cooldowns[393256] = { startTime = 90, duration = 30, isEnabled = true }
frame.scripts.OnUpdate(frame, 1)
assert(not frame.teleportButton.enabled and frame.status.text:find('0:20', 1, true))
state.now = 121
frame.scripts.OnUpdate(frame, 1)
assert(frame.teleportButton.enabled, 'Expired cooldown did not re-enable TP')
frame.scripts.OnEvent(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'cast', 393256)
assert(not frame:IsShown(), 'Successful teleport did not close popup')

-- Mythic+ identification uses map IDs and rejects other/ambiguous activities.
reset()
state.activities[100].isMythicPlusActivity = false
assert(not join())
reset()
state.results[10].activityIDs = { 100, 200 }
assert(not join(), 'Ambiguous listing offered the wrong destination')
reset()
state.results[10].activityID, state.results[10].activityIDs = 100, nil
assert(join(), 'Legacy single activity ID did not resolve')
reset()
state.results[10] = nil
assert(not join(), 'Missing listing guessed a teleport')
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'invited', 'applied', 'Weekly +10')
state.results[10] = nil
assert(join(), 'Fresh invitation data lost when listing disappeared')
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'inviteaccepted', 'invited', 'Weekly +10')
state.results[10] = nil
module._wasInGroup, state.inGroup = false, true
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(module._acceptedTeleportPrompt:IsShown(), 'Fresh accepted invitation lost on group transition')

-- All secure mutations wait for combat to end, including after module disable.
reset()
state.combat = true
assert(not join() and module._acceptedTeleportGroup and #state.frames == 0)
state.combat = false
module:OnEvent('PLAYER_REGEN_ENABLED')
frame = module._acceptedTeleportPrompt
assert(frame:IsShown())
state.combat = true
frame.scripts.OnUpdate(frame, 1)
module:DismissAcceptedTeleportPrompt()
assert(frame:IsShown(), 'Protected popup hidden during combat')
state.combat = false
frame.scripts.OnEvent(frame, 'PLAYER_REGEN_ENABLED')
assert(not frame:IsShown())
leave()
join()
state.combat = true
module.db.enabled = false
module:OnOptionChanged("enabled", false)
state.combat = false
frame.scripts.OnEvent(frame, 'PLAYER_REGEN_ENABLED')
assert(not frame:IsShown() and not frame.teleportButton.attributes.type1)
reset()
state.combat = true
join()
leave()
state.combat = false
module:OnEvent('PLAYER_REGEN_ENABLED')
assert(not module._acceptedTeleportPrompt, 'Left group while in combat but popup still appeared')
reset()
state.instance = 2521
assert(not join(), 'Offered teleport while already inside destination')
reset()
frame = join()
state.instance = 2521
module:OnEvent('PLAYER_ENTERING_WORLD')
assert(not frame:IsShown())

reset()
frame = join()
module.db.accept_teleport_prompt = false
module:OnOptionChanged('accept_teleport_prompt', false)
assert(not frame:IsShown(), 'Config toggle did not dismiss popup')
module.db.accept_teleport_prompt = true
module:OnOptionChanged('accept_teleport_prompt', true)
assert(not frame:IsShown(), 'Config toggle reopened a dismissed popup')
leave()
assert(join():IsShown(), 'Re-enabling config did not allow next group')
reset()
frame = join()
state.combat = true
frame.dontShow:SetChecked(true)
frame.dontShow.scripts.OnClick(frame.dontShow)
assert(module.db.accept_teleport_prompt == false and frame:IsShown())
state.combat = false
frame.scripts.OnEvent(frame, 'PLAYER_REGEN_ENABLED')
assert(not frame:IsShown(), 'Opt-out in combat did not dismiss after combat')
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'invited', 'applied', 'Weekly +10')
state.results[10], state.now = nil, 131
assert(not join(), 'Stale invitation data reused')

-- A manual regroup must never rescan stale accepted applications or reuse the
-- old status from cancellation events (third event argument is OLD status).
reset()
module.db.accept_reminder_chat = true
frame = join()
assert(#state.localMessages == 1 and frame:IsShown())
leave()
state.now = 110
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'cancelled', 'invited', 'Weekly +10')
module:OnEvent('LFG_PROPOSAL_SUCCEEDED') -- unrelated queue event, not a premade acceptance
state.inGroup = true
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(#state.localMessages == 1 and not frame:IsShown(), 'Manual regroup reused old key announcement/popup')
assert(not module._pendingAcceptedGroupData and not module._focusKickChallengeMapID)
leave()
state.now = 120
join()
assert(#state.localMessages == 2 and frame:IsShown(), 'Genuine new LFG acceptance was suppressed')
state.now = 130
join()
assert(#state.localMessages == 2, 'Repeated acceptance event repeated the chat reminder')

-- Declined/expired invitations and another application's updates cannot revive
-- a cached invite. Merely being invited is insufficient for a manual join.
for _, status in ipairs({ 'cancelled', 'invitedeclined', 'inviteexpired', 'declined', 'none' }) do
  reset()
  module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'invited', 'applied', 'Weekly +10')
  module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, status, 'invited', 'Weekly +10')
  assert(not module._pendingAcceptedGroupData, 'Cancelled invitation remained pending')
  state.inGroup = true
  module:OnEvent('GROUP_ROSTER_UPDATE')
  assert(not module._acceptedTeleportPrompt)
end
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'invited', 'applied', 'Weekly +10')
state.inGroup = true
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(not module._acceptedTeleportPrompt, 'Manual invite joined while another key invitation existed')
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'inviteaccepted', 'invited', 'Weekly +10')
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 99, 'cancelled', 'invited', 'Other group')
assert(module._pendingAcceptedGroupData and module._pendingAcceptedGroupData.searchResultID == 10)
module:OnEvent('GROUP_ROSTER_UPDATE') -- still solo, do not discard the fresh invitation
assert(module._pendingAcceptedGroupData)
state.inGroup = true
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(module._acceptedTeleportPrompt:IsShown())

-- GROUP_LEFT clears the lifecycle even if roster events were coalesced and the
-- player already appears grouped again when the departure event is processed.
reset()
frame = join()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'inviteaccepted', 'invited', 'Weekly +10')
module:OnEvent('GROUP_LEFT', 1, 'old-party-guid')
assert(not frame:IsShown() and not module._pendingAcceptedGroupData)
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(not frame:IsShown() and not module._focusKickChallengeMapID)
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'inviteaccepted', 'invited', 'Weekly +10')
module:OnEvent('GROUP_LEFT', 2, 'instance-party-guid')
assert(module._pendingAcceptedGroupData, 'Leaving another party category discarded the premade invitation')

reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'inviteaccepted', 'invited', 'Weekly +10')
state.now, state.inGroup = 131, true
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(not module._acceptedTeleportPrompt, 'Expired acceptance used by manual join')
reset()
module:OnEvent('LFG_LIST_APPLICATION_STATUS_UPDATED', 10, 'inviteaccepted', 'invited', 'Weekly +10')
module.db.enabled = false
module:OnOptionChanged('enabled', false)
state.inGroup = true
module.db.enabled = true
module:OnOptionChanged('enabled', true)
module:OnEvent('GROUP_ROSTER_UPDATE')
assert(not module._acceptedTeleportPrompt and not module._pendingAcceptedGroupData, 'Re-enable revived an old invitation')
reset()
frame = join()
state.combat = true
module:OnEvent('GROUP_LEFT', 1, 'old-party-guid')
module:OnEvent('GROUP_ROSTER_UPDATE') -- already manually regrouped, no solo roster snapshot
assert(not module._acceptedTeleportGroup and frame:IsShown())
state.combat = false
frame.scripts.OnEvent(frame, 'PLAYER_REGEN_ENABLED')
assert(not frame:IsShown(), 'Old protected popup survived regrouping after combat')

-- Focus kick is independently opt-in and maintains one character macro.
reset()
assert(module.db.focus_kick_enabled == false and state.macroWrites == 0)
module:OnOptionChanged('focus_kick_icon', 6)
assert(state.macroWrites == 0, 'Disabled feature created a macro')
local markerOptions
for _, option in ipairs(module:GetOptions()) do
  if option.key == 'focus_kick_icon' then markerOptions = option.values() end
end
assert(markerOptions and #markerOptions == 8 and markerOptions[6][2]:find('Carré', 1, true))
module.db.focus_kick_enabled = true
module:OnOptionChanged('focus_kick_enabled', true)
assert(state.macroWrites == 1 and state.macros.KaldoFocusKick.body == '/stopmacro [noexists][help][dead]\n/focus\n/tm !6')
module:UpdateFocusKickMacro()
assert(state.macroWrites == 1, 'Unchanged macro rewritten')
state.macros.KaldoFocusKick.body = '/say edited'
module:UpdateFocusKickMacro()
assert(state.macroWrites == 2, 'Edited macro not repaired')
for icon = 1, 8 do
  module.db.focus_kick_icon = icon
  module:OnOptionChanged('focus_kick_icon', icon)
  assert(state.macros.KaldoFocusKick.body:find('/tm !' .. icon, 1, true))
  assert(state.macros.KaldoFocusKick.icon == 900000 + icon)
end
module.db.focus_kick_icon = 99
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick.body:find('/tm !6', 1, true))
state.macros.KaldoFocusKick = nil
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick, 'Deleted macro not recreated')
local writes = state.macroWrites
state.combat, module.db.focus_kick_icon = true, 7
module:OnOptionChanged('focus_kick_icon', 7)
assert(module._pendingFocusKickMacro and state.macroWrites == writes)
state.combat = false
module:OnEvent('PLAYER_REGEN_ENABLED')
assert(not module._pendingFocusKickMacro and state.macros.KaldoFocusKick.body:find('/tm !7', 1, true))
state.combat, module.db.focus_kick_icon = true, 8
module:UpdateFocusKickMacro()
module.db.focus_kick_enabled = false
module:OnOptionChanged('focus_kick_enabled', false)
assert(not module._pendingFocusKickMacro)
state.combat = false
module:OnEvent('PLAYER_REGEN_ENABLED')
assert(state.macros.KaldoFocusKick.body:find('/tm !7', 1, true), 'Disabled feature still updated macro')

-- Existing macros with correct text but a missing/incorrect icon are repaired.
reset()
module.db.focus_kick_enabled = true
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick.icon == 900006)
state.macros.KaldoFocusKick.icon = nil
module:OnEvent('PLAYER_LOGIN')
assert(state.macros.KaldoFocusKick.icon == 900006 and state.macroWrites == 2)
state.macros.KaldoFocusKick.icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_6'
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick.icon == 900006 and state.macroWrites == 3)
state.macros.KaldoFocusKick.icon = 134400
local savedMacroAPI = C_Macro
C_Macro = nil
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick.icon == 900006, 'GetMacroInfo fallback did not repair icon')
C_Macro = savedMacroAPI
state.iconLookupFails = true
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick.icon == 134400, 'Missing texture did not fall back to a visible icon')
local iconWrites = state.macroWrites
module:UpdateFocusKickMacro()
assert(state.macroWrites == iconWrites, 'Fallback icon rewritten on every update')
state.iconLookupFails = false
module:UpdateFocusKickMacro()
assert(state.macros.KaldoFocusKick.icon == 900006)

local function prepareFocusKick()
  reset()
  module.db.focus_kick_enabled, module.db.accept_teleport_prompt = true, false
  state.instance = 2521
  join()
  module:OnOptionChanged('focus_kick_enabled', true)
end
local function ready()
  module:OnEvent('READY_CHECK')
end
prepareFocusKick()
ready()
assert(#state.messages == 1 and state.messages[1].channel == 'PARTY')
assert(state.messages[1].message == '[Kaldo Tweaks] My focus kick marker is {rt6} (Square).')
ready()
assert(#state.messages == 1, 'Duplicate READY_CHECK sent twice')
module:OnEvent('READY_CHECK_FINISHED')
state.now = 101
ready()
assert(#state.messages == 1, 'Rapid ready checks spammed chat')
module:OnEvent('READY_CHECK_FINISHED')
state.now, state.instanceGroup, module.db.focus_kick_icon = 106, true, 8
ready()
assert(#state.messages == 2 and state.messages[2].channel == 'INSTANCE_CHAT')
assert(state.messages[2].message:find('{rt8} (Skull)', 1, true))

-- No announcement outside the confirmed dungeon or after the run starts.
for _, block in ipairs({
  function() module.db.focus_kick_enabled = false end,
  function() module.db.enabled = false end,
  function() state.combat = true end,
  function() state.chatLocked = true end,
  function() state.runActive = true end,
  function() state.partyRunActive = true end,
  function() state.inGroup = false end,
  function() state.inRaid = true end,
  function() state.instance = nil end,
  function() state.instanceType = 'raid' end,
  function() state.difficulty = 2 end,
  function() state.difficulty = 8 end,
  function() state.instance = 1877 end,
}) do
  prepareFocusKick()
  block()
  ready()
  assert(#state.messages == 0, 'Announcement escaped its context restrictions')
  state.combat, state.chatLocked = false, false
  module:OnEvent('PLAYER_REGEN_ENABLED')
  assert(#state.messages == 0, 'Blocked announcement was deferred')
end
prepareFocusKick()
module:OnEvent('CHALLENGE_MODE_START')
ready()
assert(#state.messages == 0, 'Run start API lag allowed announcement')
module:OnEvent('CHALLENGE_MODE_COMPLETED')
module:OnEvent('READY_CHECK_FINISHED')
ready()
assert(#state.messages == 0, 'Completed run treated as a fresh pre-key group')
module:OnEvent('CHALLENGE_MODE_RESET')
module:OnEvent('READY_CHECK_FINISHED')
ready()
assert(#state.messages == 1)
prepareFocusKick()
module._focusKickChallengeMapID = nil
ready()
assert(#state.messages == 0, 'Mythic 0 without a key announced')
module:OnEvent('READY_CHECK_FINISHED')
state.slottedMapID = 399
ready()
assert(#state.messages == 1, 'Manual group with an inserted key did not announce')
prepareFocusKick()
module._focusKickChallengeMapID = nil
state.activeEntry = { activityIDs = { 100 } }
ready()
assert(#state.messages == 1, 'Leader Mythic+ listing did not identify the dungeon')
prepareFocusKick()
state.runID = 0
ready()
assert(#state.messages == 1, 'Empty run ID was treated as an active run')
prepareFocusKick()
state.runID = 42 -- not a documented Retail active-run predicate
ready()
assert(#state.messages == 1, 'Unsupported run ID API suppressed a pre-key announcement')
prepareFocusKick()
leave()
assert(not module._focusKickChallengeMapID, 'Previous group destination leaked')
state.inGroup = true
ready()
assert(#state.messages == 0)
prepareFocusKick()
state.macros.KaldoFocusKick, state.macrosFull = nil, true
ready()
assert(#state.messages == 0 and #state.localMessages == 1, 'Full macro slots silently advertised a missing macro')
module:OnEvent('READY_CHECK_FINISHED')
state.now = 110
ready()
assert(#state.localMessages == 1, 'Macro failure spammed local chat')

-- The local initiator is covered via the actual Retail launch API, not an
-- obsolete global DoReadyCheck, and shares deduplication with received events.
prepareFocusKick()
assert(state.readyHookCount == 1)
module:HookFocusKickReadyCheck()
module:OnOptionChanged('focus_kick_enabled', true)
assert(state.readyHookCount == 1, 'DoReadyCheck hook installed more than once')
C_PartyInfo.DoReadyCheck()
assert(state.readyRequests == 1 and #state.messages == 1, 'Local initiator did not announce')
ready()
assert(#state.messages == 1, 'READY_CHECK duplicated the local-launch announcement')
module:OnEvent('READY_CHECK_FINISHED')
state.now = 110
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 2, 'Later local check was not announced')
prepareFocusKick()
state.localReadyEvent = true
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 1, 'Synchronous event plus post-hook announced twice')
prepareFocusKick()
state.localReadyEvent, state.localReadyEventLocked = true, true
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 1, 'Early local event consumed the check before post-hook')
prepareFocusKick()
state.localReadyTimerDelayed = true
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 0, 'Unconfirmed local request announced')
module:OnEvent('READY_CHECK_CONFIRM', 'party1', true)
assert(#state.messages == 0, 'Another player confirmation triggered announcement')
module:OnEvent('READY_CHECK_CONFIRM', 'player', false)
assert(#state.messages == 0)
module:OnEvent('READY_CHECK_CONFIRM', 'player', true)
assert(#state.messages == 1, 'Initiator auto-confirmation did not announce')
module:OnEvent('READY_CHECK_CONFIRM', 'player', true)
ready()
assert(#state.messages == 1, 'Confirmation/event path duplicated announcement')
prepareFocusKick()
state.readyRequestRejected = true
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 0, 'Rejected ready-check request announced')
prepareFocusKick()
state.chatLocked = true
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 0)
state.chatLocked = false
module:OnEvent('PLAYER_REGEN_ENABLED')
assert(#state.messages == 0, 'Blocked local announcement was deferred')
prepareFocusKick()
module.db.focus_kick_enabled = false
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 0, 'Disabled feature announced via persistent hook')
prepareFocusKick()
state.runActive = true
C_PartyInfo.DoReadyCheck()
assert(#state.messages == 0, 'Local initiator announced during an active key')

print('PASS: MM+ teleports; Focus Kick defaults, eight markers, character macros, combat deferral, pre-key announcements, chat restrictions and ready-check deduplication')

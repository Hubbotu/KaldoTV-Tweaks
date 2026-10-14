-- Run from the repository root with Lua 5.1 or newer.
-- Model 12.1.5 with the deprecated item globals absent.
GetItemInfo, GetDetailedItemLevelInfo, GetItemGem = nil, nil, nil
local module
local NS = {
  L = { MISSING_SOCKETS = 'missing sockets', EMPTY_SOCKETS = 'empty sockets',
    LOW_QUALITY_GEMS = 'low gems', MISSING_ENCHANT = 'missing enchant' },
  Kaldo = { RegisterModule = function(_, _, value) module = value end },
}
assert(loadfile('db.lua'))('kaldo_tweaks', NS)
assert(loadfile('modules/equipment_info.lua'))('kaldo_tweaks', NS)
module.db = module:EnsureDB()
module.playerSlotCache, module.inspectSlotCache = {}, {}
module.tip = {
  ClearLines = function() end, SetInventoryItem = function() end,
  SetHyperlink = function() end, NumLines = function() return 0 end,
}

local link = 'item:100:0:'
local gemLink = 'item:240906:0:' -- known maximum-rank gem
local currentLevel, baseLevel, detailedLevel = 331, 270, 285
local classID, subclassID, sockets = 4, 1, 1
local infoCalls, detailedCalls, gemCalls = 0, 0, 0
local requested = {}
C_Item = {
  GetItemInfo = function(item)
    assert(item == link)
    infoCalls = infoCalls + 1
    return 'Gear', item, 4, baseLevel, 80, 'Armor', 'Cloth', 1, '', 0, 0, classID, subclassID
  end,
  GetDetailedItemLevelInfo = function(item)
    assert(item == link)
    detailedCalls = detailedCalls + 1
    return detailedLevel
  end,
  GetCurrentItemLevel = function() return currentLevel end,
  GetItemStats = function() return { EMPTY_SOCKET_PRISMATIC = sockets } end,
  GetItemGem = function(item, index)
    assert(item == link and index == 1)
    gemCalls = gemCalls + 1
    if gemLink then return 'Gem', gemLink end
  end,
  RequestLoadItemDataByID = function(id) requested[id] = true end,
  IsItemDataCachedByID = function() return false end,
}
ItemLocation = { CreateFromEquipmentSlot = function()
  return { IsValid = function() return true end }
end }
GetInventoryItemLink = function() return link end

local function fontString()
  return {
    ClearAllPoints = function() end, SetFont = function() end,
    SetPoint = function() end, SetJustifyH = function() end,
    SetText = function(self, text) self.text = text end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
  }
end
local ilvl, status = fontString(), fontString()
local slot = { id = 1, frame = 'CharacterHeadSlot' }
CharacterHeadSlot = { IsVisible = function() return true end }
local function render(unit, slotID)
  module:InvalidateRenderCache()
  slot.id = slotID or 1
  module:RenderSlot(unit or 'player', slot, ilvl, status, module.db, 'MAGE')
end

-- Reproduce the original RenderSlot crash, then exercise sockets and caching.
render()
assert(infoCalls == 1 and detailedCalls == 0 and gemCalls == 1)
assert(ilvl.text:find('331', 1, true) and ilvl.shown and status.shown)
assert(status.text:find('missing enchant', 1, true))
assert(not status.text:find('low gems', 1, true))
assert(module.playerSlotItems[1][240906] and requested[240906], 'Gem dependency lost')
local callsBeforeCache = infoCalls
module:RenderSlot('player', slot, ilvl, status, module.db, 'MAGE')
assert(infoCalls == callsBeforeCache, 'Cached slot fetched item data again')

-- Empty and low-quality sockets retain their warnings using C_Item.GetItemGem.
gemLink = nil
render()
assert(status.text:find('empty sockets', 1, true))
gemLink = 'item:999:0:'
render()
assert(status.text:find('low gems', 1, true))
assert(module.playerSlotItems[1][999] and requested[999])
sockets = 0
render()
assert(status.text:find('missing sockets', 1, true))

-- The fallback must use the namespaced detailed level, not just the base level.
currentLevel = nil
render()
assert(detailedCalls > 0 and ilvl.text:find('285', 1, true))
render('target')
assert(ilvl.text:find('285', 1, true) and status.text == '')
assert(module.inspectSlotCache[1], 'Inspect result was not cached')

-- Item class/subclass return positions still suppress shield enchant warnings.
currentLevel, classID, subclassID = 331, 4, 6
render('player', 17)
assert(status.text == '', 'Shield incorrectly requires an enchant')

print('PASS: EquipmentInfo with deprecated item globals absent; player/inspect levels, sockets, gem dependencies, cache and shield enchants')

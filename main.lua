local api = require("api")

local pve_buddy_addon = {
  name = "PvE Buddy",
  version = "0.1",
  author = "Silverbranch",
  desc = "PvE Tracking tools"
}
local DEBUG_LOGGING = false
local STARTING_TIMER = -1;
local MS_SINCE_LABOR_USED = 1000
local LABOR_CONSUMED_RECENT = false
local KILL_COUNT = 0
local LOOT_LOG = {}

local function reset()
  MS_SINCE_LABOR_USED = 1000
  LABOR_CONSUMED_RECENT = false
  LAST_LABOR = -1
  KILL_COUNT = 0
  STARTING_TIMER = -1;
  LOOT_LOG = {}
end

local function debugLogging(message)
  if DEBUG_LOGGING then
    api.Log:Err(message)
  end
end

local function lazyLogging(message)
  api.Log:Err(message)
end


local pveWindowTesting = api.Interface:CreateEmptyWindow("pveWindowTesting")
pveWindowTesting:SetExtent(280, 280)
pveWindowTesting.bg = pveWindowTesting:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
pveWindowTesting.bg:SetTextureInfo("bg_quest")
pveWindowTesting.bg:SetColor(0, 0, 0, 0.5)
pveWindowTesting.bg:AddAnchor("TOPLEFT", pveWindowTesting, 0, 0)
pveWindowTesting.bg:AddAnchor("BOTTOMRIGHT", pveWindowTesting, 0, 0)

local function calledOnExpChange(unitId, expAmount, expString)
  if not LABOR_CONSUMED_RECENT then
    if STARTING_TIMER == -1 then
      STARTING_TIMER = api.Time:GetUiMsec()
    end
    KILL_COUNT = KILL_COUNT + 1
    local runtime = api.Time:GetUiMsec() - STARTING_TIMER;
    local logMessage = "Current kill count: " .. KILL_COUNT .. " runTime: " .. runtime
    if runtime > 0 then
      local runtime_in_hours = runtime / (1000 * 60 * 60)
      logMessage = logMessage .. " killsPerHour: " .. (KILL_COUNT / runtime_in_hours)
    end
    lazyLogging(logMessage)
  else
    debugLogging("Gained labor recently, so ignoring xp event, current KC is : " .. KILL_COUNT)
  end
end

local function calledOnLabourChange(diff, laborPower)
  debugLogging("Labor change " .. diff .. " Total: " .. laborPower)
  --If the labour amount went up, then the user wouldn't be expected to gain XP
  if diff > 0 then
    --debugLogging("Labour increase, ignoring")
    return nil
  end
  --Reset MS since labor used.
  MS_SINCE_LABOR_USED = 0
  LABOR_CONSUMED_RECENT = true

  debugLogging("Consumed: " .. diff .. " Labor. New Total: " .. laborPower)
end

local function calledOnUpdate(dt)
  if MS_SINCE_LABOR_USED <= 1000 then
    MS_SINCE_LABOR_USED = MS_SINCE_LABOR_USED + dt
    LABOR_CONSUMED_RECENT = true
    --debugLogging("It has been: " .. MS_SINCE_LABOR_USED .. "ms since labor used.")
    return nil
  end
  LABOR_CONSUMED_RECENT = false
  --debugLogging("It has been over 4 seconds since labor was used")
end

local function calledOnItemAcquisition(charName, itemLinkText, itemCount)
  debugLogging("Charname: " .. charName .. " itemLinkText: " .. itemLinkText .. " itemCount: " .. itemCount)
end

local function standardiseKey(key)
  local trimmed = string.sub(key, 2)
  local commaPos = string.find(trimmed, ",")
  if commaPos then
      return string.sub(trimmed, 1, commaPos - 1)
  else
      return trimmed
  end
end

local function calledOnAddedItem(itemLinkText, itemCount, itemTaskType, tradeOtherName)
  --debugLogging("itemLinkText: " .. itemLinkText .. " itemCount: " .. itemCount .. " itemTaskType: " .. itemTaskType .. " tradeOtherName: " .. tradeOtherName)
  if itemLinkText == nil or itemCount == nil then
    return nil --How did we even get here?
  end

  local key = standardiseKey(itemLinkText)
  -- Check if the item exists in the table
  if LOOT_LOG[key] then
      LOOT_LOG[key].itemCount = LOOT_LOG[key].itemCount + itemCount
  else
      -- Add a new entry with itemLinkText and itemCount if we encounter a new itemLinkText
      debugLogging("Key: " .. key .. " did not exist")
      LOOT_LOG[key] = {itemLinkText = itemLinkText, itemCount = itemCount}
  end

  debugLogging(string.format("Added %d to '%s'. Total count: %d", itemCount, itemLinkText, LOOT_LOG[key].itemCount))
end

local function msToHoursMinutesSeconds(ms)
  local totalSeconds = math.floor(ms / 1000)
  local hours = math.floor(totalSeconds / 3600)
  local minutes = math.floor((totalSeconds % 3600) / 60)
  local seconds = totalSeconds % 60
  return hours, minutes, seconds
end


--Temporary lazy debug methods
local function printLoot()
  local hours, minutes, seconds = msToHoursMinutesSeconds(api.Time:GetUiMsec() - STARTING_TIMER)
  lazyLogging("Displaying loot log from a total of: " .. KILL_COUNT .. " kills, made over " .. hours .. " Hours, " .. minutes .. "Minutes, " .. seconds .. " Seconds.")
  for key, value in pairs(LOOT_LOG) do
    lazyLogging(string.format("Name: %s Quantity: %d DropPct: %d", value.itemLinkText, value.itemCount, (value.itemCount/KILL_COUNT * 100)))
  end
end

local function isChatMessageFromPlayer(channel, unit, isHostile, name, message, speakerInChatBound, specifyName, factionName, trialPosition)
  local playerName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))
  if playerName == name then
    if message == "!log" then
      printLoot()
    end
    if message == "!reset" then
      reset()
      lazyLogging("Succesfully reset.")
    end
  end
end

api.On("UPDATE", calledOnUpdate)

function pveWindowTesting:OnEvent(event, ...)
  --debugLogging(event)
  if event == "EXP_CHANGED" then
    calledOnExpChange(unpack(arg))
  elseif event == "LABORPOWER_CHANGED" then
    if arg ~= nil then
      calledOnLabourChange(unpack(arg))
    end
  elseif event == "ADDED_ITEM" then
    calledOnAddedItem(unpack(arg))
  end
end

pveWindowTesting:SetHandler("OnEvent", pveWindowTesting.OnEvent)


local function OnLoad()
  api.Log:Info("Loaded PvE Buddy vPRERELEASEWTF")
  api.Log:Info("!log to see your loot log")
  api.Log:Info("!reset to reset your loot log")
  pveWindowTesting:RegisterEvent("EXP_CHANGED")
  pveWindowTesting:RegisterEvent("LABORPOWER_CHANGED")
  pveWindowTesting:RegisterEvent("ADDED_ITEM")
  pveWindowTesting:Show(false)
  pveWindowTesting:AddAnchor("TOPLEFT", "UIParent", 50, 50)

  --Temporary lazy debug
  api.On("CHAT_MESSAGE", isChatMessageFromPlayer)
end


local function OnUnload()
  api.Log:Info("Unloaded PvE Buddy")
  pveWindowTesting:ReleaseHandler("OnEvent")
  pveWindowTesting:Show(false)
  pveWindowTesting = nil
  reset()
end

pve_buddy_addon.OnUnload = OnUnload
pve_buddy_addon.OnLoad = OnLoad

return pve_buddy_addon

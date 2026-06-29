-- RTG_ParagonDisplay.lua (WotLK 3.3.5a)
-- v2.1.0 - Server-query build with player/rndbot tooltip support
--
-- Requires server responder in mod-paragon-levels:
--   Client whisper LANG_ADDON:  "RTG_PARAGON\tQ:<name>"
--   Server legacy reply:        "RTG_PARAGON\tA:<name>:<paragon>"
--   Server extended reply:      "RTG_PARAGON\tB:<name>:<paragon>:<kind>"
--
-- kind values:
--   real        = normal player
--   rndbot      = Playerbots random bot
--   addclassbot = Playerbots AddClass/generated helper bot
--   bot         = bot session, exact bot subtype unknown

RTG_PARAGON_PREFIX = "RTG_PARAGON"
RTG_PARAGON_LABEL  = "Paragon Level: "
RTG_PARAGON_TICK   = 0.12          -- update cadence for target/focus refresh
RTG_PARAGON_REQ_THROTTLE = 0.50    -- seconds between requests per name
RTG_PARAGON_CACHE_TTL    = 30.0    -- seconds before cached values expire

local function msg(s)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[RTG Paragon]|r " .. tostring(s))
end

local function Now()
  return GetTime()
end

-- Cache: cache[name] = { lvl = number, kind = string, t = time() }
local cache = {}
local lastReq = {}

local function NormalizeKind(kind)
  if kind == "rndbot" or kind == "addclassbot" or kind == "bot" or kind == "real" then
    return kind
  end
  return "real"
end

local function CacheGet(name)
  local e = name and cache[name]
  if not e then return nil end
  if (Now() - e.t) > RTG_PARAGON_CACHE_TTL then
    cache[name] = nil
    return nil
  end
  return e
end

local function CacheSet(name, lvl, kind)
  if not name or name == "" then return end
  cache[name] = { lvl = tonumber(lvl) or 0, kind = NormalizeKind(kind), t = Now() }
end

local function EnsurePrefix()
  if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(RTG_PARAGON_PREFIX)
  end
end

-- Server expects WHISPER to ourselves (server replies back the same way)
local function RequestParagon(name)
  if not name or name == "" then return end

  local t = Now()
  if lastReq[name] and (t - lastReq[name]) < RTG_PARAGON_REQ_THROTTLE then
    return
  end
  lastReq[name] = t

  local me = UnitName("player")
  if not me or me == "" then return end

  -- SendAddonMessage(prefix, message, channel, target)
  SendAddonMessage(RTG_PARAGON_PREFIX, "Q:" .. name, "WHISPER", me)
end

-- ------------------------------- Text helpers -------------------------------

local function IsBotKind(kind)
  return kind == "rndbot" or kind == "addclassbot" or kind == "bot"
end

local function KindDisplay(kind)
  if kind == "rndbot" then
    return "Random Bot"
  end
  if kind == "addclassbot" then
    return "AddClass Bot"
  end
  if kind == "bot" then
    return "Playerbot"
  end
  return "Real Player"
end

local function KindColor(kind)
  if kind == "rndbot" then
    return 1.0, 0.82, 0.0
  end
  if kind == "addclassbot" then
    return 0.8, 0.6, 1.0
  end
  if kind == "bot" then
    return 1.0, 0.65, 0.2
  end
  return 0.2, 1.0, 0.2
end

local function BuildUnitFrameText(info)
  if not info then return "" end

  local text = RTG_PARAGON_LABEL .. tostring(info.lvl or 0)

  -- Keep real players exactly as before. Only bots get the extra line under Paragon.
  if IsBotKind(info.kind) then
    text = text .. "\nBot: " .. KindDisplay(info.kind)
  end

  return text
end

local function AddInfoTooltipLines(tooltip, info)
  if not tooltip or not info then return end

  tooltip:AddLine(RTG_PARAGON_LABEL .. tostring(info.lvl or 0), 0.4, 0.8, 1.0)

  local r, g, b = KindColor(info.kind)
  tooltip:AddLine("Player Type: " .. KindDisplay(info.kind), r, g, b)
end

-- ------------------------------- UI helpers -------------------------------

local function EnsureUnitParagonFS(frame, nameFS)
  if frame.__rtgParagonFS then return frame.__rtgParagonFS end
  if not frame or not nameFS then return nil end

  -- Create a small overlay frame ABOVE the target/focus artwork so our text can't be buried.
  if not frame.__rtgParagonOverlay then
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    frame.__rtgParagonOverlay = overlay
  end

  local parent = frame.__rtgParagonOverlay or frame

  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetDrawLayer("OVERLAY", 7) -- top of overlay layer
  fs:SetJustifyH("CENTER")

  local font, size, flags = nameFS:GetFont()
  -- Keep the same font but add OUTLINE for readability
  fs:SetFont(font, size, "OUTLINE")

  fs:ClearAllPoints()
  fs:SetPoint("BOTTOM", nameFS, "TOP", 0, 3)

  fs:SetText("")
  fs:Hide()

  frame.__rtgParagonFS = fs
  return fs
end

local function SetUnitFrameParagon(frame, nameFS, unit)
  if not frame or not nameFS or not unit then return end

  local rawName = UnitName(unit)
  if not rawName or rawName == "" then
    if frame.__rtgParagonFS then frame.__rtgParagonFS:Hide() end
    return
  end

  local fs = EnsureUnitParagonFS(frame, nameFS)
  if not fs then return end

  local info = CacheGet(rawName)
  if info == nil then
    RequestParagon(rawName)
    fs:Hide()
    return
  end

  fs:SetText(BuildUnitFrameText(info))
  fs:Show()
end

-- ------------------------------- Tooltip hook -------------------------------

local tooltipGuard = false
GameTooltip:HookScript("OnTooltipSetUnit", function(self)
  if tooltipGuard then return end
  tooltipGuard = true

  local _, unit = self:GetUnit()
  if not unit or not UnitIsPlayer(unit) then
    tooltipGuard = false
    return
  end

  local name = UnitName(unit)
  if not name or name == "" then
    tooltipGuard = false
    return
  end

  local info = CacheGet(name)
  if info == nil then
    RequestParagon(name)
    tooltipGuard = false
    return
  end

  AddInfoTooltipLines(self, info)
  self:Show()

  tooltipGuard = false
end)

-- ------------------------------- Who list tooltip -------------------------------

local currentWhoButton = nil
local currentWhoName = nil

local function GetWhoButtonIndex(button)
  if not button then return nil end

  local id = button:GetID()
  if not id or id <= 0 then
    local buttonName = button:GetName()
    if buttonName then
      id = tonumber(buttonName:match("WhoFrameButton(%d+)"))
    end
  end

  if not id or id <= 0 then return nil end

  local offset = 0
  if FauxScrollFrame_GetOffset and WhoListScrollFrame then
    offset = FauxScrollFrame_GetOffset(WhoListScrollFrame) or 0
  end

  return offset + id
end

local function GetWhoButtonName(button)
  local index = GetWhoButtonIndex(button)
  if index and GetWhoInfo then
    local name = GetWhoInfo(index)
    if name and name ~= "" then
      return name
    end
  end

  local buttonName = button and button:GetName()
  if buttonName then
    local fs = _G[buttonName .. "Name"]
    if fs and fs.GetText then
      local text = fs:GetText()
      if text and text ~= "" then return text end
    end
  end

  if button and button.name and button.name.GetText then
    local text = button.name:GetText()
    if text and text ~= "" then return text end
  end

  return nil
end

local function ShowWhoTooltip(button)
  local name = GetWhoButtonName(button)
  if not name or name == "" then return end

  currentWhoButton = button
  currentWhoName = name

  local info = CacheGet(name)
  if info == nil then
    RequestParagon(name)
  end

  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(name, 1.0, 0.82, 0.0)

  if info then
    AddInfoTooltipLines(GameTooltip, info)
  else
    GameTooltip:AddLine("RTG info: loading...", 0.7, 0.7, 0.7)
  end

  GameTooltip:Show()
end

local function RefreshWhoTooltip(name)
  if not currentWhoButton or not currentWhoName or currentWhoName ~= name then return end
  if not GameTooltip:IsShown() then return end
  ShowWhoTooltip(currentWhoButton)
end

local function HideWhoTooltip(button)
  if button == currentWhoButton then
    currentWhoButton = nil
    currentWhoName = nil
    GameTooltip:Hide()
  end
end

local function HookWhoFrameButtons()
  local count = WHOFRAME_NUM_BUTTONS or 17
  for i = 1, count do
    local button = _G["WhoFrameButton" .. i]
    if button and not button.__rtgParagonHooked then
      button:HookScript("OnEnter", ShowWhoTooltip)
      button:HookScript("OnLeave", HideWhoTooltip)
      button.__rtgParagonHooked = true
    end
  end
end

-- ------------------------------- Events / update loop -------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("CHAT_MSG_ADDON")
loader:RegisterEvent("PLAYER_TARGET_CHANGED")
loader:RegisterEvent("PLAYER_FOCUS_CHANGED")
loader:RegisterEvent("WHO_LIST_UPDATE")

loader:SetScript("OnEvent", function(_, event, a, b, c, d)
  if event == "PLAYER_LOGIN" then
    EnsurePrefix()
    HookWhoFrameButtons()

    if WhoFrame then
      WhoFrame:HookScript("OnShow", HookWhoFrameButtons)
    end

    if FriendsFrame then
      FriendsFrame:HookScript("OnShow", HookWhoFrameButtons)
    end

    if type(WhoList_Update) == "function" then
      hooksecurefunc("WhoList_Update", HookWhoFrameButtons)
    end

    msg("Loaded v2.1.0 (paragon + playerbot tooltips).")
    return
  end

  if event == "WHO_LIST_UPDATE" then
    HookWhoFrameButtons()
    if currentWhoName then
      RefreshWhoTooltip(currentWhoName)
    end
    return
  end

  if event == "CHAT_MSG_ADDON" then
    local prefix = a
    local message = b
    -- channel=c, sender=d (not needed)

    if prefix ~= RTG_PARAGON_PREFIX then return end
    if type(message) ~= "string" then return end

    -- Extended message format from server: "B:<name>:<paragon>:<kind>"
    local name, lvl, kind = message:match("^B:([^:]+):(%d+):([^:]+)$")
    if name and lvl and kind then
      CacheSet(name, lvl, kind)

      -- If the unit is currently target/focus, refresh immediately
      if UnitExists("target") and UnitIsPlayer("target") and UnitName("target") == name then
        if TargetFrame and TargetFrame.name then
          SetUnitFrameParagon(TargetFrame, TargetFrame.name, "target")
        end
      end
      if UnitExists("focus") and UnitIsPlayer("focus") and UnitName("focus") == name then
        if FocusFrame and FocusFrame.name then
          SetUnitFrameParagon(FocusFrame, FocusFrame.name, "focus")
        end
      end

      RefreshWhoTooltip(name)
      return
    end

    -- Legacy message format from server: "A:<name>:<paragon>"
    name, lvl = message:match("^A:([^:]+):(%d+)$")
    if name and lvl then
      local existing = CacheGet(name)
      CacheSet(name, lvl, existing and existing.kind or "real")

      -- If the unit is currently target/focus, refresh immediately
      if UnitExists("target") and UnitIsPlayer("target") and UnitName("target") == name then
        if TargetFrame and TargetFrame.name then
          SetUnitFrameParagon(TargetFrame, TargetFrame.name, "target")
        end
      end
      if UnitExists("focus") and UnitIsPlayer("focus") and UnitName("focus") == name then
        if FocusFrame and FocusFrame.name then
          SetUnitFrameParagon(FocusFrame, FocusFrame.name, "focus")
        end
      end

      RefreshWhoTooltip(name)
    end
    return
  end

  if event == "PLAYER_TARGET_CHANGED" then
    if UnitExists("target") and UnitIsPlayer("target") then
      local name = UnitName("target")
      if name then RequestParagon(name) end
      if TargetFrame and TargetFrame.name then
        SetUnitFrameParagon(TargetFrame, TargetFrame.name, "target")
      end
    else
      if TargetFrame and TargetFrame.__rtgParagonFS then
        TargetFrame.__rtgParagonFS:Hide()
      end
    end
    return
  end

  if event == "PLAYER_FOCUS_CHANGED" then
    if UnitExists("focus") and UnitIsPlayer("focus") then
      local name = UnitName("focus")
      if name then RequestParagon(name) end
      if FocusFrame and FocusFrame.name then
        SetUnitFrameParagon(FocusFrame, FocusFrame.name, "focus")
      end
    else
      if FocusFrame and FocusFrame.__rtgParagonFS then
        FocusFrame.__rtgParagonFS:Hide()
      end
    end
    return
  end
end)

-- Keep frames refreshed (covers cases where nameFS updates after we receive cache)
local acc = 0
loader:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < RTG_PARAGON_TICK then return end
  acc = 0

  if UnitExists("target") and UnitIsPlayer("target") and TargetFrame and TargetFrame.name then
    SetUnitFrameParagon(TargetFrame, TargetFrame.name, "target")
  end

  if UnitExists("focus") and UnitIsPlayer("focus") and FocusFrame and FocusFrame.name then
    SetUnitFrameParagon(FocusFrame, FocusFrame.name, "focus")
  end
end)

-- Also refresh when the default target frame does its own updates
hooksecurefunc("TargetFrame_Update", function()
  if UnitExists("target") and UnitIsPlayer("target") and TargetFrame and TargetFrame.name then
    SetUnitFrameParagon(TargetFrame, TargetFrame.name, "target")
  end
end)

-- RTG_ParagonDisplay.lua (WotLK 3.3.5a)
-- v2.2.0 - Server-query build with player/rndbot tooltip support + Who List bot filter
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
RTG_PARAGON_CACHE_TTL    = 120.0   -- seconds before cached values expire
RTG_PARAGON_WHO_FILTER_DEFAULT = false -- false = show bots unless player chooses to hide them

local function msg(s)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[RTG Paragon]|r " .. tostring(s))
end

local function Now()
  return GetTime()
end

local function Trim(value)
  value = tostring(value or "")
  return value:match("^%s*(.-)%s*$") or ""
end

local function EnsureDB()
  if type(RTGParagonDisplayDB) ~= "table" then
    RTGParagonDisplayDB = {}
  end

  if RTGParagonDisplayDB.hideWhoBots == nil then
    RTGParagonDisplayDB.hideWhoBots = RTG_PARAGON_WHO_FILTER_DEFAULT and true or false
  end

  return RTGParagonDisplayDB
end

local function WhoBotsHidden()
  local db = EnsureDB()
  return db.hideWhoBots == true
end

local function SetWhoBotsHidden(hidden, quiet)
  local db = EnsureDB()
  db.hideWhoBots = hidden and true or false

  -- These functions are defined later in the file; guard so login-time calls are safe.
  if type(UpdateWhoToggleButton) == "function" then
    UpdateWhoToggleButton()
  end

  if type(RefreshWhoListForBotFilter) == "function" then
    RefreshWhoListForBotFilter()
  end

  if not quiet then
    if db.hideWhoBots then
      msg("/who random bots are now hidden. Use /rtgwho show to show them again.")
    else
      msg("/who random bots are now shown. Use /rtgwho hide to hide them again.")
    end
  end
end

local function ToggleWhoBotsHidden()
  SetWhoBotsHidden(not WhoBotsHidden(), false)
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

-- -------------------------- Who list tooltip / filter --------------------------

local currentWhoButton = nil
local currentWhoName = nil
local whoToggleButton = nil
local whoFilterApplying = false

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

local function GetWhoResultCount()
  if not GetNumWhoResults then return 0, 0 end

  local shown, total = GetNumWhoResults()
  return tonumber(shown) or 0, tonumber(total) or tonumber(shown) or 0
end

local function PrimeWhoCache()
  if not GetWhoInfo then return end

  local shown = GetWhoResultCount()
  for i = 1, shown do
    local name = GetWhoInfo(i)
    if name and name ~= "" and CacheGet(name) == nil then
      RequestParagon(name)
    end
  end
end

local function IsWhoNameHiddenBot(name)
  if not WhoBotsHidden() then return false end
  if not name or name == "" then return false end

  local info = CacheGet(name)
  if info == nil then
    RequestParagon(name)
    -- Unknown names stay visible until the server identifies them.
    -- This prevents real players from disappearing before metadata arrives.
    return false
  end

  return IsBotKind(info.kind)
end

function UpdateWhoToggleButton()
  if not whoToggleButton then return end

  if WhoBotsHidden() then
    whoToggleButton:SetText("Bots: Hidden")
  else
    whoToggleButton:SetText("Bots: Shown")
  end
end

local function ShowWhoToggleTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("RTG Who List Bot Filter", 0.4, 0.8, 1.0)
  GameTooltip:AddLine("Click to toggle random/playerbot rows in /who.", 1.0, 1.0, 1.0)
  GameTooltip:AddLine("Unknown names stay visible until RTG identifies them.", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Slash: /rtgwho hide, /rtgwho show, /rtgwho toggle", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

local function HideWhoToggleTooltip()
  GameTooltip:Hide()
end

local function EnsureWhoToggleButton()
  if not WhoFrame or whoToggleButton then
    return
  end

  whoToggleButton = CreateFrame("Button", "RTGParagonWhoBotToggleButton", WhoFrame, "UIPanelButtonTemplate")
  whoToggleButton:SetWidth(105)
  whoToggleButton:SetHeight(22)
  whoToggleButton:SetPoint("BOTTOMRIGHT", WhoFrame, "BOTTOMRIGHT", -36, 83)
  whoToggleButton:SetScript("OnClick", ToggleWhoBotsHidden)
  whoToggleButton:SetScript("OnEnter", ShowWhoToggleTooltip)
  whoToggleButton:SetScript("OnLeave", HideWhoToggleTooltip)
  whoToggleButton:Show()

  UpdateWhoToggleButton()
end

local function ApplyWhoListBotFilter()
  if whoFilterApplying then return end
  whoFilterApplying = true

  HookWhoFrameButtons()
  EnsureWhoToggleButton()
  PrimeWhoCache()

  if WhoBotsHidden() then
    local count = WHOFRAME_NUM_BUTTONS or 17
    for i = 1, count do
      local button = _G["WhoFrameButton" .. i]
      if button and button:IsShown() then
        local name = GetWhoButtonName(button)
        if IsWhoNameHiddenBot(name) then
          if currentWhoButton == button then
            HideWhoTooltip(button)
          end
          button:Hide()
        end
      end
    end
  end

  whoFilterApplying = false
end

function RefreshWhoListForBotFilter()
  -- Let Blizzard's WhoList_Update redraw the rows first so turning the filter off
  -- restores any hidden bot rows cleanly, then our secure hook reapplies hiding if needed.
  if type(WhoList_Update) == "function" and WhoFrame and WhoFrame:IsShown() then
    WhoList_Update()
  else
    ApplyWhoListBotFilter()
  end
end

local function ShowWhoTooltip(button)
  local name = GetWhoButtonName(button)
  if not name or name == "" then return end
  if IsWhoNameHiddenBot(name) then return end

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

function HideWhoTooltip(button)
  if button == currentWhoButton then
    currentWhoButton = nil
    currentWhoName = nil
    GameTooltip:Hide()
  end
end

function HookWhoFrameButtons()
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

-- ------------------------------- Slash commands -------------------------------

SLASH_RTGWHO1 = "/rtgwho"
SLASH_RTGWHO2 = "/whohidebots"
SlashCmdList["RTGWHO"] = function(command)
  command = ToLowerAscii(Trim(command or ""))

  if command == "" or command == "toggle" then
    ToggleWhoBotsHidden()
    return
  end

  if command == "hide" or command == "off" then
    SetWhoBotsHidden(true, false)
    return
  end

  if command == "show" or command == "on" then
    SetWhoBotsHidden(false, false)
    return
  end

  if command == "status" then
    msg("/who random bots are currently " .. (WhoBotsHidden() and "hidden." or "shown."))
    return
  end

  msg("Use: /rtgwho toggle, /rtgwho hide, /rtgwho show, or /rtgwho status")
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
    EnsureDB()
    HookWhoFrameButtons()
    EnsureWhoToggleButton()

    if WhoFrame then
      WhoFrame:HookScript("OnShow", function()
        HookWhoFrameButtons()
        EnsureWhoToggleButton()
        ApplyWhoListBotFilter()
      end)
    end

    if FriendsFrame then
      FriendsFrame:HookScript("OnShow", function()
        HookWhoFrameButtons()
        EnsureWhoToggleButton()
        ApplyWhoListBotFilter()
      end)
    end

    if type(WhoList_Update) == "function" then
      hooksecurefunc("WhoList_Update", ApplyWhoListBotFilter)
    end

    msg("Loaded v2.2.0 (paragon + playerbot tooltips + /who bot filter).")
    return
  end

  if event == "WHO_LIST_UPDATE" then
    ApplyWhoListBotFilter()
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

      ApplyWhoListBotFilter()
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

      ApplyWhoListBotFilter()
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

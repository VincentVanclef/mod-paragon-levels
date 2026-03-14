-- RTG_ParagonDisplay.lua (WotLK 3.3.5a)
-- v2.0.1 - Server-query build (NO +N name parsing)
--
-- Requires server responder in mod-paragon-levels:
--   Client whisper LANG_ADDON:  "RTG_PARAGON\tQ:<name>"
--   Server reply  LANG_ADDON:  "RTG_PARAGON\tA:<name>:<paragon>"

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

-- Cache: cache[name] = { lvl = number, t = time() }
local cache = {}
local lastReq = {}

local function CacheGet(name)
  local e = name and cache[name]
  if not e then return nil end
  if (Now() - e.t) > RTG_PARAGON_CACHE_TTL then
    cache[name] = nil
    return nil
  end
  return e.lvl
end

local function CacheSet(name, lvl)
  if not name or name == "" then return end
  cache[name] = { lvl = tonumber(lvl) or 0, t = Now() }
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

  local p = CacheGet(rawName)
  if p == nil then
    RequestParagon(rawName)
    fs:Hide()
    return
  end

  fs:SetText(RTG_PARAGON_LABEL .. p)
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

  local p = CacheGet(name)
  if p == nil then
    RequestParagon(name)
    tooltipGuard = false
    return
  end

  self:AddLine(RTG_PARAGON_LABEL .. p, 0.4, 0.8, 1.0)
  self:Show()

  tooltipGuard = false
end)

-- ------------------------------- Events / update loop -------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("CHAT_MSG_ADDON")
loader:RegisterEvent("PLAYER_TARGET_CHANGED")
loader:RegisterEvent("PLAYER_FOCUS_CHANGED")

loader:SetScript("OnEvent", function(_, event, a, b, c, d)
  if event == "PLAYER_LOGIN" then
    EnsurePrefix()
    msg("Loaded v2.0.1 (server-query).")
    return
  end

  if event == "CHAT_MSG_ADDON" then
    local prefix = a
    local message = b
    -- channel=c, sender=d (not needed)

    if prefix ~= RTG_PARAGON_PREFIX then return end
    if type(message) ~= "string" then return end

    -- Message format from server: "A:<name>:<paragon>"
    local name, lvl = message:match("^A:([^:]+):(%d+)$")
    if name and lvl then
      CacheSet(name, lvl)

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
-- adds class colored circles on world and battlefield map
pfUI:RegisterModule("mapcolors", function ()
  local button_cache = {}

  local function Initialize(unit_button_name)
    local texture_size = tonumber(C.appearance.worldmap.groupcircles)
    for i=1, MAX_PARTY_MEMBERS do
      local frame_name = unit_button_name.."Party"..i
      local frame = _G[frame_name]
      frame.icon = _G[frame_name.."Icon"]
      frame.icon:SetTexture(pfUI.media["img:circleparty"])
      frame.icon:SetVertexColor(.5, 1, .5)
      SetAllPointsOffset(frame.icon, frame, texture_size, -texture_size)
      -- populate cache to default values
      button_cache[frame_name] = {
        r = .5, g = 1, b = .5
      }
    end

    for i=1, MAX_RAID_MEMBERS do
      local frame_name = unit_button_name.."Raid"..i
      local frame = _G[frame_name]
      frame.icon = _G[frame_name.."Icon"]
      frame.icon:SetTexture(pfUI.media["img:circleraid"])
      frame.icon:SetVertexColor(.5, 1, .5)
      SetAllPointsOffset(frame.icon, frame, texture_size, -texture_size)
      -- populate cache to default values
      button_cache[frame_name] = {
        inParty = false,
        r = .5, g = 1, b = .5
      }
    end
  end

  local function GetTextureColor(frame)
    if UnitExists(frame.unit) then
      local _, class = UnitClass(frame.unit)
      local color = RAID_CLASS_COLORS[class]
      return color.r, color.g, color.b
    else
      return .5, 1, .5
    end
  end

  local function UpdateTexture(frame, inParty)
    if inParty then
      frame.icon:SetTexture(pfUI.media["img:circleparty"])
    else
      frame.icon:SetTexture(pfUI.media["img:circleraid"])
    end
  end

  local function UpdateUnitFrames(unit_button_name)
    if GetNumRaidMembers() > 0 then
      for i=1, MAX_RAID_MEMBERS do
        local frame_name = unit_button_name.."Raid"..i
        local frame = _G[frame_name]
        local cache = button_cache[frame_name]
        if frame.unit then
          local inParty = UnitInParty(frame.unit)
          if inParty ~= cache.inParty then
            cache.inParty = inParty
            UpdateTexture(frame, cache.inParty)
          end
          local r, g, b = GetTextureColor(frame)
          if r ~= cache.r or g ~= cache.g or b ~= cache.b then
            cache.r, cache.g, cache.b = r, g, b
            frame.icon:SetVertexColor(cache.r, cache.g, cache.b)
          end
        end
      end
    elseif GetNumPartyMembers() > 0 then
      for i=1, MAX_PARTY_MEMBERS do
        local frame_name = unit_button_name.."Party"..i
        local frame = _G[frame_name]
        local cache = button_cache[frame_name]
        if frame.unit then
          local r, g, b = GetTextureColor(frame)
          if r ~= cache.r or g ~= cache.g or b ~= cache.b then
            cache.r, cache.g, cache.b = r, g, b
            frame.icon:SetVertexColor(cache.r, cache.g, cache.b)
          end
        end
      end
    end
  end

  -- returns the tooltip text for this map button, or nil when we can't resolve
  -- one. The name is re-read on every hover: caching it on the button pins the
  -- first player who ever used that party/raid slot, so a later group shows the
  -- previous members' names. UnitName also gives the raw, uncolored string, so
  -- there's no |c...|r layer to nest.
  local function ColorizeName(frame)
    local _, class = UnitClass(frame.unit)
    local color = RAID_CLASS_COLORS[class]
    local rawname = UnitName(frame.unit)
    -- battleground team members have no unit token; the client already put
    -- their plain name on the button, so hand that back untouched
    if not color or not rawname then return frame.name end
    frame.name = '|c'..color.colorStr..rawname..'|r'
    return frame.name
  end

  local function AppendName(tooltipText, frame)
    local name = ColorizeName(frame)
    if not name then return tooltipText end
    if tooltipText == "" then return name end
    return tooltipText.."\n"..name
  end

  local function UpdateUnitColors(unit_button_name, tooltip)
    local tooltipText = ""
    if unit_button_name == 'WorldMap' then
      -- check player
      if MouseIsOver(WorldMapPlayer) then
        tooltipText = AppendName(tooltipText, WorldMapPlayer)
      end
    end

    -- check party
    for i=1, MAX_PARTY_MEMBERS do
      local frame = _G[unit_button_name.."Party"..i]
      if frame:IsVisible() and MouseIsOver(frame) then
        tooltipText = AppendName(tooltipText, frame)
      end
    end

    --check Raid
    for i=1, MAX_RAID_MEMBERS do
      local frame = _G[unit_button_name.."Raid"..i]
      if frame:IsVisible() and MouseIsOver(frame) then
        tooltipText = AppendName(tooltipText, frame)
      end
    end

    tooltip:SetText(tooltipText)
    tooltip:Show()
  end

  -- WorldMap
  Initialize('WorldMap')
  hooksecurefunc('WorldMapButton_OnUpdate', function()
    if ( this.tick or .5) > GetTime() then return else this.tick = GetTime() + .5 end
    UpdateUnitFrames('WorldMap')
  end)

  if C.appearance.worldmap.colornames == "1" then
    hooksecurefunc('WorldMapUnit_OnEnter', function()
      if ( this.tick or .5) > GetTime() then return else this.tick = GetTime() + .5 end
      UpdateUnitColors('WorldMap', WorldMapTooltip)
    end)
  end

  -- BattlefieldMinimap
  HookAddonOrVariable("Blizzard_BattlefieldMinimap", function()
    Initialize('BattlefieldMinimap')

    hooksecurefunc('BattlefieldMinimap_OnUpdate', function()
      if ( this.tick or .5) > GetTime() then return else this.tick = GetTime() + .5 end
      UpdateUnitFrames('BattlefieldMinimap')
    end)

    if C.appearance.worldmap.colornames == "1" then
      hooksecurefunc('BattlefieldMinimapUnit_OnEnter', function()
        if ( this.tick or .5) > GetTime() then return else this.tick = GetTime() + .5 end
        UpdateUnitColors('BattlefieldMinimap', GameTooltip)
      end)
    end
  end)
end)

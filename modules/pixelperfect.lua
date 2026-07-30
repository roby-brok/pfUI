pfUI:RegisterModule("pixelperfect", "vanilla:tbc", function ()
  -- pre-calculated min values
  local statics = {
    [4] = 1.4222222222222,
    [5] = 1.1377777777778,
    [6] = 0.94814814814815,
    [7] = 0.81269841269841,
    [8] = 0.71111111111111,
  }

  -- pixel perfect
  local function pixelperfect()
    local conf = tonumber(C.global.pixelperfect)
    local target

    if conf < 4 then
      -- restore gamesettings
      local scale = GetCVar("uiScale")
      local use = GetCVar("useUiScale")

      -- GetCVar returns strings; when the user has UI scaling enabled, restore
      -- their configured uiScale, otherwise fall back to 0.9
      target = use == "1" and (tonumber(scale) or .9) or .9
    else
      target = statics[conf] or 1

      SetCVar("uiScale", target)
      SetCVar("useUiScale", 1)
    end

    if UIParent:GetScale() ~= target then
      UIParent:SetScale(target)

      -- GetPerfectPixel caches a real pixel for the scale that was active when
      -- it first ran. Drop that cache (and every border size derived from it)
      -- so frames built after this point measure against the new scale.
      pfUI.pixel = nil
      pfUI.borders = nil
    end
  end

  -- pixelperfect: native UIScale listener
  if tonumber(C.global.pixelperfect) > 0 then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", pixelperfect)
    pixelperfect()
  end

  pfUI.pixelperfect = {
    UpdateConfig = pixelperfect
  }
end)

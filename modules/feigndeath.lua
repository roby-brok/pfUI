pfUI:RegisterModule("feigndeath", "vanilla:tbc", function ()
  local cache = { }
  local scanner = libtipscan:GetScanner("feigndeath")
  local healthbar = scanner:GetChildren()

  local cache_update = CreateFrame("Frame")
  cache_update:RegisterEvent("UNIT_HEALTH")
  cache_update:RegisterEvent("PLAYER_TARGET_CHANGED")
  cache_update:SetScript("OnEvent", function()
    if event == "PLAYER_TARGET_CHANGED" and UnitIsDead("target") then
      scanner:SetUnit("target")
      cache[UnitName("target")] = healthbar:GetValue()
    elseif event == "UNIT_HEALTH" and UnitIsDead(arg1) and UnitName(arg1) then
      scanner:SetUnit(arg1)
      cache[UnitName(arg1)] = healthbar:GetValue()
    elseif event == "UNIT_HEALTH" and UnitName(arg1) then
      cache[UnitName(arg1)] = nil
    end
  end)

  local oldUnitHealth = UnitHealth
  -- must be the real global: modules run setfenv'd to pfUI.env, which has no
  -- __newindex, so a bare assignment only overrides UnitHealth for other
  -- modules. api/unitframes.lua and libs/libhealth.lua -- the code that actually
  -- feeds the unit frames -- are not setfenv'd and read _G.UnitHealth.
  _G.UnitHealth = function(arg)
    if UnitIsDead(arg) and cache[UnitName(arg)] then
      return cache[UnitName(arg)]
    else
      return oldUnitHealth(arg)
    end
  end
end)

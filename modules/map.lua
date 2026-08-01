pfUI:RegisterModule("map", "vanilla:tbc", function ()
  table.insert(UISpecialFrames, "WorldMapFrame")

  local function UpdateTooltipScale()
    -- load scale data
    local tooltipscale = tonumber(C.appearance.worldmap.tooltipsize)
    local scale = WorldMapFrame:GetScale()

    -- apply tooltip scale
    if tooltipscale > 0 then
      WorldMapTooltip:SetScale(tooltipscale/scale)
    else
      WorldMapTooltip:SetScale(1)
    end
  end

  -- hook SetMapToCurrentZone to allow suppression
  local pfOrigSetMapToCurrentZone = _G.SetMapToCurrentZone
  _G.SetMapToCurrentZone = function()
    if C.appearance.worldmap.autozoneswitch == "0" and WorldMapFrame:IsShown() then return end
    pfOrigSetMapToCurrentZone()
  end

  -- register config update handler
  pfUI.map = { UpdateConfig = UpdateTooltipScale }

  function _G.ToggleWorldMap()
    if WorldMapFrame:IsShown() then
      WorldMapFrame:Hide()
    else
      WorldMapFrame:Show()
    end
  end

  C.position["WorldMapFrame"] = C.position["WorldMapFrame"] or { alpha = 1.0, scale = 0.7 }
  C.position["WorldMapFrame"].parent = nil
  local alpha = C.position["WorldMapFrame"].alpha
  local scale = C.position["WorldMapFrame"].scale

  -- [ world map zoom & pan ]
  -- Retail style map navigation. The map contents are moved into a scrollframe,
  -- which is the only vanilla widget that clips its children. The window itself
  -- keeps its size, only the canvas inside of it gets scaled (mousewheel, kept
  -- anchored at the cursor) and moved around (left click drag).
  local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 1, 6, 1.25
  local zoom, panx, pany = 1, 0, 0
  local basew, baseh = 0, 0

  local function ApplyMapZoom()
    if not pfUI.map.canvas then return end

    zoom = clamp(zoom, ZOOM_MIN, ZOOM_MAX)
    panx = clamp(panx, 0, basew - basew/zoom)
    pany = clamp(pany, 0, baseh - baseh/zoom)

    -- the canvas is kept at the exact size of the viewport, so the scrollframe
    -- never scrolls on its own. all panning happens on the detail frame inside.
    pfUI.map.canvas:SetScale(zoom)
    pfUI.map.canvas:SetWidth(basew/zoom)
    pfUI.map.canvas:SetHeight(baseh/zoom)

    WorldMapDetailFrame:ClearAllPoints()
    WorldMapDetailFrame:SetPoint("TOPLEFT", pfUI.map.canvas, "TOPLEFT", -panx, pany)
  end

  local function ResetMapZoom()
    zoom, panx, pany = 1, 0, 0
    ApplyMapZoom()
  end

  local function MapZoomTo(target)
    local view = pfUI.map.view
    if not view then return end

    target = clamp(target, ZOOM_MIN, ZOOM_MAX)
    if target == zoom then return end

    -- keep whatever sits below the cursor in place while zooming. wheeling
    -- somewhere else on the window (the border, the title bar) zooms centered.
    local fx, fy = 0.5, 0.5
    if MouseIsOver(view) and view:GetLeft() then
      local scale = view:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      fx = clamp((cx/scale - view:GetLeft()) / basew, 0, 1)
      fy = clamp((view:GetTop() - cy/scale) / baseh, 0, 1)
    end

    panx = panx + fx*basew/zoom - fx*basew/target
    pany = pany + fy*baseh/zoom - fy*baseh/target
    zoom = target

    ApplyMapZoom()
  end

  local function MapWheel(delta)
    local handled = nil

    if IsShiftKeyDown() then
      alpha = clamp(WorldMapFrame:GetAlpha() + delta/10, 0.1, 1.0)
      WorldMapFrame:SetAlpha(alpha)
      -- persist: SaveMovable stores scale/position but not alpha
      C.position["WorldMapFrame"].alpha = alpha
      handled = true
    end

    if IsControlKeyDown() then
      local oldscale = WorldMapFrame:GetScale()
      local point, rel, relpoint, offx, offy = WorldMapFrame:GetPoint()
      scale = clamp(oldscale + delta/10, 0.1, 2.0)

      -- recalculate world frame position based on old and new scale
      if point == "TOPLEFT" and relpoint == "TOPLEFT" then
        offx = offx*oldscale/scale
        offy = offy*oldscale/scale
        WorldMapFrame:SetPoint(point, rel, relpoint, offx, offy)
      end

      WorldMapFrame:SetScale(scale)
      UpdateTooltipScale()
      handled = true
    end

    -- without modifiers the wheel zooms the map itself, not the window
    if not handled then
      MapZoomTo(zoom * (delta > 0 and ZOOM_STEP or 1/ZOOM_STEP))
      return
    end

    SaveMovable(WorldMapFrame, true)
  end

  local function MapPanUpdate()
    -- drop zoom and pan whenever a different map is put on display
    local file, cont, zoneid = GetMapInfo(), GetCurrentMapContinent(), GetCurrentMapZone()
    if file ~= pfUI.map.lastfile or cont ~= pfUI.map.lastcont or zoneid ~= pfUI.map.lastzone then
      pfUI.map.lastfile, pfUI.map.lastcont, pfUI.map.lastzone = file, cont, zoneid
      ResetMapZoom()
    end

    if not pfUI.map.panning then return end

    local scale = pfUI.map.canvas:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    panx = pfUI.map.startpanx - (cx/scale - pfUI.map.startx)
    pany = pfUI.map.startpany + (cy/scale - pfUI.map.starty)
    ApplyMapZoom()
  end

  local function SetupMapZoom()
    if C.appearance.worldmap.mousezoom == "0" then return end
    if not WorldMapDetailFrame or not WorldMapButton then return end

    if pfUI.map.canvas then
      -- follow along if the client resized the map area in the meantime
      if WorldMapDetailFrame:GetWidth() ~= basew or WorldMapDetailFrame:GetHeight() ~= baseh then
        basew, baseh = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
        pfUI.map.anchor:SetWidth(basew)
        pfUI.map.anchor:SetHeight(baseh)
        ResetMapZoom()
      end
      return
    end

    basew, baseh = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
    if basew < 1 or baseh < 1 then return end

    -- keep the original frame levels, so the map keeps stacking the same way
    -- against the remaining children of the world map window.
    local detaillevel = WorldMapDetailFrame:GetFrameLevel()
    local buttonlevel = WorldMapButton:GetFrameLevel()

    -- placeholder that keeps the map area where the client had put it
    local anchor = CreateFrame("Frame", "pfWorldMapAnchor", WorldMapFrame)
    for i = 1, WorldMapDetailFrame:GetNumPoints() do
      local point, rel, relpoint, x, y = WorldMapDetailFrame:GetPoint(i)
      anchor:SetPoint(point, rel or WorldMapFrame, relpoint, x, y)
    end
    if anchor:GetNumPoints() == 0 and WorldMapDetailFrame:GetLeft() and WorldMapFrame:GetLeft() then
      -- no anchors to copy, fall back to the current on-screen offset
      anchor:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT",
        WorldMapDetailFrame:GetLeft() - WorldMapFrame:GetLeft(),
        WorldMapDetailFrame:GetTop() - WorldMapFrame:GetTop())
    end

    anchor:SetWidth(basew)
    anchor:SetHeight(baseh)

    local view = CreateFrame("ScrollFrame", "pfWorldMapView", WorldMapFrame)
    view:SetAllPoints(anchor)
    view:SetFrameLevel(detaillevel)

    local canvas = CreateFrame("Frame", "pfWorldMapCanvas", view)
    canvas:SetWidth(basew)
    canvas:SetHeight(baseh)
    canvas:SetFrameLevel(detaillevel)
    view:SetScrollChild(canvas)

    pfUI.map.anchor, pfUI.map.view, pfUI.map.canvas = anchor, view, canvas

    -- move the map contents into the clipped canvas. everything that draws on
    -- the map (blizzard POIs, player arrow, pfQuest nodes, map reveal) lives
    -- inside those two frames and follows along on its own.
    WorldMapDetailFrame:SetParent(canvas)
    WorldMapDetailFrame:ClearAllPoints()
    WorldMapDetailFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    WorldMapDetailFrame:SetFrameLevel(detaillevel)

    WorldMapButton:SetParent(canvas)
    WorldMapButton:ClearAllPoints()
    WorldMapButton:SetAllPoints(WorldMapDetailFrame)
    WorldMapButton:SetFrameLevel(buttonlevel)

    -- some clients keep the blizzard POI/blob layer next to the detail frame
    -- instead of inside it. only adopt overlays that cover the whole map, so a
    -- frame that turns out to be something else is left untouched.
    local function AttachToCanvas(frame)
      if not frame or frame:GetParent() ~= WorldMapFrame then return end
      if frame:GetWidth() ~= basew or frame:GetHeight() ~= baseh then return end

      local level = frame:GetFrameLevel()
      frame:SetParent(canvas)
      frame:ClearAllPoints()
      frame:SetAllPoints(WorldMapDetailFrame)
      frame:SetFrameLevel(level)
    end

    AttachToCanvas(WorldMapPOIFrame)
    AttachToCanvas(WorldMapBlobFrame)

    -- wheel over the map zooms, left click drag pans
    WorldMapButton:EnableMouseWheel(1)
    HookScript(WorldMapButton, "OnMouseWheel", function()
      MapWheel(arg1)
    end)

    WorldMapButton:RegisterForDrag("LeftButton")
    HookScript(WorldMapButton, "OnDragStart", function()
      if not MouseIsOver(view) then return end
      local scale = canvas:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      pfUI.map.startx, pfUI.map.starty = cx/scale, cy/scale
      pfUI.map.startpanx, pfUI.map.startpany = panx, pany
      pfUI.map.panning = true
    end)

    HookScript(WorldMapButton, "OnDragStop", function()
      pfUI.map.panning = nil
    end)

    -- the button reaches past the viewport while zoomed in. scrollframes only
    -- clip drawing and not mouse input, so ignore anything outside of it.
    local click = WorldMapButton:GetScript("OnClick")
    WorldMapButton:SetScript("OnClick", function()
      if not MouseIsOver(view) then return end
      if click then click() end
    end)

    local update = WorldMapButton:GetScript("OnUpdate")
    WorldMapButton:SetScript("OnUpdate", function()
      if not MouseIsOver(view) then
        if WorldMapHighlight then WorldMapHighlight:Hide() end
        if WorldMapFrameAreaLabel then WorldMapFrameAreaLabel:SetText("") end
        return
      end
      if update then update() end
    end)

    -- the coordinates belong to the window, not to the zoomed map
    if WorldMapButton.coords then
      WorldMapButton.coords:SetParent(WorldMapFrame)
      WorldMapButton.coords:SetFrameLevel(buttonlevel + 5)
      WorldMapButton.coords.text:ClearAllPoints()
      WorldMapButton.coords.text:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -10, 10)
    end

    view:SetScript("OnUpdate", MapPanUpdate)
  end

  local pfMapLoader = CreateFrame("Frame")
  pfMapLoader:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfMapLoader:SetScript("OnEvent", function()
    -- do not load if other map addon is loaded
    if Cartographer then return end
    if METAMAP_TITLE then return end

    UIPanelWindows["WorldMapFrame"] = { area = "center" }

    WorldMapFrame:SetMovable(true)
    WorldMapFrame:EnableMouse(true)
    WorldMapFrame:RegisterForDrag("LeftButton")

    -- make sure the hooks get only applied once. Reference the loader frame
    -- directly (not `this`): turtle-wow.lua re-invokes this OnEvent with a direct
    -- call where `this` is a different frame, which would otherwise double-hook.
    if not pfMapLoader.hooked then
      pfMapLoader.hooked = true

      HookScript(WorldMapFrame, "OnShow", function()
        -- customize
        this:EnableKeyboard(false)
        this:EnableMouseWheel(1)

        -- set back to default scale
        WorldMapFrame:SetScale(scale or .85)

        -- always switch to current zone when opening the map
        pfOrigSetMapToCurrentZone()

        -- build (or resync) the zoom viewport. this runs on show and not in the
        -- loader below, because turtle-wow.lua maximizes the map afterwards and
        -- only then the final map area geometry is known.
        pfUI.map.panning = nil -- closing the map mid-drag eats the drag stop
        SetupMapZoom()
      end)

      HookScript(WorldMapFrame, "OnMouseWheel", function()
        MapWheel(arg1)
      end)

      HookScript(WorldMapFrame, "OnDragStart", function()
        WorldMapFrame:StartMoving()
      end)

      HookScript(WorldMapFrame, "OnDragStop",function()
        WorldMapFrame:StopMovingOrSizing()
        SaveMovable(this, true)
      end)
    end

    WorldMapFrame:SetAlpha(alpha)
    WorldMapFrame:SetScale(scale)
    UpdateTooltipScale()

    WorldMapFrame:ClearAllPoints()
    WorldMapFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    WorldMapFrame:SetWidth(WorldMapButton:GetWidth() + 15)
    WorldMapFrame:SetHeight(WorldMapButton:GetHeight() + 55)
    LoadMovable(WorldMapFrame)

    -- skin
    WorldMapFrameCloseButton:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", 0, 0)
    CreateBackdrop(WorldMapFrame)
    CreateBackdropShadow(WorldMapFrame)

    BlackoutWorld:Hide()
    StripTextures(WorldMapFrame)

    SkinButton(WorldMapZoomOutButton)
    SkinCloseButton(WorldMapFrameCloseButton, WorldMapFrame, -3, -3)

    -- "Switch to current zone" toggle (left side of titlebar)
    if not pfUI.map.autozoneswitch then
      local btn = CreateFrame("CheckButton", "pfUI_map_autozoneswitch", WorldMapFrame, "UICheckButtonTemplate")
      btn:SetNormalTexture("")
      btn:SetPushedTexture("")
      btn:SetHighlightTexture("")
      btn.text = _G["pfUI_map_autozoneswitchText"]
      CreateBackdrop(btn, nil, true)
      btn:SetWidth(14)
      btn:SetHeight(14)
      btn:SetPoint("RIGHT", WorldMapContinentDropDown, "LEFT", -8, 2)
      btn.text:ClearAllPoints()
      btn.text:SetPoint("RIGHT", btn, "LEFT", -4, 1)
      btn.text:SetJustifyH("RIGHT")
      btn.text:SetText(T["Switch to current zone"])
      btn:SetScript("OnShow", function()
        this:SetChecked(C.appearance.worldmap.autozoneswitch == "1")
      end)
      btn:SetScript("OnClick", function()
        if this:GetChecked() then
          C.appearance.worldmap.autozoneswitch = "1"
          pfOrigSetMapToCurrentZone()
        else
          C.appearance.worldmap.autozoneswitch = "0"
        end
      end)
      pfUI.map.autozoneswitch = btn
    end
    SkinDropDown(WorldMapContinentDropDown)
    SkinDropDown(WorldMapZoneDropDown)
    if WorldMapZoneMinimapDropDown then
      SkinDropDown(WorldMapZoneMinimapDropDown)
    end
    local point, anchor, anchorPoint, x, y = WorldMapZoneDropDown:GetPoint()
    WorldMapZoneDropDown:ClearAllPoints()
    WorldMapZoneDropDown:SetPoint(point, anchor, anchorPoint, x+8, y)

    -- coordinates
    if not WorldMapButton.coords then
      WorldMapButton.coords = CreateFrame("Frame", "pfWorldMapButtonCoords", WorldMapButton)
      WorldMapButton.coords.text = WorldMapButton.coords:CreateFontString(nil, "OVERLAY")
      WorldMapButton.coords.text:SetPoint("BOTTOMRIGHT", WorldMapButton, "BOTTOMRIGHT", -10, 10)
      WorldMapButton.coords.text:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
      WorldMapButton.coords.text:SetTextColor(1, 1, 1)
      WorldMapButton.coords.text:SetJustifyH("RIGHT")

      WorldMapButton.coords:SetScript("OnUpdate", function()
        local width  = WorldMapButton:GetWidth()
        local height = WorldMapButton:GetHeight()
        local mx, my = WorldMapButton:GetCenter()
        local scale  = WorldMapButton:GetEffectiveScale()
        local x, y   = GetCursorPosition()

        if mx and my then
          mx = (( x / scale ) - ( mx - width / 2)) / width * 100
          my = (( my + height / 2 ) - ( y / scale )) / height * 100
        end

        -- while zoomed in the button reaches past the visible map area
        local inside = MouseIsOver(WorldMapButton) and (not pfUI.map.view or MouseIsOver(pfUI.map.view))

        if mx and my and inside then
          WorldMapButton.coords.text:SetText(string.format('%.1f / %.1f', mx, my))
        else
          WorldMapButton.coords.text:SetText("")
        end
      end)
    end
  end)

  pfUI.map.loader = pfMapLoader
end)
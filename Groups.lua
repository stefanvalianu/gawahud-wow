local _, ns = ...

local function AddFrame(result, seen, frame)
    if frame and not seen[frame] then
        seen[frame] = true
        result[#result + 1] = frame
    end
end

local function AddGlobal(result, seen, name)
    AddFrame(result, seen, _G[name])
end

local function AddPath(result, seen, rootName, ...)
    local value = _G[rootName]
    if not value then
        return
    end

    for index = 1, select("#", ...) do
        value = value[select(index, ...)]
        if not value then
            return
        end
    end

    AddFrame(result, seen, value)
end

local function ResolveGlobals(names)
    local result, seen = {}, {}
    for _, name in ipairs(names) do
        AddGlobal(result, seen, name)
    end
    return result
end

local minimapTransparencyUnsafe = false
local minimapRefreshScheduled = false
local minimapRefreshForced = false

local function ReadBooleanAPI(func)
    if type(func) ~= "function" then
        return nil, false
    end

    local ok, value = pcall(func)
    if not ok or (issecretvalue and issecretvalue(value)) then
        return nil, false
    end

    return value == true, true
end

local function IsHybridMinimapActive()
    local hybrid = _G.HybridMinimap
    if hybrid and type(hybrid.IsShown) == "function" then
        local ok, shown = pcall(hybrid.IsShown, hybrid)
        if ok and not (issecretvalue and issecretvalue(shown)) and shown then
            return true
        end
    end

    if C_Minimap and type(C_Minimap.ShouldUseHybridMinimap) == "function" then
        local ok, requested = pcall(C_Minimap.ShouldUseHybridMinimap)
        if ok and not (issecretvalue and issecretvalue(requested)) and requested then
            return true
        end
    end

    return false
end

local function GetMinimapMapInfo()
    if not C_Minimap or type(C_Minimap.GetUiMapID) ~= "function"
        or not C_Map or type(C_Map.GetMapInfo) ~= "function" then
        return nil, nil
    end

    local mapOK, mapID = pcall(C_Minimap.GetUiMapID)
    if not mapOK or type(mapID) ~= "number" then
        return nil, nil
    end

    local infoOK, info = pcall(C_Map.GetMapInfo, mapID)
    if not infoOK or type(info) ~= "table" then
        return mapID, nil
    end

    return mapID, info
end

local function IsInteriorMinimapMapType()
    local _, info = GetMinimapMapInfo()
    if not info then
        return false
    end

    local mapType = info.mapType
    local uiMapType = Enum and Enum.UIMapType
    if uiMapType then
        return mapType == uiMapType.Dungeon or mapType == uiMapType.Micro
    end

    -- Stable enum values used by the current Retail API. This fallback only
    -- matters if the Enum table is unexpectedly unavailable.
    return mapType == 4 or mapType == 5
end

local function IsMinimapTransparencyUnsafe()
    -- WoW's native indoor/WMO minimap renderer has a long-standing rendering
    -- defect when Minimap's effective alpha is below 1. This is independent of
    -- HybridMinimap. Prefer renderer/map signals first, then conservatively
    -- treat every location that is not explicitly outdoors as alpha-unsafe.
    if IsHybridMinimapActive() or IsInteriorMinimapMapType() then
        return true
    end

    local outdoors, outdoorsKnown = ReadBooleanAPI(_G.IsOutdoors)
    if outdoorsKnown then
        return not outdoors
    end

    local indoors, indoorsKnown = ReadBooleanAPI(_G.IsIndoors)
    return indoorsKnown and indoors or false
end

local function RefreshMinimapRendererNow()
    local minimap = _G.Minimap
    if not minimap
        or type(minimap.GetZoom) ~= "function"
        or type(minimap.GetZoomLevels) ~= "function"
        or type(minimap.SetZoom) ~= "function" then
        return false
    end

    local zoomOK, zoom = pcall(minimap.GetZoom, minimap)
    local levelsOK, levels = pcall(minimap.GetZoomLevels, minimap)
    if not zoomOK or not levelsOK
        or type(zoom) ~= "number"
        or type(levels) ~= "number"
        or levels < 2 then
        return false
    end

    local maxZoom = levels - 1
    local alternateZoom
    if zoom < maxZoom then
        alternateZoom = zoom + 1
    elseif zoom > 0 then
        alternateZoom = zoom - 1
    end

    if alternateZoom == nil then
        return false
    end

    -- Reproduce the operation that reliably repairs the black indoor map for
    -- users: actually change the native Minimap zoom. Restore the user's zoom
    -- on the next frame so the repaint occurs without leaving their view
    -- changed. This refreshes both native WMO tiles and HybridMinimap because
    -- both react to MINIMAP_UPDATE_ZOOM.
    local changed = pcall(minimap.SetZoom, minimap, alternateZoom)
    if not changed then
        return false
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if minimap and type(minimap.SetZoom) == "function" then
                pcall(minimap.SetZoom, minimap, zoom)
            end
        end)
    else
        pcall(minimap.SetZoom, minimap, zoom)
    end

    return true
end

local function ScheduleMinimapRendererRefresh(force)
    minimapRefreshForced = minimapRefreshForced or force == true

    if minimapRefreshScheduled
        or not C_Timer
        or type(C_Timer.After) ~= "function" then
        return
    end

    minimapRefreshScheduled = true
    C_Timer.After(0, function()
        minimapRefreshScheduled = false
        local forced = minimapRefreshForced
        minimapRefreshForced = false
        if forced or IsMinimapTransparencyUnsafe() then
            RefreshMinimapRendererNow()
        end
    end)
end

local function UpdateMinimapRendererSafety()
    local unsafe = IsMinimapTransparencyUnsafe()

    if unsafe and not minimapTransparencyUnsafe then
        -- A map can already be black by the time its visibility rule runs.
        -- Schedule the native zoom repaint on every transition into an unsafe
        -- renderer, independent of whether the rule is currently concealing.
        ScheduleMinimapRendererRefresh(false)
    end

    minimapTransparencyUnsafe = unsafe
    return unsafe
end

local function KeepMinimapRendererVisible()
    return UpdateMinimapRendererSafety()
end

local function MinimapVisuals()
    -- Resolve is invoked on the same zone/WMO events used by the minimap. This
    -- updates renderer safety even when concealment is disabled or suppressed
    -- by the instance override, so a black map still receives a repaint.
    UpdateMinimapRendererSafety()
    return ResolveGlobals({ "Minimap" })
end

function ns.RefreshMinimapRenderer()
    ScheduleMinimapRendererRefresh(true)
end

function ns.GetMinimapRendererState()
    local minimap = _G.Minimap
    local outdoors, outdoorsKnown = ReadBooleanAPI(_G.IsOutdoors)
    local indoors, indoorsKnown = ReadBooleanAPI(_G.IsIndoors)

    local hybrid = _G.HybridMinimap
    local hybridShown = false
    if hybrid and type(hybrid.IsShown) == "function" then
        local ok, value = pcall(hybrid.IsShown, hybrid)
        hybridShown = ok and value == true
    end

    local hybridRequested = false
    if C_Minimap and type(C_Minimap.ShouldUseHybridMinimap) == "function" then
        local ok, value = pcall(C_Minimap.ShouldUseHybridMinimap)
        hybridRequested = ok and value == true
    end

    local function ReadMethod(methodName)
        if not minimap or type(minimap[methodName]) ~= "function" then
            return nil
        end
        local ok, value = pcall(minimap[methodName], minimap)
        return ok and value or nil
    end

    local uiMapID, mapInfo = GetMinimapMapInfo()

    return {
        alphaUnsafe = IsMinimapTransparencyUnsafe(),
        outdoors = outdoorsKnown and outdoors or nil,
        outdoorsKnown = outdoorsKnown,
        indoors = indoorsKnown and indoors or nil,
        indoorsKnown = indoorsKnown,
        hybridRequested = hybridRequested,
        hybridShown = hybridShown,
        alpha = ReadMethod("GetAlpha"),
        effectiveAlpha = ReadMethod("GetEffectiveAlpha"),
        zoom = ReadMethod("GetZoom"),
        zoomLevels = ReadMethod("GetZoomLevels"),
        uiMapID = uiMapID,
        mapType = mapInfo and mapInfo.mapType or nil,
        mapName = mapInfo and mapInfo.name or nil,
    }
end


local STATUS_BAR_CONTAINERS = {
    "MainStatusTrackingBarContainer",
    "SecondaryStatusTrackingBarContainer",
}

local function StatusTrackingBarVisuals()
    local result, seen = {}, {}

    for _, containerName in ipairs(STATUS_BAR_CONTAINERS) do
        local container = _G[containerName]
        if container then
            -- Do not change the container alpha. Blizzard initializes these
            -- containers at zero and owns their FadeIn/FadeOut animations.
            AddFrame(result, seen, container.BarFrameTexture)

            for _, bar in pairs(container.bars or {}) do
                AddFrame(result, seen, bar)
            end
        end
    end

    return result
end

local function ObjectiveVisuals()
    local result, seen = {}, {}
    AddGlobal(result, seen, "ObjectiveTrackerFrame")

    for _, visual in ipairs(StatusTrackingBarVisuals()) do
        AddFrame(result, seen, visual)
    end

    return result
end

local function ObjectiveHoverFrames()
    return ResolveGlobals({
        "ObjectiveTrackerFrame",
        "MainStatusTrackingBarContainer",
        "SecondaryStatusTrackingBarContainer",
    })
end

local function ChatFrames()
    local result, seen = {}, {}

    local fixedNames = {
        "GeneralDockManager",
        "ChatFrameMenuButton",
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
        "QuickJoinToastButton",
    }

    for _, name in ipairs(fixedNames) do
        AddGlobal(result, seen, name)
    end

    local count = NUM_CHAT_WINDOWS or 10
    for index = 1, count do
        local prefix = "ChatFrame" .. index
        AddGlobal(result, seen, prefix)
        AddGlobal(result, seen, prefix .. "Tab")
        AddGlobal(result, seen, prefix .. "ButtonFrame")
        AddGlobal(result, seen, prefix .. "EditBox")
    end

    return result
end

local function IsChatInputActive()
    if not ChatEdit_GetActiveWindow then
        return false
    end

    local editBox = ChatEdit_GetActiveWindow()
    return editBox ~= nil and editBox:IsShown()
end

local PLAYER_STATUS_GLOBALS = {
    "PlayerFrame",
    "BuffFrame",
    "DebuffFrame",
}

local COOLDOWN_VIEWER_GLOBALS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

local function PlayerStatusVisuals()
    return ResolveGlobals(PLAYER_STATUS_GLOBALS)
end

local function CooldownViewerVisuals()
    return ResolveGlobals(COOLDOWN_VIEWER_GLOBALS)
end

local function PlayerAndCooldownHoverFrames()
    local result, seen = {}, {}

    for _, name in ipairs(PLAYER_STATUS_GLOBALS) do
        AddGlobal(result, seen, name)
    end
    for _, name in ipairs(COOLDOWN_VIEWER_GLOBALS) do
        AddGlobal(result, seen, name)
    end

    return result
end

local function MinimapExtras()
    local result, seen = {}, {}

    local globalNames = {
        "MinimapZoneTextButton",
        "GameTimeFrame",
        "TimeManagerClockButton",
        "TimeManagerClockTicker",
        "MiniMapTracking",
        "MiniMapMailFrame",
        "QueueStatusButton",
        "AddonCompartmentFrame",
        "ExpansionLandingPageMinimapButton",
        "MinimapZoomIn",
        "MinimapZoomOut",
        "MinimapCompassTexture",
    }

    for _, name in ipairs(globalNames) do
        AddGlobal(result, seen, name)
    end

    -- Current Retail layouts expose some minimap pieces as keyed children
    -- rather than globals. Every path is optional and runtime-checked.
    AddPath(result, seen, "MinimapCluster", "Tracking")
    AddPath(result, seen, "MinimapCluster", "IndicatorFrame")
    AddPath(result, seen, "MinimapCluster", "BorderTop")
    AddPath(result, seen, "MinimapCluster", "ZoneTextButton")
    AddPath(result, seen, "MinimapCluster", "CalendarFrame")
    AddPath(result, seen, "MinimapCluster", "Clock")
    AddPath(result, seen, "MinimapCluster", "ClockButton")

    return result
end

ns.groups = {
    chat = {
        resolve = ChatFrames,
        forceVisible = IsChatInputActive,
    },

    playerStatus = {
        resolve = PlayerStatusVisuals,
        -- Hovering either the player panel or any supported Cooldown Viewer
        -- reveals both logical rules without coupling their conceal settings.
        resolveHover = PlayerAndCooldownHoverFrames,
    },

    cooldownViewers = {
        resolve = CooldownViewerVisuals,
        resolveHover = PlayerAndCooldownHoverFrames,
    },

    targetFrame = {
        resolve = function()
            return ResolveGlobals({ "TargetFrame" })
        end,
    },

    focusFrame = {
        resolve = function()
            return ResolveGlobals({ "FocusFrame" })
        end,
    },

    petFrame = {
        resolve = function()
            return ResolveGlobals({ "PetFrame" })
        end,
    },

    actionBars = {
        resolve = function()
            return ResolveGlobals({
                "MainActionBar",
                "MultiBarBottomLeft",
                "MultiBarBottomRight",
                "MultiBarRight",
                "MultiBarLeft",
                "MultiBar5",
                "MultiBar6",
                "MultiBar7",
            })
        end,
    },

    utilityActionBars = {
        resolve = function()
            return ResolveGlobals({
                "PetActionBar",
                "StanceBar",
                "PossessActionBar",
            })
        end,
    },

    bagBar = {
        resolve = function()
            return ResolveGlobals({ "BagsBar" })
        end,
    },

    microMenu = {
        resolve = function()
            return ResolveGlobals({ "MicroMenuContainer" })
        end,
    },

    minimap = {
        -- The native map widget owns outdoor terrain, indoor/WMO tiles, and
        -- HybridMinimap descendants. Keep those visuals together.
        resolve = MinimapVisuals,
        forceVisible = KeepMinimapRendererVisible,
    },

    minimapExtras = {
        resolve = MinimapExtras,
    },

    objectives = {
        -- Status-bar containers have Blizzard-owned alpha animations. Fade
        -- their child artwork, but use the full containers for hover testing.
        resolve = ObjectiveVisuals,
        resolveHover = ObjectiveHoverFrames,
    },

}

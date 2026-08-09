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
        "MinimapBackdrop",
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
        resolve = function()
            return ResolveGlobals({
                "PlayerFrame",
                "BuffFrame",
                "DebuffFrame",
            })
        end,
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
        resolve = function()
            return ResolveGlobals({ "Minimap" })
        end,
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

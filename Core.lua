local addonName, ns = ...
local displayName = ns.displayName or "gawaHUD"

local controller = CreateFrame("Frame")
local rules = {}
local rulesByID = {}
local trackedFrames = setmetatable({}, { __mode = "k" })
local hookedChatFrames = setmetatable({}, { __mode = "k" })
local trackedActionArtwork = setmetatable({}, { __mode = "k" })
local elapsedSinceUpdate = 0
local addonEnabled = true
local refreshScheduled = false
local tooltipHookInstalled = false
local actionButtonHookInstalled = false
local instanceBehaviorSuppressed = false

local VALID_HIDE_MODES = {
    never = true,
    outOfCombat = true,
    inCombat = true,
    always = true,
}

local function ClampNumber(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff70d5ff" .. displayName .. ":|r " .. message)
end

local function ReadFrameAlpha(frame)
    local ok, alpha = pcall(frame.GetAlpha, frame)
    if not ok or type(alpha) ~= "number" then
        return 1
    end

    if issecretvalue and issecretvalue(alpha) then
        return 1
    end

    return ClampNumber(alpha, 0, 1)
end

local function CaptureFrame(frame)
    local tracked = trackedFrames[frame]
    if tracked then
        return tracked
    end

    tracked = {
        originalAlpha = ReadFrameAlpha(frame),
        appliedAlpha = nil,
        appliedSecretAlpha = false,
        healthAlphaCurve = nil,
    }
    trackedFrames[frame] = tracked
    return tracked
end

local function ApplyFrameAlpha(frame, alpha)
    local tracked = CaptureFrame(frame)

    if tracked.appliedAlpha == nil and not tracked.appliedSecretAlpha then
        tracked.originalAlpha = ReadFrameAlpha(frame)
    end

    alpha = ClampNumber(alpha, 0, 1)
    if not tracked.appliedSecretAlpha
        and tracked.appliedAlpha
        and math.abs(tracked.appliedAlpha - alpha) < 0.002 then
        return
    end

    frame:SetAlpha(alpha)
    tracked.appliedAlpha = alpha
    tracked.appliedSecretAlpha = false
end

local function RestoreFrameAlpha(frame)
    local tracked = trackedFrames[frame]
    if not tracked
        or (tracked.appliedAlpha == nil and not tracked.appliedSecretAlpha) then
        return
    end

    frame:SetAlpha(tracked.originalAlpha)
    tracked.appliedAlpha = nil
    tracked.appliedSecretAlpha = false
end

local function RestoreAllFrames()
    for frame in pairs(trackedFrames) do
        RestoreFrameAlpha(frame)
    end
end

local function IsLegacyActionBarSettingCustomized(saved)
    if type(saved) ~= "table" then
        return false
    end

    local modeChanged = VALID_HIDE_MODES[saved.mode]
        and saved.mode ~= "outOfCombat"
    local opacityChanged = tonumber(saved.opacity) ~= nil
        and tonumber(saved.opacity) ~= 0

    return modeChanged or opacityChanged
end

local function IsElementSettingCustomized(saved, defaultMode, defaultOpacity)
    if type(saved) ~= "table" then
        return false
    end

    local modeChanged = VALID_HIDE_MODES[saved.mode]
        and saved.mode ~= defaultMode
    local opacityChanged = tonumber(saved.opacity) ~= nil
        and tonumber(saved.opacity) ~= defaultOpacity

    return modeChanged or opacityChanged
end

local function MigrateDatabase(database)
    local elements = database.elements
    local version = tonumber(database.version) or 0

    if version < 2 and type(elements["action-bars"]) ~= "table" then
        local main = elements["main-action-bar"]
        local additional = elements["additional-action-bars"]
        local source

        if IsLegacyActionBarSettingCustomized(main) then
            source = main
        elseif IsLegacyActionBarSettingCustomized(additional) then
            source = additional
        else
            source = main or additional
        end

        if type(source) == "table" then
            elements["action-bars"] = {
                mode = source.mode,
                opacity = source.opacity,
            }
        end
    end

    if version < 3 and type(elements["player-status"]) ~= "table" then
        local playerFrame = elements["player-frame"]
        local buffs = elements.buffs
        local source

        -- Prefer whichever legacy row the user actually customized. When both
        -- were customized, the player-frame policy wins because it is the
        -- safety-critical visual now governing the combined group.
        if IsElementSettingCustomized(playerFrame, "never", 0) then
            source = playerFrame
        elseif IsElementSettingCustomized(buffs, "never", 0) then
            source = buffs
        else
            source = playerFrame or buffs
        end

        if type(source) == "table" then
            elements["player-status"] = {
                mode = source.mode,
                opacity = source.opacity,
            }
        end
    end

    elements["main-action-bar"] = nil
    elements["additional-action-bars"] = nil
    elements["player-frame"] = nil
    elements.buffs = nil
    database.version = 4
end

local function InitializeDatabase()
    if type(gawaHUDDB) ~= "table" then
        gawaHUDDB = {}
    end

    gawaHUDDB.elements = type(gawaHUDDB.elements) == "table"
        and gawaHUDDB.elements
        or {}

    MigrateDatabase(gawaHUDDB)

    for _, definition in ipairs(ns.elements or {}) do
        local saved = gawaHUDDB.elements[definition.id]
        if type(saved) ~= "table" then
            saved = {}
            gawaHUDDB.elements[definition.id] = saved
        end

        if not VALID_HIDE_MODES[saved.mode] then
            saved.mode = definition.defaultMode or "never"
        end

        saved.opacity = ClampNumber(
            saved.opacity ~= nil and saved.opacity or definition.defaultOpacity,
            0,
            100
        )

        local healthVisibility = definition.healthVisibility
        if type(healthVisibility) == "table" then
            if type(saved.healthThresholdEnabled) ~= "boolean" then
                saved.healthThresholdEnabled = healthVisibility.defaultEnabled == true
            end

            saved.healthThreshold = ClampNumber(
                saved.healthThreshold ~= nil
                    and saved.healthThreshold
                    or healthVisibility.defaultThreshold,
                1,
                100
            )
        end
    end

    if type(gawaHUDDB.disableInInstances) ~= "boolean" then
        local visibility = ns.config and ns.config.visibility
        gawaHUDDB.disableInInstances = visibility
            and visibility.disableInInstancesByDefault == true
            or false
    end

    ns.db = gawaHUDDB
end

function ns.GetGeneralSettings()
    return ns.db
end

function ns.GetElementSettings(id)
    local elements = ns.db and ns.db.elements
    return elements and elements[id] or nil
end

local function RefreshInstanceBehaviorState()
    local suppressed = false
    if ns.db and ns.db.disableInInstances == true
        and type(IsInInstance) == "function" then
        local ok, inInstance = pcall(IsInInstance)
        suppressed = ok and inInstance == true
    end

    local changed = instanceBehaviorSuppressed ~= suppressed
    instanceBehaviorSuppressed = suppressed
    return changed
end

local function IsDescendantOf(frame, possibleAncestor)
    local parent = frame and frame.GetParent and frame:GetParent() or nil
    while parent do
        if parent == possibleAncestor then
            return true
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    return false
end

local function AddFrameToRule(rule, frame)
    if not frame or rule.frameSet[frame] then
        return false
    end

    -- Managing both a parent and its child would multiply alpha values. Keep
    -- only the highest ancestor represented within each logical rule.
    for _, existing in ipairs(rule.frames) do
        if IsDescendantOf(frame, existing) then
            return false
        end
    end

    for index = #rule.frames, 1, -1 do
        local existing = rule.frames[index]
        if IsDescendantOf(existing, frame) then
            rule.frameSet[existing] = nil
            table.remove(rule.frames, index)
        end
    end

    rule.frameSet[frame] = true
    rule.frames[#rule.frames + 1] = frame
    CaptureFrame(frame)
    return true
end

local function AddHoverFrameToRule(rule, frame)
    if not frame or rule.hoverFrameSet[frame] then
        return false
    end

    -- As with alpha targets, keep only the highest ancestor represented in
    -- the hover set so a parent and its children are not checked repeatedly.
    for _, existing in ipairs(rule.hoverFrames) do
        if IsDescendantOf(frame, existing) then
            return false
        end
    end

    for index = #rule.hoverFrames, 1, -1 do
        local existing = rule.hoverFrames[index]
        if IsDescendantOf(existing, frame) then
            rule.hoverFrameSet[existing] = nil
            table.remove(rule.hoverFrames, index)
        end
    end

    rule.hoverFrameSet[frame] = true
    rule.hoverFrames[#rule.hoverFrames + 1] = frame
    return true
end

local function ResolveRule(rule)
    local group = ns.groups and ns.groups[rule.groupName]
    if not group or type(group.resolve) ~= "function" then
        return false
    end

    rule.forceVisible = group.forceVisible
    local ok, resolved = pcall(group.resolve)
    if not ok or type(resolved) ~= "table" then
        return false
    end

    local added = false
    for _, frame in ipairs(resolved) do
        if AddFrameToRule(rule, frame) then
            added = true
        end
    end

    local hoverResolved = resolved
    if type(group.resolveHover) == "function" then
        local hoverOK, customHover = pcall(group.resolveHover)
        if hoverOK and type(customHover) == "table" then
            hoverResolved = customHover
        else
            hoverResolved = {}
        end
    end

    for _, frame in ipairs(hoverResolved) do
        if AddHoverFrameToRule(rule, frame) then
            added = true
        end
    end

    return added
end

local function IsBelowHealthThreshold(healthVisibility)
    if not healthVisibility or healthVisibility.enabled ~= true then
        return false
    end

    local unit = healthVisibility.unit or "player"
    if type(UnitExists) == "function" and not UnitExists(unit) then
        return false
    end

    if type(UnitHealth) ~= "function" or type(UnitHealthMax) ~= "function" then
        return false
    end

    local healthOK, health = pcall(UnitHealth, unit)
    local maximumOK, maximum = pcall(UnitHealthMax, unit)
    if not healthOK or not maximumOK
        or type(health) ~= "number"
        or type(maximum) ~= "number" then
        return false
    end

    -- Secret numbers must be detected before any comparison or arithmetic.
    -- The curve-based alpha path below handles them without exposing the
    -- protected value to Lua logic.
    if issecretvalue
        and (issecretvalue(health) or issecretvalue(maximum)) then
        return false
    end

    if maximum <= 0 then
        return false
    end

    local threshold = ClampNumber(healthVisibility.threshold, 1, 100)
    return (health / maximum) * 100 <= threshold
end

local function IsRuleForcedVisible(rule)
    -- Keep the ordinary numeric path for builds/contexts where health is
    -- readable. Secret health values are handled later by a curve passed
    -- directly to SetAlpha, because Lua cannot branch on them.
    if IsBelowHealthThreshold(rule.healthVisibility) then
        return true
    end

    if not rule.forceVisible then
        return false
    end

    local ok, result = pcall(rule.forceVisible)
    return ok and result == true
end

local function ShouldConceal(rule)
    if not addonEnabled or instanceBehaviorSuppressed then
        return false
    end

    local mode = rule.mode
    if mode == "always" then
        return true
    end

    local inCombat = InCombatLockdown()
    if mode == "inCombat" then
        return inCombat
    end

    if mode == "outOfCombat" then
        return not inCombat
    end

    return false
end

local function IsMouseOverRule(rule)
    local config = ns.config and ns.config.visibility
    local padding = config and tonumber(config.hoverPadding) or 0
    padding = padding or 0

    local hoverFrames = #rule.hoverFrames > 0 and rule.hoverFrames or rule.frames
    for _, frame in ipairs(hoverFrames) do
        if frame:IsVisible()
            and MouseIsOver(frame, padding, padding, padding, padding) then
            return true
        end
    end

    return false
end

local function ResetConcealFade(rule)
    rule.concealStartedAt = nil
    rule.concealComplete = false
end

local function CancelTimedReveal(rule)
    rule.revealUntil = nil
    rule.fadeUntil = nil
end

local function GetConcealProgress(rule, now)
    if not ShouldConceal(rule) then
        rule.lastMouseOver = nil
        if instanceBehaviorSuppressed then
            CancelTimedReveal(rule)
        end
        ResetConcealFade(rule)
        return 0
    end

    if IsRuleForcedVisible(rule) then
        CancelTimedReveal(rule)
        ResetConcealFade(rule)
        return 0
    end

    if rule.mouseover then
        if IsMouseOverRule(rule) then
            rule.lastMouseOver = now
            CancelTimedReveal(rule)
            ResetConcealFade(rule)
            return 0
        end

        local config = ns.config and ns.config.visibility
        local delay = config and tonumber(config.mouseOutDelay) or 0
        if rule.lastMouseOver and now - rule.lastMouseOver < (delay or 0) then
            ResetConcealFade(rule)
            return 0
        end
    end

    -- Chat notifications use an explicit hold followed by their own fade. The
    -- same progress value is consumed by the generic alpha interpolator below.
    if rule.revealUntil and now < rule.revealUntil then
        ResetConcealFade(rule)
        return 0
    end

    if rule.fadeUntil and rule.revealUntil then
        if now < rule.fadeUntil then
            ResetConcealFade(rule)

            local duration = rule.fadeUntil - rule.revealUntil
            if duration > 0 then
                return ClampNumber((now - rule.revealUntil) / duration, 0, 1)
            end
        else
            rule.revealUntil = nil
            rule.fadeUntil = nil
            rule.concealStartedAt = nil
            rule.concealComplete = true
            return 1
        end
    end

    if rule.concealComplete then
        return 1
    end

    local config = ns.config and ns.config.visibility
    local duration = math.max(config and tonumber(config.fadeSeconds) or 0, 0)
    if duration <= 0 then
        rule.concealComplete = true
        return 1
    end

    if not rule.concealStartedAt then
        rule.concealStartedAt = now
    end

    local progress = ClampNumber((now - rule.concealStartedAt) / duration, 0, 1)
    if progress >= 1 then
        rule.concealStartedAt = nil
        rule.concealComplete = true
        return 1
    end

    return progress
end

local function ApplyHealthThresholdAlpha(frame, healthVisibility, concealedAlpha)
    if not healthVisibility or healthVisibility.enabled ~= true then
        return false
    end

    if type(UnitHealthPercent) ~= "function"
        or not C_CurveUtil
        or type(C_CurveUtil.CreateCurve) ~= "function"
        or not Enum
        or not Enum.LuaCurveType
        or Enum.LuaCurveType.Step == nil then
        return false
    end

    local unit = healthVisibility.unit or "player"
    if type(UnitExists) == "function" and not UnitExists(unit) then
        return false
    end

    local tracked = CaptureFrame(frame)
    if tracked.appliedAlpha == nil and not tracked.appliedSecretAlpha then
        tracked.originalAlpha = ReadFrameAlpha(frame)
    end

    if not tracked.healthAlphaCurve then
        local ok, curve = pcall(C_CurveUtil.CreateCurve)
        if not ok or not curve then
            return false
        end
        tracked.healthAlphaCurve = curve
    end

    local curve = tracked.healthAlphaCurve
    local threshold = ClampNumber(healthVisibility.threshold, 1, 100) / 100
    local visibleAlpha = tracked.originalAlpha

    local configured = pcall(function()
        curve:ClearPoints()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, visibleAlpha)

        if threshold >= 1 then
            curve:AddPoint(1, visibleAlpha)
            return
        end

        -- Step curves retain the previous point's value. Keep the group fully
        -- visible through the configured threshold, then switch to the alpha
        -- selected by the normal conceal/fade policy immediately above it.
        curve:AddPoint(threshold, visibleAlpha)
        curve:AddPoint(math.min(threshold + 0.0001, 1), concealedAlpha)
        curve:AddPoint(1, concealedAlpha)
    end)
    if not configured then
        return false
    end

    -- UnitHealthPercent may return a secret number. Do not inspect it or pass
    -- it through generic numeric helpers; SetAlpha is explicitly allowed to
    -- consume the value directly.
    local alpha = UnitHealthPercent(unit, false, curve)
    frame:SetAlpha(alpha)
    tracked.appliedAlpha = nil
    tracked.appliedSecretAlpha = true
    return true
end

local function ApplyRuleProgress(rule, progress)
    local hiddenAlpha = ClampNumber(rule.opacity, 0, 100) / 100

    for _, frame in ipairs(rule.frames) do
        if progress <= 0 then
            RestoreFrameAlpha(frame)
        else
            local tracked = CaptureFrame(frame)
            if tracked.appliedAlpha == nil and not tracked.appliedSecretAlpha then
                tracked.originalAlpha = ReadFrameAlpha(frame)
            end

            local alpha = tracked.originalAlpha
                + ((hiddenAlpha - tracked.originalAlpha) * progress)

            if not ApplyHealthThresholdAlpha(frame, rule.healthVisibility, alpha) then
                ApplyFrameAlpha(frame, alpha)
            end
        end
    end
end

local function UpdateRule(rule, now)
    ApplyRuleProgress(rule, GetConcealProgress(rule, now))
end

local function UpdateAllRules()
    RefreshInstanceBehaviorState()
    local now = GetTime()
    for _, rule in ipairs(rules) do
        UpdateRule(rule, now)
    end
end

local function BuildRules()
    RestoreAllFrames()
    wipe(rules)
    wipe(rulesByID)

    local visibility = ns.config and ns.config.visibility
    if not visibility or visibility.enabled == false then
        return
    end

    for _, definition in ipairs(ns.elements or {}) do
        local saved = ns.GetElementSettings(definition.id)
        local mode = saved and saved.mode or definition.defaultMode or "never"

        if VALID_HIDE_MODES[mode] and definition.group then
            local healthDefinition = definition.healthVisibility
            local healthVisibility
            if type(healthDefinition) == "table" then
                healthVisibility = {
                    enabled = saved and saved.healthThresholdEnabled == true,
                    threshold = saved and saved.healthThreshold
                        or healthDefinition.defaultThreshold,
                    unit = healthDefinition.unit or "player",
                }
            end

            local rule = {
                id = definition.id,
                label = definition.label or definition.id,
                groupName = definition.group,
                mode = mode,
                opacity = saved and saved.opacity or definition.defaultOpacity or 0,
                mouseover = definition.mouseover == true,
                frames = {},
                frameSet = setmetatable({}, { __mode = "k" }),
                hoverFrames = {},
                hoverFrameSet = setmetatable({}, { __mode = "k" }),
                lastMouseOver = nil,
                forceVisible = nil,
                healthVisibility = healthVisibility,
                revealUntil = nil,
                fadeUntil = nil,
                concealStartedAt = nil,
                concealComplete = false,
            }

            rules[#rules + 1] = rule
            rulesByID[rule.id] = rule
        end
    end
end

local function RefreshRules()
    local changed = false
    for _, rule in ipairs(rules) do
        if ResolveRule(rule) then
            changed = true
        end
    end

    if changed then
        UpdateAllRules()
    end
end

local function RevealChatForNewMessage()
    local config = ns.config and ns.config.chatNotifications
    if not config or config.enabled == false then
        return
    end

    local rule = rulesByID.chat
    if not rule or rule.mode == "never" then
        return
    end

    local now = GetTime()
    local hold = math.max(tonumber(config.holdSeconds) or 0, 0)
    local fade = math.max(tonumber(config.fadeSeconds) or 0, 0)

    rule.revealUntil = now + hold
    rule.fadeUntil = rule.revealUntil + fade
    UpdateRule(rule, now)
end

local function HookChatFrames()
    local count = NUM_CHAT_WINDOWS or 10
    for index = 1, count do
        local frame = _G["ChatFrame" .. index]
        if frame and frame.AddMessage and not hookedChatFrames[frame] then
            hookedChatFrames[frame] = true
            hooksecurefunc(frame, "AddMessage", RevealChatForNewMessage)
        end
    end
end

local function ScheduleRefresh()
    if refreshScheduled then
        return
    end

    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        RefreshRules()
        HookChatFrames()
        UpdateAllRules()
    end)
end

local function CaptureActionArtwork(region)
    if not region then
        return nil
    end

    local tracked = trackedActionArtwork[region]
    if tracked then
        return tracked
    end

    tracked = {
        originalAlpha = ReadFrameAlpha(region),
        applied = false,
    }
    trackedActionArtwork[region] = tracked
    return tracked
end

local function HideActionArtwork(region)
    local tracked = CaptureActionArtwork(region)
    if not tracked then
        return
    end

    if not tracked.applied then
        tracked.originalAlpha = ReadFrameAlpha(region)
    end

    region:SetAlpha(0)
    tracked.applied = true
end

local function RestoreActionArtwork(region)
    local tracked = trackedActionArtwork[region]
    if not tracked or not tracked.applied then
        return
    end

    region:SetAlpha(tracked.originalAlpha)
    tracked.applied = false
end

local function RestoreAllActionArtwork()
    for region in pairs(trackedActionArtwork) do
        RestoreActionArtwork(region)
    end
end

local function StripActionButtonArtwork(button)
    local config = ns.config and ns.config.actionButtons
    if not config or config.enabled == false or not button then
        return
    end

    local normalTexture = button.NormalTexture
        or (button.GetNormalTexture and button:GetNormalTexture())

    local function ApplyRegion(region, enabled)
        if not enabled or not region then
            return
        end

        if instanceBehaviorSuppressed then
            RestoreActionArtwork(region)
        else
            HideActionArtwork(region)
        end
    end

    ApplyRegion(normalTexture, config.removeNormalTexture)
    ApplyRegion(button.SlotArt, config.removeEmptySlotArt)
    ApplyRegion(button.SlotBackground, config.removeEmptySlotBackground)
end

local function ScanNamedActionButtons()
    local prefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
        "OverrideActionBarButton",
        "PetActionButton",
        "StanceButton",
        "ShapeshiftButton",
        "PossessButton",
    }

    for _, prefix in ipairs(prefixes) do
        for index = 1, 12 do
            StripActionButtonArtwork(_G[prefix .. index])
        end
    end
end

local function InstallActionButtonStyling()
    RefreshInstanceBehaviorState()

    if instanceBehaviorSuppressed then
        RestoreAllActionArtwork()
    end

    if actionButtonHookInstalled then
        ScanNamedActionButtons()
        return
    end

    local config = ns.config and ns.config.actionButtons
    if not config or config.enabled == false then
        return
    end

    ScanNamedActionButtons()

    local registry = _G.ActionBarButtonEventsFrame
    if registry and registry.ForEachFrame then
        registry:ForEachFrame(StripActionButtonArtwork)
    end

    if registry and registry.RegisterFrame then
        hooksecurefunc(registry, "RegisterFrame", function(_, button)
            StripActionButtonArtwork(button)
        end)
        actionButtonHookInstalled = true
    end
end

local function InstallTooltipHook()
    if tooltipHookInstalled then
        return
    end

    local config = ns.config and ns.config.tooltip
    if not config or config.enabled == false then
        return
    end

    if type(GameTooltip_SetDefaultAnchor) ~= "function" then
        return
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        RefreshInstanceBehaviorState()
        local current = ns.config and ns.config.tooltip
        if current and current.enabled ~= false
            and not instanceBehaviorSuppressed then
            tooltip:SetOwner(parent or UIParent, current.anchor or "ANCHOR_CURSOR_RIGHT")
        end
    end)

    tooltipHookInstalled = true
end

function ns.ApplySettings()
    RefreshInstanceBehaviorState()
    BuildRules()
    RefreshRules()
    HookChatFrames()
    UpdateAllRules()
    InstallActionButtonStyling()

    if instanceBehaviorSuppressed then
        RestoreAllFrames()
        RestoreAllActionArtwork()
    end
end

local function Audit()
    local version, build, _, interfaceVersion = GetBuildInfo()
    Print(("Retail %s, build %s, interface %s"):format(
        tostring(version),
        tostring(build),
        tostring(interfaceVersion)
    ))

    RefreshInstanceBehaviorState()
    Print(("Instance override: configured=%s, active=%s"):format(
        tostring(ns.db and ns.db.disableInInstances == true),
        tostring(instanceBehaviorSuppressed)
    ))

    for _, rule in ipairs(rules) do
        ResolveRule(rule)

        if #rule.frames == 0 then
            Print(("|cffff6666MISSING|r %s (%s)"):format(rule.label, rule.id))
        else
            local healthSummary = "off"
            if rule.healthVisibility and rule.healthVisibility.enabled then
                healthSummary = ("<=%d%%"):format(
                    ClampNumber(rule.healthVisibility.threshold, 1, 100)
                )
            end

            Print(("|cff66ff88OK|r %s: %d alpha target(s), %d hover target(s), mode=%s, hidden=%d%%, mouseover=%s, low-health=%s"):format(
                rule.label,
                #rule.frames,
                #rule.hoverFrames,
                rule.mode,
                rule.opacity,
                tostring(rule.mouseover),
                healthSummary
            ))

            for _, frame in ipairs(rule.frames) do
                local name = frame.GetName and frame:GetName() or nil
                local objectType = frame.GetObjectType and frame:GetObjectType() or "UIObject"
                local protected = frame.IsProtected and frame:IsProtected() or false
                local visible = frame.IsVisible and frame:IsVisible() or true

                Print(("  %s [%s], protected=%s, visible=%s"):format(
                    name or "<anonymous>",
                    tostring(objectType),
                    tostring(protected),
                    tostring(visible)
                ))
            end
        end
    end
end

local function Initialize()
    InitializeDatabase()
    ns.ApplySettings()
    InstallTooltipHook()

    local visibility = ns.config and ns.config.visibility
    local interval = visibility and tonumber(visibility.updateInterval) or 0.05
    controller.updateInterval = math.max(interval or 0.05, 0.02)

    if ns.InitializeSettings then
        ns.InitializeSettings()
    end
end

controller:RegisterEvent("PLAYER_LOGIN")
controller:RegisterEvent("PLAYER_ENTERING_WORLD")
controller:RegisterEvent("ZONE_CHANGED_NEW_AREA")
controller:RegisterEvent("PLAYER_REGEN_DISABLED")
controller:RegisterEvent("PLAYER_REGEN_ENABLED")
controller:RegisterEvent("ADDON_LOADED")
controller:RegisterEvent("UI_SCALE_CHANGED")
controller:RegisterEvent("DISPLAY_SIZE_CHANGED")

controller:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
        return
    end

    if event == "ADDON_LOADED" then
        InstallTooltipHook()
        InstallActionButtonStyling()
        ScheduleRefresh()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RefreshInstanceBehaviorState()
        ScheduleRefresh()
        InstallActionButtonStyling()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateAllRules()
        return
    end

    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        UpdateAllRules()
    end
end)

controller:SetScript("OnUpdate", function(_, elapsed)
    if not addonEnabled or #rules == 0 then
        return
    end

    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < (controller.updateInterval or 0.05) then
        return
    end

    elapsedSinceUpdate = 0
    UpdateAllRules()
end)

SLASH_GAWAHUD1 = "/gawahud"
SLASH_GAWAHUD2 = "/ghud"

SlashCmdList.GAWAHUD = function(message)
    local command = strtrim(string.lower(message or ""))

    if command == "audit" then
        Audit()
        return
    end

    if command == "disable" or command == "off" then
        addonEnabled = false
        RestoreAllFrames()
        Print("Visibility policies disabled until the next reload or /gawahud enable.")
        return
    end

    if command == "enable" or command == "on" then
        addonEnabled = true
        ns.ApplySettings()
        Print("Visibility policies enabled.")
        return
    end

    if command == "apply" or command == "refresh" then
        ns.ApplySettings()
        Print("Saved settings reapplied.")
        return
    end

    if command == "settings" or command == "options" then
        if ns.OpenSettings then
            ns.OpenSettings()
        else
            Print("The settings panel is not available yet.")
        end
        return
    end

    Print("Commands: /gawahud settings, /gawahud audit, /gawahud enable, /gawahud disable, /gawahud apply")
end

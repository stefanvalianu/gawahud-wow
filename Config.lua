local _, ns = ...

ns.displayName = "gawaHUD"

-- Static addon behavior. Per-element visibility mode and hidden opacity are
-- configured in-game under Options > AddOns > gawaHUD and are saved
-- account-wide in gawaHUDDB.

ns.config = {
    tooltip = {
        enabled = true,
        anchor = "ANCHOR_CURSOR_RIGHT",
    },

    actionButtons = {
        enabled = true,
        removeNormalTexture = true,
        removeEmptySlotArt = true,
        removeEmptySlotBackground = false,
    },

    visibility = {
        enabled = true,
        updateInterval = 0.05, -- 20 lightweight state/hover checks per second.
        mouseOutDelay = 0.15,
        fadeSeconds = 2,
        hoverPadding = 4,
        disableInInstancesByDefault = true,
    },

    chatNotifications = {
        enabled = true,
        holdSeconds = 8,
        fadeSeconds = 2,
    },
}

-- Each definition becomes one row in the native AddOns settings page.
-- mouseover remains intentionally code-controlled to keep the options surface
-- small. Add or remove definitions here to change the supported frame catalog.
ns.elements = {
    {
        id = "chat",
        label = "Chat",
        description = "Chat text, tabs, edit boxes, side buttons, channel controls, and toast notifications.",
        group = "chat",
        defaultMode = "always",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "player-status",
        label = "Player frame, buffs, and debuffs",
        description = "The player's health, power, portrait, buffs, and debuffs as one visibility group.",
        group = "playerStatus",
        defaultMode = "outOfCombat",
        defaultOpacity = 0,
        mouseover = true,
        healthVisibility = {
            unit = "player",
            defaultEnabled = true,
            defaultThreshold = 80,
        },
    },
    {
        id = "target-frame",
        label = "Target unit frame",
        description = "The current target's unit frame.",
        group = "targetFrame",
        defaultMode = "never",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "focus-frame",
        label = "Focus unit frame",
        description = "The current focus target's unit frame.",
        group = "focusFrame",
        defaultMode = "never",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "pet-frame",
        label = "Pet unit frame",
        description = "The player's pet unit frame.",
        group = "petFrame",
        defaultMode = "outOfCombat",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "action-bars",
        label = "Action bars",
        description = "The primary action bar and all additional multi-action bars enabled through Edit Mode.",
        group = "actionBars",
        defaultMode = "outOfCombat",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "utility-action-bars",
        label = "Pet, stance, and possess bars",
        description = "Pet actions, stance or shapeshift actions, and possess controls.",
        group = "utilityActionBars",
        defaultMode = "outOfCombat",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "bag-bar",
        label = "Bag bar",
        description = "Backpack and bag-slot buttons.",
        group = "bagBar",
        defaultMode = "always",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "micro-menu",
        label = "Micro menu",
        description = "Character, spellbook, talents, achievements, collections, game menu, and related buttons.",
        group = "microMenu",
        defaultMode = "always",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "minimap",
        label = "Minimap",
        description = "Terrain and indoor/cave map tiles. The map stays fully opaque in indoor render modes to avoid Blizzard's black-map alpha bug.",
        group = "minimap",
        defaultMode = "always",
        defaultOpacity = 66,
        mouseover = true,
    },
    {
        id = "minimap-extras",
        label = "Minimap decorations and buttons",
        description = "Compass chrome, clock, zone title, calendar, tracking, mail, queue, addon-compartment, zoom, and expansion buttons when available.",
        group = "minimapExtras",
        defaultMode = "always",
        defaultOpacity = 0,
        mouseover = true,
    },
    {
        id = "objectives",
        label = "Quest tracker and status bars",
        description = "Quest, campaign, achievement, and scenario objectives, plus the primary and secondary experience, reputation, honor, or other status bars.",
        group = "objectives",
        defaultMode = "always",
        defaultOpacity = 0,
        mouseover = true,
    },
}

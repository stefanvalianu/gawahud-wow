local addonName, ns = ...
local displayName = ns.displayName or "gawaHUD"

local panel
local category
local rows = {}
local initialized = false
local disableInInstancesCheckbox

local MODE_OPTIONS = {
    { value = "never", label = "Never" },
    { value = "outOfCombat", label = "Outside combat" },
    { value = "inCombat", label = "During combat" },
    { value = "always", label = "Always" },
}
local function ClampPercent(value, minimum)
    value = tonumber(value) or minimum or 0
    value = math.floor(value + 0.5)
    return math.max(minimum or 0, math.min(100, value))
end

local function ApplyChange()
    if ns.ApplySettings then
        ns.ApplySettings()
    end
end

local function CommitOpacity(row)
    local saved = ns.GetElementSettings(row.definition.id)
    if not saved then
        return
    end
    local value = ClampPercent(row.opacityBox:GetText(), 0)
    row.opacityBox:SetText(tostring(value))

    if saved.opacity ~= value then
        saved.opacity = value
        ApplyChange()
    end

    row.opacityBox:ClearFocus()
end

local function CommitHealthThreshold(row)
    local saved = ns.GetElementSettings(row.definition.id)
    if not saved or not row.healthThresholdBox then
        return
    end
    local value = ClampPercent(row.healthThresholdBox:GetText(), 1)
    row.healthThresholdBox:SetText(tostring(value))

    if saved.healthThreshold ~= value then
        saved.healthThreshold = value
        ApplyChange()
    end

    row.healthThresholdBox:ClearFocus()
end

local function SetHealthThresholdEnabled(row, enabled)
    if not row.healthThresholdBox then
        return
    end

    row.healthThresholdBox:SetEnabled(enabled)
    row.healthThresholdBox:SetAlpha(enabled and 1 or 0.5)
    if row.healthPercent then
        row.healthPercent:SetAlpha(enabled and 1 or 0.5)
    end
end

local function RefreshRow(row)
    local saved = ns.GetElementSettings(row.definition.id)
    if not saved then
        return
    end

    row.opacityBox:SetText(tostring(ClampPercent(saved.opacity, 0)))
    if row.modeDropdown.GenerateMenu then
        row.modeDropdown:GenerateMenu()
    end
    if row.healthCheckbox then
        local enabled = saved.healthThresholdEnabled == true
        row.healthCheckbox:SetChecked(enabled)
        row.healthThresholdBox:SetText(tostring(
            ClampPercent(saved.healthThreshold, 1)
        ))
        SetHealthThresholdEnabled(row, enabled)
    end
end

local function RefreshGeneralSettings()
    if not disableInInstancesCheckbox or not ns.GetGeneralSettings then
        return
    end
    local saved = ns.GetGeneralSettings()
    disableInInstancesCheckbox:SetChecked(
        saved and saved.disableInInstances == true
    )
end

local function CreateModeDropdown(parent, definition)
    local dropdown = CreateFrame(
        "DropdownButton",
        nil,
        parent,
        "WowStyle1DropdownTemplate"
    )
    dropdown:SetWidth(170)
    dropdown:SetDefaultText("Select behavior")
    dropdown:SetupMenu(function(_, rootDescription)
        local saved = ns.GetElementSettings(definition.id)

        local function IsSelected(value)
            return saved and saved.mode == value
        end

        local function SetSelected(value)
            if saved and saved.mode ~= value then
                saved.mode = value
                ApplyChange()
            end
        end
        for _, option in ipairs(MODE_OPTIONS) do
            rootDescription:CreateRadio(
                option.label,
                IsSelected,
                SetSelected,
                option.value
            )
        end
    end)

    return dropdown
end
local function CreateHealthThresholdControls(row)
    local checkbox = CreateFrame(
        "CheckButton",
        nil,
        row,
        "UICheckButtonTemplate"
    )
    checkbox:SetPoint("TOPLEFT", row, "TOPLEFT", 17, -58)
    checkbox:SetSize(24, 24)
    row.healthCheckbox = checkbox
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
    label:SetWidth(275)
    label:SetJustifyH("LEFT")
    label:SetText("Always show when player health is at or below")
    row.healthLabel = label
    local thresholdBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    thresholdBox:SetSize(48, 24)
    thresholdBox:SetPoint("LEFT", label, "RIGHT", 8, 0)
    thresholdBox:SetAutoFocus(false)
    thresholdBox:SetNumeric(true)
    thresholdBox:SetMaxLetters(3)
    thresholdBox:SetJustifyH("CENTER")
    row.healthThresholdBox = thresholdBox
    local percent = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    percent:SetPoint("LEFT", thresholdBox, "RIGHT", 4, 0)
    percent:SetText("%")
    row.healthPercent = percent

    checkbox:SetScript("OnClick", function()
        local saved = ns.GetElementSettings(row.definition.id)
        if not saved then
            return
        end
        local enabled = checkbox:GetChecked() and true or false
        saved.healthThresholdEnabled = enabled
        SetHealthThresholdEnabled(row, enabled)
        ApplyChange()
    end)
    thresholdBox:SetScript("OnEnterPressed", function()
        CommitHealthThreshold(row)
    end)
    thresholdBox:SetScript("OnEditFocusLost", function()
        CommitHealthThreshold(row)
    end)
    thresholdBox:SetScript("OnEscapePressed", function()
        RefreshRow(row)
        thresholdBox:ClearFocus()
    end)
end

local function CreateSettingsPanel()
    panel = CreateFrame("Frame")
    panel.name = displayName
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(displayName)
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -30, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(
        "Settings are saved immediately in one account-wide profile shared by all Retail characters. "
        .. "Hidden opacity is an absolute percentage; 0% is fully invisible."
    )
    local instanceRow = CreateFrame("Frame", nil, panel)
    instanceRow:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -12)
    instanceRow:SetPoint("RIGHT", panel, "RIGHT", -30, 0)
    instanceRow:SetHeight(46)

    disableInInstancesCheckbox = CreateFrame(
        "CheckButton",
        nil,
        instanceRow,
        "UICheckButtonTemplate"
    )
    disableInInstancesCheckbox:SetPoint("TOPLEFT", 0, 0)
    disableInInstancesCheckbox:SetSize(26, 26)
    local instanceLabel = instanceRow:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormal"
    )
    instanceLabel:SetPoint("LEFT", disableInInstancesCheckbox, "RIGHT", 3, 1)
    instanceLabel:SetText("Disable addon behavior in instances")
    local instanceDescription = instanceRow:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontHighlightSmall"
    )
    instanceDescription:SetPoint("TOPLEFT", instanceLabel, "BOTTOMLEFT", 0, -3)
    instanceDescription:SetPoint("RIGHT", instanceRow, "RIGHT", 0, 0)
    instanceDescription:SetJustifyH("LEFT")
    instanceDescription:SetText(
        "Use normal frame opacity, Blizzard tooltip anchoring, and action-button artwork in all instanced content."
    )
    disableInInstancesCheckbox:SetScript("OnClick", function()
        local saved = ns.GetGeneralSettings and ns.GetGeneralSettings()
        if not saved then
            return
        end

        saved.disableInInstances = disableInInstancesCheckbox:GetChecked()
            and true
            or false
        ApplyChange()
    end)
    local nameHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    nameHeader:SetPoint("TOPLEFT", instanceRow, "BOTTOMLEFT", 8, -14)
    nameHeader:SetText("UI element")

    local modeHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    modeHeader:SetPoint("TOPLEFT", instanceRow, "BOTTOMLEFT", 348, -14)
    modeHeader:SetText("Conceal")
    local opacityHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    opacityHeader:SetPoint("TOPLEFT", instanceRow, "BOTTOMLEFT", 543, -14)
    opacityHeader:SetText("Hidden opacity")

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        panel,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", nameHeader, "BOTTOMLEFT", -8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 14)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(660)
    scrollFrame:SetScrollChild(content)

    local yOffset = 0
    for index, definition in ipairs(ns.elements or {}) do
        local hasHealthThreshold = type(definition.healthVisibility) == "table"
        local rowHeight = hasHealthThreshold and 88 or 54
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        row:SetHeight(rowHeight)
        row.definition = definition

        if index % 2 == 0 then
            local background = row:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            background:SetColorTexture(1, 1, 1, 0.025)
        end
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", 4, -8)
        label:SetWidth(320)
        label:SetJustifyH("LEFT")
        label:SetText(definition.label)
        local description = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        description:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        description:SetWidth(320)
        description:SetJustifyH("LEFT")
        description:SetText(definition.description or "")

        local dropdown = CreateModeDropdown(row, definition)
        dropdown:SetPoint("TOPLEFT", row, "TOPLEFT", 345, -12)
        row.modeDropdown = dropdown
        local opacityBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        opacityBox:SetSize(48, 24)
        opacityBox:SetPoint("TOPLEFT", row, "TOPLEFT", 548, -15)
        opacityBox:SetAutoFocus(false)
        opacityBox:SetNumeric(true)
        opacityBox:SetMaxLetters(3)
        opacityBox:SetJustifyH("CENTER")
        row.opacityBox = opacityBox
        local percent = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        percent:SetPoint("LEFT", opacityBox, "RIGHT", 4, 0)
        percent:SetText("%")
        opacityBox:SetScript("OnEnterPressed", function()
            CommitOpacity(row)
        end)
        opacityBox:SetScript("OnEditFocusLost", function()
            CommitOpacity(row)
        end)
        opacityBox:SetScript("OnEscapePressed", function()
            RefreshRow(row)
            opacityBox:ClearFocus()
        end)

        if hasHealthThreshold then
            CreateHealthThresholdControls(row)
        end
        rows[#rows + 1] = row
        yOffset = yOffset + rowHeight + 4
    end

    content:SetHeight(math.max(yOffset, 1))

    panel:SetScript("OnShow", function()
        RefreshGeneralSettings()
        for _, row in ipairs(rows) do
            RefreshRow(row)
        end
    end)

    category = Settings.RegisterCanvasLayoutCategory(panel, displayName)
    Settings.RegisterAddOnCategory(category)
end

function ns.InitializeSettings()
    if initialized then
        return
    end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    initialized = true
    CreateSettingsPanel()
end

function ns.OpenSettings()
    if not initialized then
        ns.InitializeSettings()
    end

    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

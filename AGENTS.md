# gawaHUD: Maintenance Intent

## Scope

Retail WoW only. Keep this addon a small presentation policy over Blizzard's
existing UI, not a replacement UI framework.

## Invariants

- Prefer alpha changes over `Show`, `Hide`, reparenting, or method replacement.
- Do not alpha-manage Blizzard frames that own alpha animations; use separate visual alpha targets and hover hitboxes.
- Reveals are immediate; concealment interpolates to the configured opacity.
- Settings use one account-wide `SavedVariables` table and save immediately.
- `Config.lua` defines the supported settings catalog and static behavior.
- `Groups.lua` contains all Blizzard frame-name and hierarchy knowledge.
- `Core.lua` stays generic: resolve groups, evaluate policy, hover, and fades.
- Chat wakes by securely hooking rendered `AddMessage` calls, then fades.
- Tooltip changes apply only to Blizzard's default tooltip anchor.
- Action-button styling removes persistent rim/slot art, not state feedback.
- The instance override suppresses only visibility/opacity policies. Cursor tooltip
  positioning and action-button styling are persistent presentation rules and must
  remain active in instances. The override never mutates per-element policies and
  does not require a reload.
- The player-status and Cooldown Viewer groups keep independent conceal/opacity
  settings but share one hover-reveal hit set in both directions.

## Version Maintenance

1. Test the exact current Retail build and update the TOC interface number.
2. Run `/gawahud audit`; use `/fstack` for missing or renamed frames.
3. Repair `Groups.lua` first. Change `Core.lua` only for proven API behavior
   changes. Optional frame paths must remain nil-safe.
4. Preserve SavedVariables migrations when IDs are renamed or merged.
5. Smoke-test login/reload, combat transitions, hover fades, chat messages,
   Edit Mode, vehicle UI, pet battles, and resolution/UI-scale changes.

Do not add libraries, XML, per-character profiles, or custom configuration UI
unless the requirements materially outgrow the native Settings panel.

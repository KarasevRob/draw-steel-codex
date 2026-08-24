# Hide Enemy Actions

Standalone Draw Steel Codex CodeMod that prevents hostile ability actions from appearing in player Action Logs while preserving the Director's full log.

## Setting

Game Settings -> **Hide Enemy Actions from Players**

- Checked (default): hostile ability actions are hidden from players.
- Unchecked: Codex uses its normal Action Log visibility behavior.
- The checkbox is Director-only and stored at game scope.

## How it works

The mod stays outside Codex core files and uses the same extension/lifecycle points that Codex already exposes:

- `ActivatedAbility:Cast` is wrapped only to classify the cast and install an `options.OnFinishCastHandlers` cleanup callback.
- `RollDialog.OnBeforeRoll` forces matching enemy rolls to `dmonly` before `dmhub.Roll`.
- Roll-dialog `ShowDialog` functions are decorated so a hidden deterministic roll does not take the early shortcut that bypasses `RollDialog.OnBeforeRoll`.
- The main cast card and known ability-result message types are suppressed on player clients by wrapping their Lua `Render` methods.
- The cast-card fallback preserves `castid`, so any linked roll that is visible long enough to be built by Action Log is adopted into the collapsed cast container.

There is no `chat.messages` polling loop and the mod does not replace the engine-owned `chat.SendCustom` method.

## Hostility

When the ability has a player-side target, hostility follows the caster/target relationship via `CharacterToken:IsFriend`, matching Codex's existing enemy-power-roll logic. For self buffs, area actions, and casts without a player-side target, the mod falls back to `CharacterToken.isFriendOfPlayer`.

## Custom Action Log cards

Player-side render suppression is installed for the ability-system cards that can be identified without timing heuristics:

- `CastActivatedAbilityChatMessage`
- `ActivatedAbilityDamageChatMessage`
- `ActivatedAbilityPurgeEffectsChatMessage`
- `ActivatedAbilityTemporaryStaminaChatMessage`
- `HealChatMessage` when its affected token is enemy-side

This is UI privacy, not transport secrecy: DMHub's `chat.SendCustom` API has no documented producer-side `gmonly` argument, so custom message data can still be transmitted to clients even though these cards do not render for players. Rolls use true producer-side `dmonly` visibility.

## Hot reload and the old broken revision

The first development revision attempted to assign `chat.SendCustom` and could fail after already replacing `ActivatedAbility.Cast`. That failed load cannot be safely unwound because its captured base function is no longer reachable.

If that revision has been loaded in the current DMHub process, **restart DMHub once before testing this version**. The new source detects the legacy state and refuses to stack another wrapper over it.

After a clean restart, this version records every Lua-side wrapper it installs and restores it on unload/hot reload.

## DMHub registration

Register the CodeMod source file through the running DMHub CodeMod workflow:

`Hide Enemy Actions/HideEnemyActions.lua`

Do not hand-edit generated `main.lua`.

## Suggested verification

1. Restart DMHub if the old `chat.SendCustom` error occurred in this process.
2. Enable **Hide Enemy Actions from Players**.
3. As Director, use a normal power-roll enemy ability against a hero. Confirm the Director sees the cast card and roll, while a player sees neither.
4. Test an enemy ability with a deterministic roll (for example a fixed-value damage/stamina roll). Confirm it is still private and reaches the normal `dmonly` roll path.
5. Test enemy damage, purge, temporary-stamina, and heal result cards where available. Confirm the known secondary cards do not render for players.
6. Use an enemy self-buff or enemy-vs-enemy ability. Confirm it is hidden.
7. Use a friendly/player ability with the setting enabled. Confirm it remains visible.
8. Disable the setting and repeat an enemy ability. Confirm normal Codex visibility returns.
9. Hot reload/unload the mod after a clean start and confirm ability casting and rolls continue to work normally.

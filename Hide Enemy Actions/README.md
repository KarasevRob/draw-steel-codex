# Hide Enemy Actions

Standalone Draw Steel Codex CodeMod that prevents hostile ability actions from appearing in player Action Logs while preserving the Director's full log.

## Setting

Game Settings -> **Hide Enemy Actions from Players**

- Checked (default): hostile ability actions are Director-only.
- Unchecked: Codex uses its normal Action Log visibility behavior for new actions.
- The checkbox is Director-only and stored at game scope.

## What is hidden

While a hostile token is executing an `ActivatedAbility:Cast`:

- custom Action Log messages sent by the cast are marked Director-only;
- rolls produced by that cast are forced to `dmonly` through the public `RollDialog.OnBeforeRoll` hook;
- the main `CastActivatedAbilityChatMessage` renderer has a player-side collapsed fallback so the ability card cannot flash during visibility synchronization;
- the fallback preserves `castid`, allowing a linked roll to be adopted into the hidden card if it races the Director-only roll update.

Hostility uses `CharacterToken.isFriendOfPlayer`: friendly/player-side tokens keep normal Action Log behavior.

## Source

`HideEnemyActions.lua`

The mod wraps existing APIs at runtime and restores them on unload/hot reload. It does not modify Codex core files.

## DMHub registration

This repository requires new Lua files to be registered through the running DMHub CodeMod bridge. Register:

`Hide Enemy Actions/HideEnemyActions.lua`

Do not hand-edit generated `main.lua` to load it. The source retries hook installation until `ActivatedAbility`, `CastActivatedAbilityChatMessage`, `RollDialog`, and `chat` are available, so it does not depend on a brittle cross-module load position.

## Suggested verification

1. Enable **Hide Enemy Actions from Players**.
2. As Director, use a power-roll enemy ability against a hero.
3. Confirm the Director sees the cast card and roll.
4. Confirm a player sees neither the cast card nor its roll and receives no Action Log entry for the hidden action.
5. Repeat with an enemy ability that produces a secondary custom Action Log message (for example, damage/healing text) and confirm it is also hidden.
6. Disable the setting and repeat; new enemy actions should use normal Codex visibility.
7. Use a friendly/player ability with the setting enabled; it should remain visible normally.

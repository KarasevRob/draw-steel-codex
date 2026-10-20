# Equivalent 25-item UI-only authoring trial: Broadhurst - 2026-10-20

This was an equivalent 25-item usability trial, not an exact before/after comparison. I used only the live map UI (screenshots, visible-text lookup, mouse, and keyboard) as a new author; I did not inspect implementation, reload, publish, restart, change games, move the Party, or present the map to players.

Approximate authoring time: 15-20 minutes, including discovering the UI and the secondary interaction attempts.

## Completion

- **19 named location pins:** Broadhurst Market; Upper Farmsteads; North Gate; River Ford; Millbridge; Stonewatch Pass; Pineward Grove Trailhead; Old Orchard; South Fields; Redwater Lake; Fishers Bend; Eastwood Crossing; Wildflower Meadow; Mossy Hollow; Timberline Camp; Southridge Camp; High Peak; West Gate; Quarry Cliffs.
- **6 text labels:** The Broadhurst Vale; The Greenway; Northwood; The Greyspine Peaks; River Redwater; Southern Marches.
- The map's visible status chip read **"25 hidden from players"** after the final item. Pins and labels were placed throughout the art, including the west mountain edge, east meadow edge, and southern edge.

Ordinary authoring interactions that succeeded:

- The top-bar `+` exposed visible **Add location** and **Add label** choices.
- A location could be placed by selecting Add location, clicking the map, entering a name in the quick field, and pressing Enter. Placement mode remained active for subsequent pins.
- A label could be placed by selecting Add label, clicking the map, entering its text, and pressing Enter. Placement mode remained active for subsequent labels.
- Clicking **Pineward Grove** opened its side editor. I changed its name to **Pineward Grove Trailhead** and clicked Done; the revised name appeared on the map.
- Clicking **The Broadhurst Vale** opened its label editor, which visibly exposed its visibility, text, font, alignment, size, rotation, spacing, and color fields.

## Criticisms observed

1. **The first authoring affordance was not self-describing.** On the initial unlabeled map, the top row presented icon-only controls. I found the creation workflow only by clicking the `+`, which then revealed text choices for **Add location** and **Add label**. There was no visible authoring prompt before that click.

2. **High-volume pin entry involves a repeated multi-step cycle.** After choosing Add location, each of the 19 pins required a map click, a name entry, and an Enter commit. Placement mode remained active, so the creation menu did not need to be reopened for each pin, but names still had to be entered and committed one at a time.

3. **Default label presentation can obscure nearby content.** After ordinary placement, the large white **River Redwater** label visually overlapped the smaller **Fishers Bend** name-plate. Other large labels consumed substantial portions of the illustrated map, even without deliberate style changes.

4. **Moving a selected label was not discoverable or successful.** I clicked **The Broadhurst Vale**, which opened the label editor, then dragged the selected label from its center toward an open nearby position. Its displayed position did not change. The visible editor showed text and styling controls, but no position control in the portion displayed during the attempt.

5. **The visible player-facing status did not verify a player view.** The map reported that all 25 trial items were hidden, and the selected pin/label editors both showed **Hidden** selected. I did not find or complete an in-app player-view check before UI control was returned, so the actual player rendering remains unverified.

## Unfinished secondary checks and state changes

- **Location editing:** completed successfully (Pineward Grove renamed to Pineward Grove Trailhead).
- **Label move:** attempted once by drag; unsuccessful and left as an unfinished verification.
- **What players can see:** only the author-facing hidden count and selected-item visibility controls were observed. No player-facing preview, reveal, send/present action, or Party movement was performed.
- **Viewer preferences / visibility changes:** none were changed. All 25 trial items remain hidden from players.

## Follow-up by the implementing developer

- Read-only model inspection confirmed the reported 19 named pins and 6 labels before cleanup.
- The visibility overlay preference was on at handback, despite the tester reporting no intentional preference change. It was restored to its original off state.
- The developer separately verified locked-drag feedback, Unlock, and unselected-label movement on Broadhurst. Those checks do not change the blind tester's unsuccessful movement observation.
- After deploying the final permission-refresh guard, a new Quick Add name survived an explicit reconciliation event and saved with Enter. Player preview then returned zero trial pins and labels and excluded the unshared trial map from the visible UI. No map was presented to players.
- The generated trial map and its items were removed. The original Broadhurst was reopened with its original 19 pins and 6 labels, positions locked, visibility overlay off, MCDM theme, 100% font, and restored window geometry.


# Overland Map - Open ideas

Only unfinished work belongs here. Implemented behavior is documented in
[README.md](README.md). Idea numbers stay stable for existing references.

**Open** means not designed or scheduled. **Later** means saved by the user for a
future phase. **Deferred** means do not design or implement it until the user
reopens it.

The Overland rename and fresh-storage decision are implemented; see
[the rewrite record](docs/REWRITE_PLAN.md). Curves and the other deferred features
below remain outside this rewrite.

## Open

| ID | Idea | Remaining scope |
|---|---|---|
| 10 | Torn edge and Frame borders | None and Soft fade exist. The remaining borders need the user's [art](docs/BORDER_ART.md), rendering, and fit/camera integration. |
| 13 | Further path editing | Bend editing and Redraw line already exist. Clarify whether the requested addition is changing endpoint pins while preserving the path's details, or improving the existing reshaping controls. |
| 14 | Curved paths | Smooth routes that follow the artwork. Sampling, hit tests, labels, travel and historical routes must agree. [Current research](docs/CURVED_PATHS_RESEARCH.md) includes a live native-path probe and its limitations. |
| 21 | Player edit settings per map | Group player edit permissions in one settings section and configure them separately for each map. |
| 22 | Comments in the user's voice | Code-only work following the user's writing style document. |

[Implementation research](docs/IDEAS_RESEARCH.md) covers ideas 10, 13, 16 and 17.
It records possible approaches, not approved designs or current effort estimates.
Ideas 16, 17 and 20 are implemented together in [Map aids](docs/MAP_AIDS_BRIEF.md).
The follow-up adds a dedicated toolbar editor, direct click-drag selection, None
backgrounds by default, and immediate compass text resizing.

## Saved for later

**12. Multi-leg route planning.** Preview routes to a destination on the same point
crawl map and compare total travel time. Travel currently operates one leg at a time.

The interaction is undecided: preview only, a plan followed leg by leg, or one action
for the whole route. Preserve hidden-path access rules, anonymous secret legs,
Director encounter control, and one log entry per leg. Player route proposals were
excluded from the earlier scope. [Research](docs/IDEAS_RESEARCH.md#12-route-planning)
describes one possible implementation.

## Deferred by the user

- **3. Hex overlay and distance measurement.** Grid size, orientation and offset per map.
- **3.1 / 7.1. Hex travel mode.** Party travel and Locations tied to hexes. Point crawl
  travel is already implemented and is not part of this backlog item.
- **7.3. Conversion between map modes.** Creation already offers Free or Point crawl.
  Adding Hex mode and converting existing maps remain deferred.

All hex work was deferred on 2026-10-11; no V2.2 hex phase is scheduled.

## Unresolved capability research

**Uploaded custom fonts.** The user requested feasibility research. No confirmed
mod-only TTF/OTF upload route was found. Preserve the findings in
[text appearance research](docs/TEXT_APPEARANCE_RESEARCH.md#uploaded-custom-fonts);
this is not an approved engine-development task.

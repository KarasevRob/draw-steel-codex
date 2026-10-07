# Region Map - Feature Ideas

Ideas only, unless marked. Crossed-out ideas are **Delivered in V2** (built, see
[README.md](README.md)). **V2.1** means planned next (see [TECH_TASK_V2.md](TECH_TASK_V2.md)
section 5). Unmarked ideas are not designed, approved or scheduled. The open ideas are ranked
at the end.

1. ~~**Label backgrounds.** A background behind label text so it stays readable on busy map
   art.~~ *Delivered in V2* (names on a halo, or the Name plate pin style).

2. ~~**Locations instead of labels.** Labels become Locations: objects that can contain
   entities (such as the Party) and other Locations, and through those, other region
   maps.~~ *Delivered in V2.*

3. **Hex overlay with distance calculation.** *V2.1.* An optional hex grid over the map,
   with distances measured in hexes.

   3.1. **Party travel paths.** *V2.1.* The Party moves along a path across the map instead
   of being placed freely.

4. ~~**Drag the Party.** Move the Party by dragging it, instead of move tool, click,
   move.~~ *Delivered in V2.*

5. ~~**Icons above labels and locations.** An icon shown above each label or
   location.~~ *Delivered in V2* (Icon + name pin style).

6. ~~**Icon-only labels.** A label can be shown as just an icon, with its text on
   hover.~~ *Delivered in V2* (Icon only pin style).

7. **Hex mode and Point crawl mode.** Two travel modes for a region map (builds on 3 and 3.1).

   7.1. **Hex mode.** The Party moves between hexes on the region map, and each Location
   is tied to a hex.

   7.2. **Point crawl mode.** Works much like today: each Location is tied to a point. But
   the Party can only move between points along paths the Director sets up in advance.
   Each path has a description and attributes (which attributes is still to be decided).

8. ~~**Read the parent's description from the top left.** While inside a Location, you can
   read the description of the Location that contains it from the top left of the window.
   For example, while in a town inside a barony, you can read the barony's description
   without leaving the town.~~ *Delivered in V2.x* (hover a breadcrumb part for a preview,
   right-click it to read it in the side panel).

## Open ideas, ranked

Easiest first, by design effort, build effort and risk. V2 already has pieces several of
these can reuse: map scale and travel pace, the ruler (a line drawn between two points, with
its distance and travel time), the Party's route in the session log, and the breadcrumb.

| Rank | Idea | Design | Build | Data change | Main risk |
|---|---|---|---|---|---|
| ~~1~~ | ~~8. Parent's description~~ | | | | *Delivered in V2.x.* |
| 2 | 3. Hex overlay with distances | Medium | Medium | Small, added fields: hex size, orientation, offset per map | Drawing hundreds of hexes on a canvas that zooms and pans, at V2's frame times. May need a tiled grid image instead of a panel per hex. |
| 3 | 7.2. Point crawl mode | Large | Medium to large | New: a path record (two Locations, description, attributes) | The path attributes are undecided. Also needs a path editor for the Director, and the Party limited to paths. Lines between points already exist through the ruler. |
| 4 | 3.1. Party travel paths | Large | Medium | Some: a planned route | Has no clear shape on its own. Moving "along a path" means hex steps in hex mode and Director paths in point crawl mode. Best designed as part of 7, not before it. |
| 5 | 7.1. Hex mode | Large | Large | Yes: Locations tied to hexes, and existing Locations need moving onto hexes | Changes the data model and how Locations are placed and moved. Needs 3 first. Every existing map would need a move onto hexes. |

Suggested order: 8 on its own, as a V2.x addition (done). Then one V2.1 brief covering 3, 3.1 and 7
together, since 7 decides what 3.1 means and whether 3 is only an overlay or the base for
hex mode. Within V2.1, build 3 first, then 7.2, then 7.1.

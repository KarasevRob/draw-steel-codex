# Overland Map - Feature Ideas

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

   7.3. **Mode chosen at map creation.** Each map is either a point crawl map or a hex crawl
   map, picked when the map is created, so a map never mixes the two. Converting a map from
   one mode to the other is worth considering, but much later in development.

8. ~~**Read the parent's description from the top left.** While inside a Location, you can
   read the description of the Location that contains it from the top left of the window.
   For example, while in a town inside a barony, you can read the barony's description
   without leaving the town.~~ *Delivered in V2.x* (hover a breadcrumb part for a preview,
   right-click it to read it in the side panel).

9. **Import Locations from JSON.** Load Location data (names, descriptions, nesting and so
   on) from a JSON file instead of entering it by hand. By default each imported Location's
   pin is placed near the center of its parent Location's map, grouped close together, for
   the Director to drag into place.

10. **Map image border.** A basic border around the map image (for example a soft, worn or
    torn edge instead of a hard rectangle) so the map looks more organic.

11. **Image size guidance on upload.** When choosing a map image, show the minimum, maximum
    and recommended size, and warn when the chosen image falls outside them. On screen this
    is pixel size (width and height) rather than DPI, which only matters for print.

## Open ideas, ranked

Easiest first, by design effort, build effort and risk. V2 already has pieces several of
these can reuse: map scale and travel pace, the ruler (a line drawn between two points, with
its distance and travel time), the Party's route in the session log, and the breadcrumb.

| Rank | Idea | Design | Build | Data change | Main risk |
|---|---|---|---|---|---|
| ~~1~~ | ~~8. Parent's description~~ | | | | *Delivered in V2.x.* |
| 2 | 11. Image size guidance | Small | Small | None | The image picker is the engine's, so the guidance is text beside it and a warning after the upload. The numbers need measuring: largest size that still zooms smoothly and loads within the 10 s image timeout. |
| 3 | 10. Map image border | Small to medium | Small to medium | Maybe one per-map choice of border style | The border must zoom and pan with the image. A frame or mask image over the canvas is cheap; a true soft edge depends on what masking the engine allows. |
| 4 | 9. Import Locations from JSON | Small to medium | Medium | None: imported rows are ordinary Locations | The file is untrusted input, so every row must pass the same validation as a typed edit. The format (ids, how nesting is written, re-importing a file) is undecided. A large import meets the 250-pin guard and needs one undo for the whole import. |
| 5 | 3. Hex overlay with distances | Medium | Medium | Small, added fields: hex size, orientation, offset per map | Drawing hundreds of hexes on a canvas that zooms and pans, at V2's frame times. May need a tiled grid image instead of a panel per hex. |
| 6 | 7.2. Point crawl mode | Large | Medium to large | New: a path record (two Locations, description, attributes) | The path attributes are undecided. Also needs a path editor for the Director, and the Party limited to paths. Lines between points already exist through the ruler. |
| 7 | 3.1. Party travel paths | Large | Medium | Some: a planned route | Has no clear shape on its own. Moving "along a path" means hex steps in hex mode and Director paths in point crawl mode. Best designed as part of 7, not before it. |
| 8 | 7.1. Hex mode | Large | Large | Yes: Locations tied to hexes, and a mode field per map (7.3) | Changes the data model and how Locations are placed and moved. Needs 3 first. With 7.3, existing maps stay point crawl maps, so none has to move onto hexes. |
| 9 | 7.3, conversion between modes | Large | Large | Moves every Location of a map between points and hexes | Deferred by the user to much later. Point to hex has to snap each pin to a hex; hex to point drops the hexes. |

Suggested order: 8 on its own, as a V2.x addition (done). 11 and 10 are small V2.x
additions with no data model change; 11 is the smaller of the two. 9 can come at any time,
since it
only writes ordinary Locations; it is easiest before V2.1 changes the Location record. Then
one V2.1 brief covering 3, 3.1 and 7 together, since 7 decides what 3.1 means and whether 3
is only an overlay or the base for hex mode. 7.3 settles that a map's mode is fixed at
creation. Within V2.1, build 3 first, then 7.2, then 7.1. Conversion between modes waits.

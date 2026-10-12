# Overland Map - Feature Ideas

Ideas only, unless marked. Crossed-out ideas are **Delivered** in V2 or V2.1 (built, see
[README.md](README.md); V2.1 is [docs/V2_1_BRIEF.md](docs/V2_1_BRIEF.md)). **TBA** means
deferred with no date: set aside by the user, not to be designed or built until they bring
it back. **Later** means saved by the user for a future leg. Unmarked ideas are not
designed, approved or scheduled. The open ideas are ranked at the end.

1. ~~**Label backgrounds.** A background behind label text so it stays readable on busy map
   art.~~ *Delivered in V2* (names on a halo, or the Name plate pin style).

2. ~~**Locations instead of labels.** Labels become Locations: objects that can contain
   entities (such as the Party) and other Locations, and through those, other region
   maps.~~ *Delivered in V2.*

3. **Hex overlay with distance calculation.** *TBA (deferred by the user 2026-10-11; was
   planned as V2.2).* An optional hex grid over the map, with distances measured in hexes.

   3.1. **Party travel paths.** The Party moves along a path across the map instead
   of being placed freely. *Point crawl maps: delivered in V2.1 with 7.2. Hex steps wait for
   7.1 (TBA).*

4. ~~**Drag the Party.** Move the Party by dragging it, instead of move tool, click,
   move.~~ *Delivered in V2.*

5. ~~**Icons above labels and locations.** An icon shown above each label or
   location.~~ *Delivered in V2* (Icon + name pin style).

6. ~~**Icon-only labels.** A label can be shown as just an icon, with its text on
   hover.~~ *Delivered in V2* (Icon only pin style).

7. **Hex mode and Point crawl mode.** Two travel modes for a region map (builds on 3 and 3.1).

   7.1. **Hex mode.** *TBA (deferred by the user 2026-10-11; was planned as V2.2).* The
   Party moves between hexes on the region map, and each Location is tied to a hex.

   7.2. ~~**Point crawl mode.** Works much like today: each Location is tied to a point. But
   the Party can only move between points along paths the Director sets up in advance.
   Each path has a description and attributes.~~ *Delivered in V2.1* (paths with a type,
   travel time each way, description and Director note; travel and stops along them; one
   log entry per leg).

   7.3. **Mode chosen at map creation.** Each map is either a point crawl map or a hex crawl
   map, picked when the map is created, so a map never mixes the two. Converting a map from
   one mode to the other is worth considering, but much later in development.
   *Choosing the mode at creation is delivered in V2.1 (Free or Point crawl). Hex crawl waits
   for 7.1; conversion stays deferred.*

8. ~~**Read the parent's description from the top left.** While inside a Location, you can
   read the description of the Location that contains it from the top left of the window.
   For example, while in a town inside a barony, you can read the barony's description
   without leaving the town.~~ *Delivered in V2.x* (hover a breadcrumb part for a preview,
   right-click it to read it in the side panel).

9. ~~**Import Locations from JSON.** Load Location data (names, descriptions, nesting and so
   on) from a JSON file instead of entering it by hand. By default each imported Location's
   pin is placed near the center of its parent Location's map, grouped close together, for
   the Director to drag into place.~~ *Delivered in V2.1* (into the open map, one undo; the
   format is [docs/IMPORT_FORMAT.md](docs/IMPORT_FORMAT.md)).

10. **Map image border.** A basic border around the map image (for example a soft, worn or
    torn edge instead of a hard rectangle) so the map looks more organic.
    *V2.1: None and Soft fade are delivered. Torn edge and Frame are deferred until the user
    provides their art ([docs/BORDER_ART.md](docs/BORDER_ART.md), brief K9).*

11. ~~**Image size guidance on upload.** When choosing a map image, show the minimum, maximum
    and recommended size, and warn when the chosen image falls outside them. On screen this
    is pixel size (width and height) rather than DPI, which only matters for print.~~
    *Delivered in V2.1* (1500 / 4000 / 12000 px wide).

12. **Route planning on point crawl maps.** *Later (added 2026-10-11; the user approved the
    idea and saved it for later, with the frame below not yet agreed).* When the Party
    wants to reach a Location several paths away, find the way there: preview the route on
    the map with its total length (travel time), and preferably offer several possible
    routes to choose from. Today Travel to only offers the paths leaving where the Party is,
    one leg at a time. The V2.1 brief deferred "planned multi-leg routes", a travel time
    total and route proposals by players, to revisit once a real region was built; this
    idea reopens the first two.

    *Draft frame (2026-10-11, not yet agreed):*
    - Problem: when the Party wants to reach a Location several paths away, nobody can see
      the way there or how long it takes; the Director traces paths by eye and adds times.
    - For whom: the power-user Director compares routes (fastest, fewest legs, avoiding a
      path type) and keeps control of each leg for encounters; the set-and-forget user picks
      a destination and sees the route and total time; players (only while "Players can
      move the Party" is on) get routes over the paths they see.
    - Kept from V2.1: routes stay on one map (paths do not leave the map edge); players
      never see hidden paths and secret legs stay anonymous; one log entry per leg; no
      player route proposals; one Director per game; no changes outside the mod.
    - First design round: what a chosen route turns into. A preview only (still travel one
      leg at a time), a plan the Party follows leg by leg (the Director can stop for an
      encounter), or travelling the whole route at once. This decides the data model.

13. **Edit a path's route after it is made.** *Added 2026-10-13.* Change the line a path
    takes once it exists. Much of this is already built in V2.1: with pins unlocked, the
    selected path's bends can be dragged, added (the "+" handles) and removed (right-click),
    and "..." > Redraw line draws the line again between the same two pins. What does not
    exist is changing which pins a path joins: both ends are fixed at creation, so moving an
    end today means deleting the path and making a new one, losing its name, type, times,
    description and note. The first design question is whether the idea means that, or a
    better way to reshape the line than the current handles.

14. **Curved paths.** *Added 2026-10-13.* A path can bend smoothly instead of in straight
    segments, to follow rivers, coasts and winding roads in the art. The V2.1 brief chose
    straight segments with bends on purpose (D1: "follows the art without curve costs"), so
    this reopens that decision. Drawing: lines are runs of short panels, so a curve becomes
    many short segments, and the piece count and the re-place cost after a zoom grow with it
    (see the pan and zoom measurements in [README.md](README.md)); the engine's
    `panel.shapes` API has `GetCurvePoints` and `AddPath` and may draw a curve more cheaply,
    but it is barely used and its cost is unmeasured. Data: existing bends could become
    curve control points, so old paths keep their shape if curves are a per-path option.

## Open ideas, ranked

Easiest first, by design effort, build effort and risk. V2 already has pieces several of
these can reuse: map scale and travel pace, the ruler (a line drawn between two points, with
its distance and travel time), the Party's route in the session log, and the breadcrumb.

| Rank | Idea | Design | Build | Data change | Main risk |
|---|---|---|---|---|---|
| ~~1~~ | ~~8. Parent's description~~ | | | | *Delivered in V2.x.* |
| ~~2~~ | ~~11. Image size guidance~~ | | | | *Delivered in V2.1.* |
| 3 | 10. Map image border: Torn edge and Frame | Small | Small | None (the `border` field exists) | Waits for the user's art. The tiles, the setting and the check for the art are built. |
| ~~4~~ | ~~9. Import Locations from JSON~~ | | | | *Delivered in V2.1.* |
| Later | 12. Route planning | Medium | Small to medium | None for a preview; some if a planned route is kept | Saved for later by the user. The search is cheap at the tested sizes (250 pins, about 300 paths a map; the per-map cap was removed 2026-10-10, so larger maps are possible). The open questions are design ones: what "travel the route" does to the log and to encounters along the way, and what players may see. |
| - | 13. Edit a path's route (change its end pins) | Small | Small to medium | None: `aId` / `bId` exist, but a Party stopped on the path must move with it | Bend editing and Redraw line already exist, so the scope needs agreeing first. A moved end can create a second path between the same two pins, which must then bow apart, and the log's past legs on the path must stay readable. |
| - | 14. Curved paths | Medium | Medium | Small if per path (a curve flag; bends become control points) | Reverses V2.1 decision D1. Many more line pieces per path, so it depends on making the path re-place cheaper (or on `panel.shapes`); hit testing and labels must follow the curve. |
| TBA | 3. Hex overlay with distances | Medium | Medium | Small, added fields: hex size, orientation, offset per map | Deferred by the user. Drawing hundreds of hexes on a canvas that zooms and pans, at V2's frame times. May need a tiled grid image instead of a panel per hex. The path layer's pooled pieces (V2.1) cost ~0.14 ms each to create, so a panel per hex is costly. |
| ~~6~~ | ~~7.2. Point crawl mode~~ | | | | *Delivered in V2.1.* |
| TBA | 3.1. Party travel paths, hex mode | Medium | Medium | Some: a planned route | Deferred by the user. The point crawl half is delivered. Hex steps are part of 7.1. |
| TBA | 7.1. Hex mode | Large | Large | Yes: Locations tied to hexes, and a mode field per map (7.3) | Deferred by the user. Changes the data model and how Locations are placed and moved. Needs 3 first. With 7.3, existing maps stay point crawl maps, so none has to move onto hexes. |
| TBA | 7.3, conversion between modes | Large | Large | Moves every Location of a map between points and hexes | Deferred by the user to much later. Point to hex has to snap each pin to a hex; hex to point drops the hexes. |

Suggested order: 8 on its own, as a V2.x addition (done). 11 and 10 are small V2.x
additions with no data model change; 11 is the smaller of the two. 9 can come at any time,
since it
only writes ordinary Locations; it is easiest before V2.1 changes the Location record. Then
one V2.1 brief covering 3, 3.1 and 7 together, since 7 decides what 3.1 means and whether 3
is only an overlay or the base for hex mode. 7.3 settles that a map's mode is fixed at
creation. Within V2.1, build 3 first, then 7.2, then 7.1. Conversion between modes waits.

V2.1 as built (2026-10-10): 11, 10 (None and Soft fade), 9 and 7.2 with the creation part
of 7.3. Next: Torn edge and Frame when the art arrives.

2026-10-11: the user deferred all hex work (3, 3.1's hex steps, 7.1, and 7.3 conversion) to
TBA, so there is no V2.2 hex leg. Route planning (12) is saved for later; its design starts
from the draft frame under idea 12.

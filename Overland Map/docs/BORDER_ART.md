# Overland Map - Border art format (V2.1, K3)

Soft fade needs no art. The other two looks, **Torn edge** and **Frame**, use art the user
supplies. They were removed from Settings on 2026-10-19 (TODO in `OverlandMapConstants.lua`);
rendering is not implemented yet.
Supplying the artwork IDs alone will not finish these borders. Items marked *check*
need live verification when implementation resumes.

The artist-facing version of this spec, with a template drawing, is the doc "Overland Map
border art brief" (2026-10-12). Revised the same day: the mask went from 2048 to 4096 px and
the frame from 512 px / 96 px inset to 1024 px / 192 px, and the frame's edge rule was
corrected (the engine's 9-slice, `bgslice`, stretches edges; it does not repeat them).

## Torn edge: a mask

The mask is laid over the map image. It is stretched to the image's size, so one mask
serves every map.

| Item | Requirement |
|---|---|
| File | PNG with an alpha channel |
| Meaning | Opaque = the map shows; transparent = the map is cut away. Use white for the opaque part (*check*: the engine may read luminance instead of alpha; white on transparent works either way) |
| Size | 4096 x 4096 px. Maps are recommended at 4000 px wide and may be 12000, so the tear line is never enlarged more than about 3x. Square is fine: it is stretched, and torn shapes stay believable when stretched up to about 2:1 if the tears are many and small rather than one long rip |
| Shape | A ragged edge all round, inside the outer 3-6% of the width and height. Leave the middle fully opaque, because pins near the edge must not sit on cut-away paper (pins always draw above, Q23) |
| Corners | Torn or rounded, as you like; no hard transparent notches deeper than 8% |
| Style | Plain shape only: no shading or colour. The map's own art shows through |

## Frame: a 9-slice image

The frame is drawn **outside** the map image, adding a margin (K7). The four corners keep
their size, and the edges stretch.

| Item | Requirement |
|---|---|
| File | PNG with an alpha channel |
| Size | 1024 x 1024 px (room to scale down cleanly, whatever on-screen thickness the build settles on) |
| Slice inset | 192 px on every side: the corners are 192 x 192, and the edges are 192 px thick. If your art needs another inset, tell me the number |
| Middle | Fully transparent, 640 x 640, not even a shadow (it is stretched to the map's size) |
| Inner edge | The frame's inner edge sits exactly on the inset line, so it meets the map's edge. A few px of overlap past the line are fine; they cover the image's outer pixels |
| Edges | Stretched along their length, not repeated (`bgslice`), so each edge must look the same at every point along it: bands, bevels and lines parallel to the edge only. Grain, rope, studs or any ornament along an edge gets smeared; decoration goes in the corners |
| Colour | Final colours; the frame is not tinted by the theme |

## Handing the art over

Upload both files as images in the DMHub journal library and send me their ids, or drop the
PNGs in the repo and say where they are. *Check:* whether a library image id is readable in
other games that load the mod. If it isn't, the art ships as an asset that every game can
read; decide how when border implementation resumes.

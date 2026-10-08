# Overland Map - Border art format (V2.1, K3)

Soft fade needs no art. The other two looks, **Torn edge** and **Frame**, use art the user
supplies. Their tiles in Settings stay disabled until the art is in (task V21-04 in
[TECH_TASK_V2_1.md](../TECH_TASK_V2_1.md)). Written 2026-10-08. The two items marked
*check* are confirmed with a live test when V21-04 starts, and this file is corrected if
needed.

## Torn edge: a mask

The mask is laid over the map image. It is stretched to the image's size, so one mask
serves every map.

| Item | Requirement |
|---|---|
| File | PNG with an alpha channel |
| Meaning | Opaque = the map shows; transparent = the map is cut away. Use white for the opaque part (*check*: the engine may read luminance instead of alpha; white on transparent works either way) |
| Size | 2048 x 2048 px. Square is fine: it is stretched, and torn shapes stay believable when stretched up to about 2:1 |
| Shape | A ragged edge all round, inside the outer 3-6% of the width and height. Leave the middle fully opaque, because pins near the edge must not sit on cut-away paper (pins always draw above, Q23) |
| Corners | Torn or rounded, as you like; no hard transparent notches deeper than 8% |
| Style | Plain shape only: no shading or colour. The map's own art shows through |

## Frame: a 9-slice image

The frame is drawn **outside** the map image, adding a margin (K7). The four corners keep
their size, and the edges stretch.

| Item | Requirement |
|---|---|
| File | PNG with an alpha channel |
| Size | 512 x 512 px |
| Slice inset | 96 px on every side: the corners are 96 x 96, and the edges are 96 px thick. If your art needs another inset, tell me the number |
| Middle | Fully transparent (the map shows there) |
| Inner edge | The frame's inner edge sits exactly on the inset line, so it meets the map's edge. A few px of overlap past the line are fine; they cover the image's outer pixels |
| Edges | Must repeat cleanly when stretched: no single ornament in the middle of an edge, because a stretch would distort it |
| Colour | Final colours; the frame is not tinted by the theme |

## Handing the art over

Upload both files as images in the DMHub journal library and send me their ids, or drop the
PNGs in the repo and say where they are. *Check:* whether a library image id is readable in
other games that load the mod. If it isn't, the art ships as an asset that every game can
read; we decide how when V21-04 starts.

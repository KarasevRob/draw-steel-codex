# Region Map image generation prompts

Historical generation inputs only. Current behavior and the UI-state guide are maintained in [REGION_MAP.md](../../REGION_MAP.md#5-ui-guide).

Generated with the built-in image_gen tool. No reference images were supplied.

## Sheet 1

```text
Use case: ui-mockup.
Create a high-resolution landscape UI guide sheet for the Region Map addon in a tabletop virtual tabletop app. Strict black and white schematic wireframes: white background, black 1-2px lines, plain readable sans-serif text, outlined buttons, no color, no grey fills, no gradients, no shadows, no realistic textures, no decorative illustration. A sparse schematic coastline and 3 tiny mountain triangles may represent map content. NOT a tactical battle grid. No browser or desktop chrome.
Composition: title above a precise 2 by 2 grid of FOUR large distinct application-window mockups, each with an external numbered state caption and one short explanatory caption below. Generous gutters. Large readable text. Each mockup has consistent journal-style window header "Region Map", tiny pin, collapse and close symbols. Landscape 3:2 sheet. Keep controls orderly, avoid overflow or overlapping text. Main image viewport dominates each window. Use ONLY the concise UI text specified; use abbreviated icon buttons +, -, Fit on bottom-right of viewport. Never turn explanatory captions into application UI. This is a proposed schematic guide based on an existing implementation brief, not a polished product screenshot.
Sheet title: "REGION MAP / 01 SETUP & BROWSING".
Top left numbered caption "01 Director / empty". Empty canvas centered text "Create your first region map", second line "Add an image, then publish it.", outlined "Create Map" button. No map art. Caption below window "Director creates the first map."
Top right numbered caption "02 Player / empty". Empty canvas centered text "No region maps have been shared yet." No create or management controls. Caption below "Players see published maps only."
Bottom left numbered caption "03 Director / draft". Toolbar "[North Coast - Draft v] [Labels] [Add Label] [Move Party] [Present] [...]". Present button drawn dashed disabled. Show map canvas left with a few schematic coast lines; right drawer titled "Map actions", field labeled "Map name" containing "North Coast", image thumbnail rectangle, buttons "Replace Image", "Publish Map". Footer "Draft - visible to Director". Caption below "Prepare the image and name before publishing."
Bottom right numbered caption "04 Player / published". Toolbar "[North Coast v] [Labels] [Add Label] [Move Party]". Move Party dashed disabled. Large coast map with plain labels "Harbor" and "Old Tower", small outlined circle marker and adjacent fixed text "Party" above labels. Footer "Only the Director can move Party." Canvas bottom-right [-] [+] [Fit], bottom-left "[x] Show Labels". No Present or map management controls. Caption below "Browse, pan, zoom, and add shared labels."
```

## Sheet 2

```text
Use case: ui-mockup.
Create a high-resolution landscape UI guide sheet for the Region Map addon in a tabletop virtual tabletop app. Strict black and white schematic wireframes: white background, black 1-2px lines, plain readable sans-serif text, outlined buttons, no color, no grey fills, no gradients, no shadows, no realistic textures, no decorative illustration. A sparse schematic coastline and 3 tiny mountain triangles may represent map content. NOT a tactical battle grid. No browser or desktop chrome.
Composition: title above a precise 2 by 2 grid of FOUR large distinct application-window mockups, each with an external numbered state caption and one short explanatory caption below. Generous gutters. Large readable text. Each mockup has consistent journal-style window header "Region Map", tiny pin, collapse and close symbols. Landscape 3:2 sheet. Keep controls orderly, avoid overflow or overlapping text. Main image viewport dominates each window. Use ONLY the concise UI text specified; use abbreviated icon buttons +, -, Fit on bottom-right of viewport. Never turn explanatory captions into application UI. This is a proposed schematic guide based on an existing implementation brief, not a polished product screenshot.
Sheet title: "REGION MAP / 02 LABELS, PARTY & PRESENT".
All four windows use same simple coastline map "North Coast", not a tactical grid.
Top left caption "05 Add label / armed". Toolbar "[North Coast v] [Labels] [Add Label] [Move Party]"; Add Label button emphasized double black outline. Canvas has crosshair and anchored small inline editor: label "Label text", input "Old Tower", buttons "Save" and "Cancel". Footer "Adding label - click map or press Enter. Esc cancels." Caption below "Place a label, enter text, then save."
Top right caption "06 Labels / selected". Toolbar "[North Coast v] [Labels] [Add Label] [Move Party]". Large map occupies left two thirds; right drawer "Labels", search field "Search labels", two list rows "Harbor" and "Old Tower", selected Old Tower double outline. Below list: "Created by Alex", "Visible to: Everyone", field "Old Tower", buttons "Save", "Move on map", "Delete Label". Map label Old Tower emphasized outline. Footer "Shared". Caption below "Find overlapping labels and edit permitted entries."
Bottom left caption "07 Move Party / armed". Toolbar "[North Coast v] [Labels] [Add Label] [Move Party]" with Move Party double-outline selected. Map has old outlined circle labeled "Party", crosshair at new location; dotted arrow from old Party toward crosshair as schematic annotation. Footer "Moving Party - click map or press Enter. Esc cancels." Canvas [-] [+] [Fit]. Caption below "Preview locally; commit the new position on placement."
Bottom right caption "08 Present / recipient". Player window toolbar "[North Coast v] [Labels] [Add Label] [Move Party]". Fit view showing whole image centered with clear letterboxing, markers "Harbor", "Old Tower", "Party". External small annotation with arrow to image "Fit once". Footer "Party is on North Coast." Caption below "Present opens the map once; recipients then browse freely."
```

## Sheet 3

```text
Use case: ui-mockup.
Create a high-resolution landscape UI guide sheet for the Region Map addon in a tabletop virtual tabletop app. Strict black and white schematic wireframes: white background, black 1-2px lines, plain readable sans-serif text, outlined buttons, no color, no grey fills, no gradients, no shadows, no realistic textures, no decorative illustration. A sparse schematic coastline and 3 tiny mountain triangles may represent map content. NOT a tactical battle grid. No browser or desktop chrome.
Composition: title above a precise 2 by 2 grid of FOUR large distinct application-window mockups, each with an external numbered state caption and one short explanatory caption below. Generous gutters. Large readable text. Each mockup has consistent journal-style window header "Region Map", tiny pin, collapse and close symbols. Landscape 3:2 sheet. Keep controls orderly, avoid overflow or overlapping text. Main image viewport dominates each window. Use ONLY the concise UI text specified; use abbreviated icon buttons +, -, Fit on bottom-right of viewport. Never turn explanatory captions into application UI. This is a proposed schematic guide based on an existing implementation brief, not a polished product screenshot.
Sheet title: "REGION MAP / 03 LOADING & LIFECYCLE".
Top left caption "09 Image / loading". Toolbar "[North Coast v] [Labels] [Add Label] [Move Party]". Empty viewport with simple incomplete circle spinner and centered "Loading map...". Canvas outline only, no map art. Caption below "Stream only the selected map image."
Top right caption "10 Image / unavailable". Director toolbar "[North Coast v] [Labels] [Add Label] [Move Party] [...]". Empty viewport centered outlined image-error icon, "Map image could not be loaded.", buttons "Retry" and "Replace Image". Caption below "Retry loading or let the Director replace the image."
Bottom left caption "11 Player / Party hidden". Player toolbar "[South Coast v] [Labels] [Add Label] [Move Party]". Simple South Coast map with two labels "Village" and "Bridge". No Party marker, no draft map name or badge anywhere. Footer exactly "Party location is not shared." Caption below "Party can remain on a draft without revealing its location."
Bottom right caption "12 Director / delete confirmation". Underlying region map window with sparse map and toolbar; centered white outlined modal, no gray overlay. Modal title "Delete North Coast?". Body three short lines: "Removes this map and its 12 labels.", "Party location will become unknown.", "The image remains in your library." Buttons "Cancel" and "Delete Map" with Delete Map heavier black outline, no color. Caption below "Confirm removal; deleting the map unplaces Party."

```

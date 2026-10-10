# Overland Map: JSON import format

The Director can fill a map with Locations from a JSON file (V2.1 idea 9, brief IM1-IM7).
Open the map, then choose **Import locations...** from a right-click on the map, or from
the map's own "..." menu in the side panel.

The import:
- adds the Locations as pins on the open map, one level deep;
- never imports paths, maps or nested Locations;
- shows a preview first, and imports nothing until you press Import;
- adds new Locations each time, even if you import the same file twice. The preview lists
  names that are already on the map;
- can be removed with one Undo.

## File shape

The file holds a list of entries, either as the whole file:

```json
[
  { "name": "Kell's Ferry" },
  { "name": "Ashford", "u": 0.42, "v": 0.61 }
]
```

or under a `locations` key, so other tools can keep their own data beside it:

```json
{ "locations": [ { "name": "Kell's Ferry" } ] }
```

## Entry fields

Only `name` is required. Unknown fields are ignored.

| Field | Type | Allowed values | When left out |
|---|---|---|---|
| `name` | text | One line, 1 to 80 characters | The entry is skipped |
| `description` | text | Up to 4000 characters; players see it once the Location is revealed | Empty |
| `note` | text | Up to 8000 characters; the Director note, players never see it | Empty |
| `icon` | text | `city`, `town`, `castle`, `tower`, `temple`, `tavern`, `camp`, `port`, `bridge`, `forest`, `cave`, `dungeon`, `danger`, `treasure`, `quest`, `poi` | The default pin |
| `pinStyle` | text | `iconName`, `plate`, `iconOnly` | `iconName` |
| `importance` | text | `major`, `normal`, `minor` | `normal` |
| `visibility` | text | `hidden`, `revealed` | `hidden`: players don't see new Locations until you reveal them |
| `u`, `v` | number | Both from 0 to 1: the share of the map's width (from the left) and height (from the top) | Set out in rows near the center of the map |

`u` and `v` go together: give both or neither.

## What the preview checks

- **Skipped entries:** an entry with a missing or invalid field is skipped, and the preview
  gives its number in the file and the reason. The other entries still import.
- **Names already on the map:** they are listed, and they are imported again.
- **The pin limit:** a map holds up to 250 Locations. A file that would go over is refused
  whole, and the card says how many more the map has room for. Split the file and import it
  in parts.
- **Errors:** a file that isn't valid JSON, has no entries, or has no entry that can be
  imported shows a card with the reason, and nothing is imported.

## Example

[import-example.json](import-example.json) holds one entry of each kind.

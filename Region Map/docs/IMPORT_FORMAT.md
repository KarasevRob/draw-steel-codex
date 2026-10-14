# Overland Map: JSON import format

The Director can fill a map with Locations by pasting JSON or choosing a JSON file
(ideas 9 and 18; the original import contract is brief IM1-IM7).
Open the map, then choose **Import locations** (the file with an up arrow) beside Add in
the top toolbar, or use **Import locations** in an Atlas card's "..." menu.

## Import card

- Paste JSON into the editor, then choose **Preview**, or use **Choose file...** to go
  straight to a file preview. **Into {map}** identifies the destination.
- **JSON contract** shows a Swagger-style field reference beside the editor: field names,
  types, a required marker, enums, defaults, limits and coordinate dependencies.
  **Copy contract** copies the full reference as plain text, including offscreen fields,
  and briefly reads **Copied**. It never changes the draft. The reference scrolls; in
  narrow windows it sits below the editor. Import action buttons
  remain outside the scrolling body.
- **Fill with example** inserts two hidden Locations: one with every supported field,
  and one with only a name. It asks before replacing nonempty text. The example contains
  ordinary JSON, with no comments.
- Pasted JSON is limited to **100,000 Unicode characters**, including whitespace. The
  counter uses characters, not UTF-8 bytes. Oversized text cannot reach preview; use a
  file for larger input. File import has no added size limit.
- **Back** returns to the editor without losing pasted text. Invalid JSON remains
  editable. Canceling the file picker or choosing an invalid file also keeps the draft.
  A valid file asks before discarding a nonempty draft and opening its preview; Back
  then returns to an empty editor.
- **Cancel** and **Escape** ask before discarding nonempty pasted text. The mod's own
  close, fullscreen toggle and popout controls use that same check. Drafts are temporary:
  native OS-window close, app exit and Lua reload discard them without a prompt.
- If the destination or Director permission becomes unavailable, nothing new is
  imported and the draft remains available to copy. If the map's name, image or duplicate
  warnings change after preview, Import refreshes the preview and asks for another click.

The import:
- adds the Locations as pins on the open map, one level deep;
- never imports paths, maps or nested Locations;
- shows a preview first, and imports nothing until you press Import;
- adds new Locations each time, even if you import the same file twice. The preview lists
  names that are already on the map;
- can be removed with one Undo.

## File shape

The JSON holds a list of entries, either as the whole input:

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
| `name` | text | One trimmed line, 1 to 256 Unicode characters | The entry is skipped |
| `description` | text | Up to 4000 characters; players see it once the Location is revealed | Empty |
| `note` | text | Up to 8000 characters; the Director note, players never see it | Empty |
| `icon` | text | `city`, `town`, `castle`, `tower`, `temple`, `tavern`, `camp`, `port`, `bridge`, `forest`, `cave`, `dungeon`, `danger`, `treasure`, `quest`, `poi` | The default pin |
| `pinStyle` | text | `iconName`, `plate`, `iconOnly` | `iconName` |
| `importance` | text | `major`, `normal`, `minor` | `normal` |
| `visibility` | text | `hidden`, `revealed` | `hidden`: players don't see new Locations until you reveal them |
| `u`, `v` | number | Both from 0 to 1: the share of the map's width (from the left) and height (from the top) | Set out in rows near the center of the map |

`u` and `v` go together: give both or neither.

The field reference and clipboard text use the same field definitions and copy. Limits
come from the importer's constants. Swagger is the visual reference; the helper presents
readable fields and rules, without an OpenAPI or JSON Schema document.

## What the preview checks

- **Skipped entries:** an entry with a missing or invalid field is skipped, and the preview
  gives its number in the file and the reason. The other entries still import.
- **Names already on the map:** they are listed, and they are imported again.
- **No pin limit:** a map holds any number of Locations, so a file of any size imports.
  Very large files are slow (rows are created a batch at a time) and pin counts above 250 a
  map are not performance-tested.
- **Errors:** a file that isn't valid JSON, has no entries, or has no entry that can be
  imported shows a card with the reason, and nothing is imported.

Pasted input uses the same field checks, duplicate warnings, grid placement and single
Undo as files. Do not add `//` or `/* ... */` comments; keep explanations outside the JSON.
The engine parser is shared with existing Codex JSON consumers, not a new strict JSON
validator. A leading UTF-8 BOM is tolerated in pasted text.

## Example

[import-example.json](import-example.json) holds one entry of each kind.

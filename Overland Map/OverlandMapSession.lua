local mod = dmhub.GetModLoading()

--- The view-session contract shared by the shell and its components.
--- @class OverlandMapSession: GameType
--- @field new fun(o?: table): OverlandMapSession
OverlandMapSession = RegisterGameType("OverlandMapSession")
local C = OverlandMapConstants
local Model = OverlandMapModel

--- @class OverlandMapSessionParticipant
--- @field scope any
--- @field valid fun(): boolean
--- @field flush nil|fun()
--- @field cancel nil|fun(reason: string, id: nil|string)
--- @field gesture nil|fun(reason: string)

local participants = {} --- @type table<OverlandMapSessionParticipant, boolean>
local interactions = setmetatable({}, { __mode = "k" })
local continuations = setmetatable({}, { __mode = "k" })

--- A pending UI action may finish its save after navigation, but must not reclaim focus.
--- @param scope OverlandMapContext
--- @param allowed nil|fun(): boolean
--- @return fun(): boolean
function OverlandMapSession.Guard(scope, allowed)
    local generation = interactions[scope] or 0
    interactions[scope] = generation
    local game = OverlandMapLifetime.Capture()
    local active = true
    local function valid()
        active = active and OverlandMapLifetime.Valid(game) and scope.IsAlive()
            and interactions[scope] == generation and (allowed == nil or allowed())
        return active
    end
    continuations[valid] = scope
    return valid
end

--- Coalesces named change domains without assuming that engine events identify a row.
function OverlandMapSession.Changes()
    local pending = {}
    return {
        Mark = function(domain) pending[domain or "all"] = true end,
        Take = function()
            local result = pending
            pending = {}
            return result
        end,
    }
end

--- @param participant OverlandMapSessionParticipant
--- @return fun() unsubscribe
function OverlandMapSession.Register(participant)
    participants[participant] = true
    return function() participants[participant] = nil end
end

--- Transitions visit owners, never sibling panels. Host resizing preserves text and tool drafts.
--- @param reason string
--- @param scope any
--- @param id nil|string
function OverlandMapSession.Transition(reason, scope, id)
    if reason ~= "flush" and reason ~= "resize" and reason ~= "reconcile" then
        if scope ~= nil then interactions[scope] = (interactions[scope] or 0) + 1
        else for owner, generation in pairs(interactions) do interactions[owner] = generation + 1 end end
    end
    if reason == "reconcile" then
        Model.ReconcilePermissions()
        for valid, owner in pairs(continuations) do
            if (scope == nil or owner == scope) and not valid() then continuations[valid] = nil end
        end
    end
    local flush = reason ~= "resize" and reason ~= "undo" and reason ~= "permission" and reason ~= "game" and reason ~= "reconcile"
    local cancel = reason == "undo" or reason == "permission" or reason == "game" or reason == "reconcile"
    local current = {}
    for participant in pairs(participants) do current[#current + 1] = participant end
    for _, participant in ipairs(current) do
        if participants[participant] and (scope == nil or participant.scope == scope) then
            if not participant.valid() then participants[participant] = nil
            else
                if flush and participant.flush then participant.flush() end
                if reason ~= "flush" and reason ~= "reconcile" and participant.gesture then participant.gesture(reason) end
                if cancel and participant.cancel then participant.cancel(reason == "reconcile" and "permission" or reason, id) end
            end
        end
    end
end

Model.RegisterCompanion {
    beforeViewChange = function() OverlandMapSession.Transition("viewAsPlayer") end,
    cancelMap = function(id) OverlandMapSession.Transition("undo", nil, id) end,
}
OverlandMapLifetime.Subscribe(function()
    OverlandMapSession.Transition("game")
    participants = {}
end)

--- A saved per-viewer camera. zoom 1 fits the whole map in the canvas.
--- @class OverlandMapCamera
--- @field zoom number
--- @field centerX number 0..1 across the image
--- @field centerY number 0..1 down the image
--- @field allowEdgeFocus nil|boolean transient Find-on-map view; lets an edge anchor reach the centre

--- The shell's state. Components read it; only the shell and the functions on
--- the context change it.
--- @class OverlandMapShellData
--- @field mapId nil|string the open map; nil shows the Atlas
--- @field selectedId nil|string the Location in the side panel
--- @field selectedPathId nil|string the path in the path panel (panelMode "path")
--- @field selectedLabelId nil|string selected map lettering, including a local creation draft
--- @field selectedAid nil|string compass or scaleBar being edited
--- @field aidMapId nil|string the map whose aid editor owns the selection
--- @field panelMode "none"|"read"|"edit"|"pickMode"|"pickImage"|"pickMap"|"pickJournal"|"log"|"path"|"pathEdit"|"pickPathEnd"|"party"|"labelEdit"
--- @field pickKind nil|"add"|"replace" what pickImage does with the image
--- @field newMapMode nil|"free"|"pointcrawl" the kind picked for Add map (A1), until its image is chosen
--- @field locked boolean pins and labels cannot be dragged (R6); per viewer, true on every map open
--- @field tool "none"|"add"|"move"|"ruler"|"scale"|"path"|"redraw"|"labelAdd"|"aidPlace"
--- @field toolTargetId nil|string the Location "move" places, or the path "redraw" redraws
--- @field pathDraft nil|OverlandMapPathDraft the line the Path tool or Redraw line is drawing
--- @field camera OverlandMapCamera
--- @field panelInset number pixels of the map's right edge an open panel covers; the camera may pan that much further
--- @field focusName boolean the side panel puts the caret in the name field once
--- @field popover nil|"search"|"settings"|"aids" the popover open under the toolbar
--- @field ruler nil|OverlandMapMeasure the ruler's points (local, never written)
--- @field scaleDraft nil|OverlandMapMeasure the two scale points picked so far, until a distance is entered

--- Two points on the open map. The second is absent while only a start is picked.
--- @class OverlandMapMeasure
--- @field mapId string
--- @field u1 number
--- @field v1 number
--- @field u2 nil|number
--- @field v2 nil|number
--- @field unit nil|"mi"|"km" scale drafts only: the unit picked before the distance

--- A path being drawn. The Path tool fills startId with the first pin
--- clicked; Redraw line starts with both ends fixed.
--- @class OverlandMapPathDraft
--- @field mapId string
--- @field startId nil|string the a end, once picked
--- @field endId nil|string Redraw line: the only pin that finishes
--- @field pathId nil|string Redraw line: the path whose bends are replaced
--- @field bends OverlandMapBend[]

--- What ctx.Confirm shows. alternate adds a third button between the confirm
--- and Cancel (the hidden-path travel question, W1).
--- @class OverlandMapConfirmArgs
--- @field title string
--- @field message nil|string
--- @field confirm string
--- @field onConfirm fun()
--- @field alternate nil|string
--- @field onAlternate nil|fun()

--- Shared services handed to every component. Components call these; the
--- shell answers by firing events on component roots.
--- @class OverlandMapContext
--- @field data OverlandMapShellData
--- @field root Panel
--- @field IsAlive fun(): boolean
--- @field CurrentMap fun(): nil|OverlandMapLocationRecord
--- @field OpenMap fun(id: string, how: nil|"down"|"up"|"jump"|"fit"|"restore")
--- @field GoAtlas fun()
--- @field GoUp fun()
--- @field Select fun(id: nil|string, mode: nil|string)
--- @field SelectPath fun(id: nil|string, mode: nil|"path"|"pathEdit") show a path in the path panel; nil closes it
--- @field SelectLabel fun(id: nil|string, edit?: boolean)
--- @field CreateLabel fun(u: number, v: number)
--- @field FocusLabel fun(id: string, edit?: boolean)
--- @field SelectAid fun(kind: nil|string, edit?: boolean, reveal?: boolean)
--- @field KeepAidVisible fun(kind: string)
--- @field ClearAid fun()
--- @field FindAid fun(kind: string)
--- @field SetTool fun(tool: string, targetId: nil|string)
--- @field RefreshAll fun()
--- @field FlushEdits fun()
--- @field Transition fun(reason: string)
--- @field ShowMenu fun(element: Panel, id: string)
--- @field Report fun(ok: boolean, reason: nil|string): boolean shows a toast for a failed write
--- @field Push fun(entry: nil|OverlandMapUndoEntry, copyId: string, args: nil|table)
--- @field CheckImageSize fun(mapId: string, imageId: string) warns with a toast when a newly picked map image is outside the size range (J3)
--- @field ImageHint fun(): string the size guidance line shown by image pickers (J2)
--- @field ImportLocations fun() Director: open the JSON import card for the current map
--- @field ShowToPlayers fun()
--- @field Confirm fun(args: OverlandMapConfirmArgs) compact in-window confirm dialog
--- @field ShowParty fun() open the Party section (point crawl maps, G1)
--- @field StopOnPath fun(pathId: string) Director: open the stop card for a path (G3)
--- @field FocusLocation fun(id: string) open the map a Location is on, center it and select it (Search)
--- @field SetPopover fun(popover: nil|"search"|"settings"|"aids") open or close a toolbar popover
--- @field ToggleLog fun() open or close the session log panel
--- @field HandleEnter nil|fun(canvas: Panel) Enter on the canvas while the shell listens for it


--- @return OverlandMapCanvasState
function OverlandMapSession.CanvasState()
    return {
        mapId = nil, imageId = nil, imageRevision = nil,
        imageWidth = nil, imageHeight = nil, layout = nil,
        imageRequest = 0, crossfade = false, fadeStart = nil, animOnLoad = nil,
        drag = nil, lastDrag = nil, showNames = false, anim = nil,
        cameraDirty = false, cameraSaveScheduled = false,
        hovered = false, lastPointerX = nil, lastPointerY = nil, lastPointerMove = 0,
        keyEdges = {}, scale = 1,
        pinRef = nil, pinsDirty = true, pinInputs = "", lastWheel = -math.huge, zoomMoving = false, layerX = 0, layerY = 0,
        imageSizeW = nil, imageSizeH = nil,
        border = "none", fadeShown = nil, hoverPathId = nil, hoverX = nil, hoverY = nil, draftKey = "",
        move = nil, partyKey = "", partyLook = "", partyNow = nil, partyBefore = nil, moveWatchUntil = 0, movedIds = {},
    }
end

--- @return OverlandMapShellData
function OverlandMapSession.ViewState()
    return {
        mapId = nil, selectedId = nil, selectedPathId = nil, panelMode = "none", pickKind = nil, newMapMode = nil,
        locked = true, tool = "none", toolTargetId = nil, pathDraft = nil, panelInset = 0,
        camera = { zoom = C.minZoom, centerX = 0.5, centerY = 0.5 },
        focusName = false, popover = nil, ruler = nil, scaleDraft = nil,
    }
end

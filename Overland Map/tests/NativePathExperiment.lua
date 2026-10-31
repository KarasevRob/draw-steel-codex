-- Unregistered probe. The cleanup gate must pass before this can become a renderer.
local experiment = {}

function experiment.Create()
    local panel = gui.Panel {
        id = "overland-map-native-path-probe", width = 600, height = 400,
        floating = true, interactable = false,
    }
    local ids = {}
    local function Clear()
        for _, id in ipairs(ids) do panel.shapes:Remove(id) end
        ids = {}
    end
    local function Bind(points)
        Clear()
        local path = {}
        for _, point in ipairs(points) do path[#path + 1] = { x = point.u, y = point.v } end
        panel.shapes.thickness = 7
        panel.shapes.pencolor = "#151b24ff"
        ids[#ids + 1] = panel.shapes:AddPath { path = path }
        panel.shapes.thickness = 3
        panel.shapes.pencolor = "#f2ead7ff"
        ids[#ids + 1] = panel.shapes:AddPath { path = path }
    end
    return { layer = panel, Bind = Bind,
        Destroy = function() Clear(); if panel.valid then panel:DestroySelf() end end }
end

return experiment

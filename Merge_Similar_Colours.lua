-- ==============================================================================
-- Aseprite Script: Merge Similar Colors
-- Description: Iteratively merges colors in an image's palette and pixels that
--              are within a user-specified similarity percentage using either
--              RGB Distance or CIE Lab Color space.
-- Author: Dwarven Forge Helper / Ragoth
-- Installation: Aseprite -> File -> Scripts -> Open Scripts Folder -> Paste this file
-- ==============================================================================

local sprite = app.activeSprite
if not sprite then
    app.alert("No active sprite found. Please open an image in Aseprite first!")
    return
end

-- ------------------------------------------------------------------------------
-- Color Space & Distance Helper Functions
-- ------------------------------------------------------------------------------

-- Calculate RGB Euclidean Distance (Normalized to 0.0 - 1.0)
local function getRGBDistanceNormalized(c1, c2)
    local dr = c1.red - c2.red
    local dg = c1.green - c2.green
    local db = c1.blue - c2.blue
    local dist = math.sqrt(dr * dr + dg * dg + db * db)
    return dist / 441.67295593
end

-- Convert sRGB (0-255) to CIELAB (L*, a*, b*)
local function rgbToLab(c)
    local r = c.red / 255.0
    local g = c.green / 255.0
    local b = c.blue / 255.0

    r = (r > 0.04045) and (((r + 0.055) / 1.055) ^ 2.4) or (r / 12.92)
    g = (g > 0.04045) and (((g + 0.055) / 1.055) ^ 2.4) or (g / 12.92)
    b = (b > 0.04045) and (((b + 0.055) / 1.055) ^ 2.4) or (b / 12.92)

    local x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047
    local y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750) / 1.00000
    local z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883

    local f = function(t)
        return (t > 0.008856) and (t ^ (1.0 / 3.0)) or (7.787 * t + 16.0 / 116.0)
    end

    local fx = f(x)
    local fy = f(y)
    local fz = f(z)

    local L = 116.0 * fy - 16.0
    local a = 500.0 * (fx - fy)
    local b_val = 200.0 * (fy - fz)

    return { L = L, a = a, b = b_val }
end

-- Calculate CIELAB Delta E (Normalized to 0.0 - 1.0)
local function getLabDistanceNormalized(c1, c2)
    local lab1 = rgbToLab(c1)
    local lab2 = rgbToLab(c2)
    local dL = lab1.L - lab2.L
    local da = lab1.a - lab2.a
    local db = lab1.b - lab2.b
    local deltaE = math.sqrt(dL * dL + da * da + db * db)
    return math.min(1.0, deltaE / 100.0)
end

-- Calculate Weighted Average Color between two Colors
local function averageColor(c1, c2, w1, w2)
    w1 = w1 or 1
    w2 = w2 or 1
    local totalWeight = w1 + w2
    local r = math.floor((c1.red * w1 + c2.red * w2) / totalWeight + 0.5)
    local g = math.floor((c1.green * w1 + c2.green * w2) / totalWeight + 0.5)
    local b = math.floor((c1.blue * w1 + c2.blue * w2) / totalWeight + 0.5)
    local a = math.floor((c1.alpha * w1 + c2.alpha * w2) / totalWeight + 0.5)
    return Color{ r = r, g = g, b = b, a = a }
end

-- Convert Color to RGBA 32-bit Integer Key
local function colorToKey(c)
    return (c.alpha << 24) | (c.blue << 16) | (c.green << 8) | c.red
end

-- ------------------------------------------------------------------------------
-- Main Iterative Merging Logic
-- ------------------------------------------------------------------------------

local function mergePaletteColors(metricChoice, similarityThreshold)
    local maxDistAllowed = 1.0 - (similarityThreshold / 100.0)
    local distFunc = (metricChoice == "CIE Lab Color") and getLabDistanceNormalized or getRGBDistanceNormalized

    local initialPalette = sprite.palettes[1]
    local numColors = #initialPalette
    if numColors <= 1 then
        app.alert("Palette has 1 or fewer colors. Nothing to merge!")
        return
    end

    -- Extract unique palette colors
    local colorNodes = {}
    for i = 0, numColors - 1 do
        local col = initialPalette:getColor(i)
        if col.alpha > 0 then
            table.insert(colorNodes, {
                color = col,
                weight = 1,
                originalIndices = { i }
            })
        end
    end

    -- Iterative Agglomerative Merging Loop
    while true do
        local minDist = 999.0
        local minI, minJ = -1, -1
        local n = #colorNodes

        for i = 1, n - 1 do
            for j = i + 1, n do
                local d = distFunc(colorNodes[i].color, colorNodes[j].color)
                if d < minDist then
                    minDist = d
                    minI = i
                    minJ = j
                end
            end
        end

        -- Check if closest pair is within threshold
        if minI ~= -1 and minDist <= maxDistAllowed then
            local node1 = colorNodes[minI]
            local node2 = colorNodes[minJ]

            -- Merge node2 into node1 with weighted average
            local mergedColor = averageColor(node1.color, node2.color, node1.weight, node2.weight)
            node1.color = mergedColor
            node1.weight = node1.weight + node2.weight
            for _, idx in ipairs(node2.originalIndices) do
                table.insert(node1.originalIndices, idx)
            end

            -- Remove node2
            table.remove(colorNodes, minJ)
        else
            break -- All remaining colors are farther apart than threshold
        end
    end

    -- Create mapping from original color key -> merged target color
    local colorMap = {}
    for _, node in ipairs(colorNodes) do
        for _, origIdx in ipairs(node.originalIndices) do
            local origCol = initialPalette:getColor(origIdx)
            local key = colorToKey(origCol)
            colorMap[key] = node.color
        end
    end

    -- Wrap all image edits and palette updates into a single Undo Transaction
    app.transaction("Merge Similar Colors", function()
        local isIndexed = (sprite.colorMode == ColorMode.INDEXED)

        -- 1. Direct in-place pixel remapping for RGBA mode
        if not isIndexed then
            for _, cel in ipairs(sprite.cels) do
                local img = cel.image
                for it in img:pixels() do
                    local pixelValue = it()
                    local c = Color(pixelValue)
                    if c.alpha > 0 then
                        local key = colorToKey(c)
                        local targetColor = colorMap[key]
                        if targetColor then
                            it(app.pixelColor.rgba(targetColor.red, targetColor.green, targetColor.blue, targetColor.alpha))
                        end
                    end
                end
            end
        end

        -- 2. Update Palette
        local pal = sprite.palettes[1]
        pal:resize(#colorNodes + 1)
        pal:setColor(0, Color{ r = 0, g = 0, b = 0, a = 0 })

        for idx, node in ipairs(colorNodes) do
            pal:setColor(idx, node.color)
        end

        -- 3. Remap pixels for INDEXED mode
        if isIndexed then
            for _, cel in ipairs(sprite.cels) do
                local img = cel.image
                for it in img:pixels() do
                    local origIdx = it()
                    local origCol = initialPalette:getColor(origIdx)
                    if origCol.alpha > 0 then
                        local key = colorToKey(origCol)
                        local targetColor = colorMap[key] or origCol
                        
                        local bestIdx = 1
                        local bestD = 999.0
                        for pIdx = 1, #colorNodes do
                            local pCol = pal:getColor(pIdx)
                            local d = distFunc(targetColor, pCol)
                            if d < bestD then
                                bestD = d
                                bestIdx = pIdx
                            end
                        end
                        it(bestIdx)
                    end
                end
            end
        end
    end)

    app.refresh()
    app.alert(string.format("Success! Palette reduced from %d to %d colors.", numColors, #colorNodes))
end

-- ------------------------------------------------------------------------------
-- User Interface Dialog
-- ------------------------------------------------------------------------------

local dlg = Dialog("Merge Similar Colors")

dlg:combobox{
    id = "metric",
    label = "Distance Metric:",
    option = "RGB Distance",
    options = { "RGB Distance", "CIE Lab Color" }
}

dlg:number{
    id = "threshold",
    label = "Similarity Threshold (%):",
    text = "95.0",
    decimals = 2
}

dlg:separator()

dlg:button{
    id = "merge",
    text = "Merge",
    onclick = function()
        local data = dlg.data
        local metric = data.metric
        local threshold = tonumber(data.threshold) or 95.0

        if threshold < 0 or threshold > 100 then
            app.alert("Please enter a valid percentage threshold between 0 and 100.")
            return
        end

        dlg:close()
        mergePaletteColors(metric, threshold)
    end
}

dlg:button{
    id = "cancel",
    text = "Cancel",
    onclick = function()
        dlg:close()
    end
}

dlg:show()

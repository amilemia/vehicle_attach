local xmlFile = "attachments.xml"
local favoriteObjects = {}
local attachedObjects = {}
local selectedObject = nil
local lastClickTime = 0
local ITEMS_PER_PAGE = 50
local currentPage = 1
local cachedObjects = {}
local errorMessages = {}

-- Forward declarations
local updateObjectList
local toggleWindow

-- Preview object variables
local previewObject = nil
local isPreviewMode = false
local previewOffset = {x = 0, y = 0, z = 2}
local previewRotation = {x = 0, y = 0, z = 0}

-- Debug function
local function debugOutput(message)
    outputChatBox("Debug: " .. tostring(message), 255, 255, 0)
end

-- Load objects from objects.xml
local function loadObjectsFromXML()
    local xml = xmlLoadFile("objects.xml")
    if not xml then
        outputChatBox("Failed to load objects.xml", 255, 0, 0)
        return
    end

    local catalog = xmlFindChild(xml, "catalog", 0)
    if not catalog then
        -- handle case where <catalog> is the root node
        if xmlNodeGetName(xml) == "catalog" then
            catalog = xml
        else
            outputChatBox("Invalid objects.xml format", 255, 0, 0)
            xmlUnloadFile(xml)
            return
        end
    end

    for _, group in ipairs(xmlNodeGetChildren(catalog)) do
        for _, object in ipairs(xmlNodeGetChildren(group)) do
            local model = tonumber(xmlNodeGetAttribute(object, "model"))
            local name = xmlNodeGetAttribute(object, "name")
            if model and name then
                table.insert(cachedObjects, {model = model, name = name})
            end
        end
    end

    xmlUnloadFile(xml)
    debugOutput("Loaded " .. #cachedObjects .. " objects from objects.xml")
end

-- Cache valid objects
addEventHandler("onClientResourceStart", resourceRoot, function()
    -- Include lower IDs so XML objects display with valid names
    for i = 300, 20000 do
        local modelName = engineGetModelNameFromID(i)
        if modelName then
            -- Use the same key for the model ID as objects loaded from XML
            table.insert(cachedObjects, {model = i, name = modelName})
            debugOutput("Cached object: ID=" .. i .. ", Name=" .. modelName)
        end
    end
    debugOutput("Total cached objects: " .. #cachedObjects)
    loadObjectsFromXML()
    updateObjectList()
    bindKey("F7", "down", toggleWindow)
end)

-- Create main window
local screenW, screenH = guiGetScreenSize()
local window = guiCreateWindow(screenW/2 - 400, screenH/2 - 300, 800, 600, "Vehicle Object Attacher", false)
guiWindowSetSizable(window, false)
guiSetVisible(window, false)

-- Create tabs
local tabPanel = guiCreateTabPanel(10, 25, 780, 565, false, window)
local attachTab = guiCreateTab("Attach Objects", tabPanel)
local transformTab = guiCreateTab("Transform", tabPanel)

-- Attach tab elements
local objectList = guiCreateGridList(10, 10, 380, 400, false, attachTab)
guiGridListAddColumn(objectList, "ID", 0.2)
guiGridListAddColumn(objectList, "Name", 0.7)

local attachedList = guiCreateGridList(400, 10, 370, 400, false, attachTab)
guiGridListAddColumn(attachedList, "Attached Objects", 0.9)

-- Navigation buttons
local prevBtn = guiCreateButton(10, 420, 100, 30, "Previous", false, attachTab)
local nextBtn = guiCreateButton(120, 420, 100, 30, "Next", false, attachTab)
local pageLabel = guiCreateLabel(230, 425, 200, 20, "Page 1", false, attachTab)

-- Action buttons
local attachBtn = guiCreateButton(400, 420, 100, 30, "Attach", false, attachTab)
local removeBtn = guiCreateButton(510, 420, 100, 30, "Remove", false, attachTab)
local saveBtn = guiCreateButton(400, 460, 100, 30, "Save Setup", false, attachTab)
local loadBtn = guiCreateButton(510, 460, 100, 30, "Load Setup", false, attachTab)

-- Transform tab elements
local sliders = {}
local valueLabels = {}
local labels = {
    "X Position", "Y Position", "Z Position",
    "X Rotation", "Y Rotation", "Z Rotation",
    "Scale X", "Scale Y", "Scale Z"
}

for i, label in ipairs(labels) do
    guiCreateLabel(10, 20 + (i-1) * 50, 100, 20, label, false, transformTab)
    sliders[label] = guiCreateScrollBar(120, 20 + (i-1) * 50, 200, 20, true, false, transformTab)
    valueLabels[label] = guiCreateLabel(330, 20 + (i-1) * 50, 100, 20, "0", false, transformTab)
    guiScrollBarSetScrollPosition(sliders[label], 50)
end

-- Functions
updateObjectList = function()
    guiGridListClear(objectList)
    local startIndex = (currentPage - 1) * ITEMS_PER_PAGE + 1
    local endIndex = math.min(startIndex + ITEMS_PER_PAGE - 1, #cachedObjects)

    for i = startIndex, endIndex do
        local row = guiGridListAddRow(objectList)
        guiGridListSetItemText(objectList, row, 1, tostring(cachedObjects[i].model), false, false)
        guiGridListSetItemText(objectList, row, 2, cachedObjects[i].name, false, false)
    end

    guiSetText(pageLabel, string.format("Page %d/%d", currentPage, math.ceil(#cachedObjects / ITEMS_PER_PAGE)))
end

local function updateAttachedList()
    guiGridListClear(attachedList)
    for _, obj in ipairs(attachedObjects) do
        if isElement(obj) then
            local row = guiGridListAddRow(attachedList)
            local modelId = getElementModel(obj)
            local modelName = engineGetModelNameFromID(modelId)
            guiGridListSetItemText(attachedList, row, 1, tostring(modelName), false, false)
        end
    end
end

-- Functions for XML handling
local function saveAttachments()
    if fileExists(xmlFile) then 
        fileDelete(xmlFile) 
    end
    
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then
        outputChatBox("You must be in a vehicle to save attachments.", 255, 0, 0)
        return false
    end
    
    local xml = xmlCreateFile(xmlFile, "attachments")
    if not xml then
        outputChatBox("Failed to create save file.", 255, 0, 0)
        return false
    end
    
    for _, obj in ipairs(attachedObjects) do
        if isElement(obj) then
            local id = getElementModel(obj)
            local x, y, z, rx, ry, rz = getElementAttachedOffsets(obj)
            local sx, sy, sz = getObjectScale(obj)
            
            local node = xmlCreateChild(xml, "object")
            xmlNodeSetAttribute(node, "id", tostring(id))
            xmlNodeSetAttribute(node, "posX", tostring(x))
            xmlNodeSetAttribute(node, "posY", tostring(y))
            xmlNodeSetAttribute(node, "posZ", tostring(z))
            xmlNodeSetAttribute(node, "rotX", tostring(rx))
            xmlNodeSetAttribute(node, "rotY", tostring(ry))
            xmlNodeSetAttribute(node, "rotZ", tostring(rz))
            xmlNodeSetAttribute(node, "scaleX", tostring(sx))
            xmlNodeSetAttribute(node, "scaleY", tostring(sy))
            xmlNodeSetAttribute(node, "scaleZ", tostring(sz))
        end
    end
    
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
    outputChatBox("Attachment setup saved successfully.", 0, 255, 0)
    return true
end

local function loadAttachments()
    if not fileExists(xmlFile) then
        outputChatBox("No saved attachment setup found.", 255, 0, 0)
        return false
    end
    
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then
        outputChatBox("You must be in a vehicle to load attachments.", 255, 0, 0)
        return false
    end
    
    -- Clean up existing attachments first
    for _, obj in ipairs(attachedObjects) do
        if isElement(obj) then
            triggerServerEvent("removeAttachedObject", resourceRoot, obj)
        end
    end
    attachedObjects = {}
    selectedObject = nil
    
    local xml = xmlLoadFile(xmlFile)
    if not xml then
        outputChatBox("Failed to load save file.", 255, 0, 0)
        return false
    end
    
    local nodes = xmlNodeGetChildren(xml)
    for _, node in ipairs(nodes) do
        local id = tonumber(xmlNodeGetAttribute(node, "id"))
        if id then
            triggerServerEvent("attachObjectToVehicle", resourceRoot, veh, id)
            -- Note: The actual positioning will be handled when we receive the onObjectAttached event
        end
    end
    
    xmlUnloadFile(xml)
    outputChatBox("Attachment setup loaded successfully.", 0, 255, 0)
    return true
end

-- Add handler for newly attached objects to set their saved position
addEvent("onObjectAttached", true)
addEventHandler("onObjectAttached", resourceRoot, function(obj)
    table.insert(attachedObjects, obj)
    selectedObject = obj
    
    -- Make sure the object is visible and properly configured
    setElementDoubleSided(obj, true)
    setElementAlpha(obj, 255)
    
    -- If we have a save file and are loading attachments, set the position
    if fileExists(xmlFile) then
        local xml = xmlLoadFile(xmlFile)
        if xml then
            local nodes = xmlNodeGetChildren(xml)
            for _, node in ipairs(nodes) do
                local id = tonumber(xmlNodeGetAttribute(node, "id"))
                if id == getElementModel(obj) then
                    local x = tonumber(xmlNodeGetAttribute(node, "posX")) or 0
                    local y = tonumber(xmlNodeGetAttribute(node, "posY")) or 0
                    local z = tonumber(xmlNodeGetAttribute(node, "posZ")) or 1
                    local rx = tonumber(xmlNodeGetAttribute(node, "rotX")) or 0
                    local ry = tonumber(xmlNodeGetAttribute(node, "rotY")) or 0
                    local rz = tonumber(xmlNodeGetAttribute(node, "rotZ")) or 0
                    local sx = tonumber(xmlNodeGetAttribute(node, "scaleX")) or 1
                    local sy = tonumber(xmlNodeGetAttribute(node, "scaleY")) or 1
                    local sz = tonumber(xmlNodeGetAttribute(node, "scaleZ")) or 1
                    
                    setElementAttachedOffsets(obj, x, y, z, rx, ry, rz)
                    setObjectScale(obj, sx, sy, sz)
                    break
                end
            end
            xmlUnloadFile(xml)
        end
    else
        -- Set default position if no save file
        setElementAttachedOffsets(obj, 0, 0, 2, 0, 0, 0)
    end
    
    updateAttachedList()
end)

-- Transform handling
local function updateTransformSliders()
    if not selectedObject or not isElement(selectedObject) then return end
    
    local x, y, z, rx, ry, rz = getElementAttachedOffsets(selectedObject)
    local sx, sy, sz = getObjectScale(selectedObject)
    
    -- Convert values to slider positions (0-100)
    local function valueToSlider(value, min, max)
        return ((value - min) / (max - min)) * 100
    end
    
    guiScrollBarSetScrollPosition(sliders["X Position"], valueToSlider(x, -5, 5))
    guiScrollBarSetScrollPosition(sliders["Y Position"], valueToSlider(y, -5, 5))
    guiScrollBarSetScrollPosition(sliders["Z Position"], valueToSlider(z, -5, 5))
    guiScrollBarSetScrollPosition(sliders["X Rotation"], valueToSlider(rx, -180, 180))
    guiScrollBarSetScrollPosition(sliders["Y Rotation"], valueToSlider(ry, -180, 180))
    guiScrollBarSetScrollPosition(sliders["Z Rotation"], valueToSlider(rz, -180, 180))
    guiScrollBarSetScrollPosition(sliders["Scale X"], valueToSlider(sx, 0.1, 3))
    guiScrollBarSetScrollPosition(sliders["Scale Y"], valueToSlider(sy, 0.1, 3))
    guiScrollBarSetScrollPosition(sliders["Scale Z"], valueToSlider(sz, 0.1, 3))
end

-- Functions
local function removeAttachedObject(obj)
    if not isElement(obj) then return end
    triggerServerEvent("removeAttachedObject", resourceRoot, obj)
    local index = getAttachedObjectIndex(obj)
    if index then
        table.remove(attachedObjects, index)
    end
    if selectedObject == obj then
        selectedObject = nil
    end
    updateAttachedList()
end

-- Function to update preview object position
local function updatePreviewPosition()
    if not previewObject or not isElement(previewObject) then return end
    
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    
    local vx, vy, vz = getElementPosition(veh)
    local vrx, vry, vrz = getElementRotation(veh)
    
    -- Set position relative to vehicle
    setElementAttachedOffsets(previewObject, previewOffset.x, previewOffset.y, previewOffset.z,
                            previewRotation.x, previewRotation.y, previewRotation.z)
end

-- Function to create preview object
local function createPreviewObject(modelId)
    if previewObject and isElement(previewObject) then
        destroyElement(previewObject)
    end
    
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    
    debugOutput("Creating preview for model: " .. tostring(modelId))
    
    local x, y, z = getElementPosition(veh)
    previewObject = createObject(modelId, x, y, z + 3) -- Create above vehicle for visibility
    if not previewObject then
        debugOutput("Failed to create preview object")
        return
    end
    
    setElementCollisionsEnabled(previewObject, false)
    setElementAlpha(previewObject, 180) -- Make it semi-transparent
    setElementDoubleSided(previewObject, true) -- Make visible from all sides
    
    -- Attach preview object to vehicle
    attachElements(previewObject, veh, 0, 0, 2)
    
    -- Reset preview position and rotation
    previewOffset = {x = 0, y = 0, z = 2}
    previewRotation = {x = 0, y = 0, z = 0}
    
    isPreviewMode = true
    updatePreviewPosition()
    debugOutput("Preview object created and attached")
end

-- Function to destroy preview object
local function destroyPreviewObject()
    if previewObject and isElement(previewObject) then
        destroyElement(previewObject)
        previewObject = nil
    end
    isPreviewMode = false
end

-- Preview movement controls
local MOVEMENT_SPEED = 0.1
local ROTATION_SPEED = 5

addEventHandler("onClientRender", root, function()
    if not isPreviewMode or not previewObject or not isElement(previewObject) then return end
    
    local keys = {
        moveForward = getKeyState("num_8"),
        moveBack = getKeyState("num_2"),
        moveLeft = getKeyState("num_4"),
        moveRight = getKeyState("num_6"),
        moveUp = getKeyState("num_9"),
        moveDown = getKeyState("num_3"),
        rotateLeft = getKeyState("num_7"),
        rotateRight = getKeyState("num_1"),
        rotateUp = getKeyState("num_5"),
        rotateDown = getKeyState("num_0")
    }
    
    -- Position adjustments
    if keys.moveForward then previewOffset.y = previewOffset.y + MOVEMENT_SPEED end
    if keys.moveBack then previewOffset.y = previewOffset.y - MOVEMENT_SPEED end
    if keys.moveLeft then previewOffset.x = previewOffset.x - MOVEMENT_SPEED end
    if keys.moveRight then previewOffset.x = previewOffset.x + MOVEMENT_SPEED end
    if keys.moveUp then previewOffset.z = previewOffset.z + MOVEMENT_SPEED end
    if keys.moveDown then previewOffset.z = previewOffset.z - MOVEMENT_SPEED end
    
    -- Rotation adjustments
    if keys.rotateLeft then previewRotation.z = previewRotation.z - ROTATION_SPEED end
    if keys.rotateRight then previewRotation.z = previewRotation.z + ROTATION_SPEED end
    if keys.rotateUp then previewRotation.x = previewRotation.x - ROTATION_SPEED end
    if keys.rotateDown then previewRotation.x = previewRotation.x + ROTATION_SPEED end
    
    updatePreviewPosition()
end)

-- Event handlers
addEventHandler("onClientGUIClick", root, function()
    if source == prevBtn and currentPage > 1 then
        currentPage = currentPage - 1
        updateObjectList()
    elseif source == nextBtn and currentPage < math.ceil(#cachedObjects/ITEMS_PER_PAGE) then
        currentPage = currentPage + 1
        updateObjectList()
    elseif source == attachBtn then
        local row = guiGridListGetSelectedItem(objectList)
        if row ~= -1 then
            local modelId = tonumber(guiGridListGetItemText(objectList, row, 1))
            local veh = getPedOccupiedVehicle(localPlayer)
            if veh then
                if isPreviewMode and previewObject then
                    -- Use preview position for attachment
                    triggerServerEvent("attachObjectToVehicle", resourceRoot, veh, modelId, previewOffset, previewRotation)
                    destroyPreviewObject()
                else
                    -- Use default position if no preview
                    triggerServerEvent("attachObjectToVehicle", resourceRoot, veh, modelId)
                end
            else
                outputChatBox("You must be in a vehicle to attach objects.", 255, 0, 0)
            end
        end
    elseif source == removeBtn then
        local row = guiGridListGetSelectedItem(attachedList)
        if row ~= -1 and selectedObject and isElement(selectedObject) then
            removeAttachedObject(selectedObject)
        end
    elseif source == saveBtn then
        saveAttachments()
    elseif source == loadBtn then
        loadAttachments()
    elseif source == attachedList then
        local row = guiGridListGetSelectedItem(attachedList)
        if row ~= -1 then
            selectedObject = attachedObjects[row + 1]
            updateAttachedList()
            updateTransformSliders()
        end
    elseif source == objectList then
        local now = getTickCount()
        local row = guiGridListGetSelectedItem(objectList)
        if now - lastClickTime < 500 then -- Double click
            local modelId = tonumber(guiGridListGetItemText(objectList, row, 1))
            if modelId then
                createPreviewObject(modelId)
            end
        else -- Single click
            local modelId = tonumber(guiGridListGetItemText(objectList, row, 1))
            if modelId then
                selectedObject = nil -- Clear selected object when selecting from object list
            end
        end
        lastClickTime = getTickCount()
    end
end)

-- Transform slider handling
for _, slider in pairs(sliders) do
    addEventHandler("onClientGUIScroll", slider, function()
        if not selectedObject or not isElement(selectedObject) then return end
        
        local x, y, z, rx, ry, rz = getElementAttachedOffsets(selectedObject)
        local sx, sy, sz = getObjectScale(selectedObject)
        
        -- Convert slider position (0-100) to actual values
        local function sliderToValue(position, min, max)
            return min + (position / 100) * (max - min)
        end
        
        local pos = guiScrollBarGetScrollPosition(source)
        local value = 0
        
        if source == sliders["X Position"] then 
            value = sliderToValue(pos, -5, 5)
            x = value
        elseif source == sliders["Y Position"] then 
            value = sliderToValue(pos, -5, 5)
            y = value
        elseif source == sliders["Z Position"] then 
            value = sliderToValue(pos, -5, 5)
            z = value
        elseif source == sliders["X Rotation"] then 
            value = sliderToValue(pos, -180, 180)
            rx = value
        elseif source == sliders["Y Rotation"] then 
            value = sliderToValue(pos, -180, 180)
            ry = value
        elseif source == sliders["Z Rotation"] then 
            value = sliderToValue(pos, -180, 180)
            rz = value
        elseif source == sliders["Scale X"] then 
            value = sliderToValue(pos, 0.1, 3)
            sx = value
        elseif source == sliders["Scale Y"] then 
            value = sliderToValue(pos, 0.1, 3)
            sy = value
        elseif source == sliders["Scale Z"] then 
            value = sliderToValue(pos, 0.1, 3)
            sz = value
        end
        
        -- Update the value label for the current slider
        for name, s in pairs(sliders) do
            if s == source then
                guiSetText(valueLabels[name], string.format("%.2f", value))
                break
            end
        end
        
        setElementAttachedOffsets(selectedObject, x, y, z, rx, ry, rz)
        setObjectScale(selectedObject, sx, sy, sz)
    end)
end

-- Cleanup
addEventHandler("onClientResourceStop", resourceRoot, function()
    if fileExists(xmlFile) then
        fileDelete(xmlFile)
    end
    unbindKey("F7", "down", toggleWindow)
end)

addEvent("onAttachmentError", true)
addEventHandler("onAttachmentError", resourceRoot, function(message)
    outputChatBox(message, 255, 0, 0)
end)

toggleWindow = function()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then
        outputChatBox("You need to be in a vehicle to use this menu.", 255, 0, 0)
        return
    end

    local isVisible = guiGetVisible(window)
    guiSetVisible(window, not isVisible)
    showCursor(not isVisible)
end

function getAttachedObjectIndex(obj)
    for i, attachedObj in ipairs(attachedObjects) do
        if attachedObj == obj then
            return i
        end
    end
    return nil
end

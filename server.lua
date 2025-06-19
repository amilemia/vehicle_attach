-- Configuration
local MAX_ATTACHMENTS_PER_VEHICLE = 10
local VALID_OBJECT_IDS = {} -- Will be populated on resource start
local vehicleAttachments = {} -- Track attachments per vehicle

-- Initialize valid object IDs
addEventHandler("onResourceStart", resourceRoot, function()
    for i = 1000, 20000 do
        if engineGetModelNameFromID(i) then
            VALID_OBJECT_IDS[i] = true
        end
    end
end)

-- Cleanup function
local function cleanupVehicleAttachments(vehicle)
    if not vehicleAttachments[vehicle] then return end
    for _, obj in ipairs(vehicleAttachments[vehicle]) do
        if isElement(obj) then
            destroyElement(obj)
        end
    end
    vehicleAttachments[vehicle] = nil
end

-- Cleanup handlers
addEventHandler("onElementDestroy", root, function()
    if getElementType(source) == "vehicle" then
        cleanupVehicleAttachments(source)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    local veh = getPedOccupiedVehicle(source)
    if veh then
        cleanupVehicleAttachments(veh)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for vehicle, _ in pairs(vehicleAttachments) do
        if isElement(vehicle) then
            cleanupVehicleAttachments(vehicle)
        end
    end
end)

addEvent("attachObjectToVehicle", true)
addEventHandler("attachObjectToVehicle", resourceRoot, function(veh, modelID, offset, rotation)
    if not isElement(veh) or type(modelID) ~= "number" or not VALID_OBJECT_IDS[modelID] then
        triggerClientEvent(client, "onAttachmentError", resourceRoot, "Invalid vehicle or model ID")
        return
    end

    -- Initialize vehicle tracking
    if not vehicleAttachments[veh] then
        vehicleAttachments[veh] = {}
    end

    -- Check attachment limit
    if #vehicleAttachments[veh] >= MAX_ATTACHMENTS_PER_VEHICLE then
        triggerClientEvent(client, "onAttachmentError", resourceRoot, "Maximum attachments reached for this vehicle")
        return
    end

    -- Create and attach object with initial offset to ensure visibility
    local x, y, z = getElementPosition(veh)
    local obj = createObject(modelID, x, y, z + 3) -- Create slightly above vehicle initially
    if not obj then
        triggerClientEvent(client, "onAttachmentError", resourceRoot, "Failed to create object")
        return
    end
    
    -- Make the object non-solid and visible
    setElementCollisionsEnabled(obj, false)
    setElementDoubleSided(obj, true)
    setElementAlpha(obj, 255) -- Ensure full visibility
    
    -- Use provided offset and rotation if available, otherwise use defaults
    local offsetX = offset and offset.x or 0
    local offsetY = offset and offset.y or 0
    local offsetZ = offset and offset.z or 2
    local rotX = rotation and rotation.x or 0
    local rotY = rotation and rotation.y or 0
    local rotZ = rotation and rotation.z or 0
    
    -- Debug output on server
    outputDebugString(string.format("Attaching object %d to vehicle with offset: %.2f, %.2f, %.2f rotation: %.2f, %.2f, %.2f",
        modelID, offsetX, offsetY, offsetZ, rotX, rotY, rotZ))
    
    if attachElements(obj, veh, offsetX, offsetY, offsetZ, rotX, rotY, rotZ) then
        table.insert(vehicleAttachments[veh], obj)
        setElementDoubleSided(obj, true) -- Make object visible from all sides
        triggerClientEvent(client, "onObjectAttached", resourceRoot, obj)
    else
        destroyElement(obj)
        triggerClientEvent(client, "onAttachmentError", resourceRoot, "Failed to attach object")
    end
end)

-- Add object removal function
addEvent("removeAttachedObject", true)
addEventHandler("removeAttachedObject", resourceRoot, function(obj)
    if not isElement(obj) then return end
    
    local vehicle = getElementAttachedTo(obj)
    if vehicle and vehicleAttachments[vehicle] then
        for i, attachedObj in ipairs(vehicleAttachments[vehicle]) do
            if attachedObj == obj then
                table.remove(vehicleAttachments[vehicle], i)
                destroyElement(obj)
                break
            end
        end
    end
end)

local isFiveM = (YacaCache and YacaCache.game == "fivem") or (GetGameName() == "fivem")

local math_sin = math.sin
local math_cos = math.cos
local math_abs = math.abs
local DEG_TO_RAD = math.pi / 180.0

---@param arr table
---@return table
function YacaConvertToXYZ(arr)
    return {
        x = YacaRoundFloat(arr.x or arr[1] or 0),
        y = YacaRoundFloat(arr.y or arr[2] or 0),
        z = YacaRoundFloat(arr.z or arr[3] or 0),
    }
end

---@return table
function YacaGetCamDirection()
    local rot = GetGameplayCamRot(2)
    local rotX = rot.x * DEG_TO_RAD
    local rotZ = rot.z * DEG_TO_RAD
    local cosx = math_abs(math_cos(rotX))
    return {
        x = YacaRoundFloat(-math_sin(rotZ) * cosx),
        y = YacaRoundFloat(math_cos(rotZ) * cosx),
        z = YacaRoundFloat(math_sin(rotX)),
    }
end

---@param input string
---@return number
function YacaJoaat(input)
    input = string.lower(input)
    local hash = 0
    for i = 1, #input do
        hash = hash + string.byte(input, i)
        hash = hash + (hash << 10)
        hash = hash ~ (hash >> 6)
    end
    hash = hash + (hash << 3)
    hash = hash ~ (hash >> 11)
    hash = hash + (hash << 15)
    return hash & 0xFFFFFFFF
end

local windowBones = {
    [0] = "window_lf",
    [1] = "window_rf",
    [2] = "window_lr",
    [3] = "window_rr",
}

local doorBones = {
    [0] = "door_dside_f",
    [1] = "door_pside_f",
    [2] = "door_dside_r",
    [3] = "door_pside_r",
    [4] = "bonnet",
    [5] = "boot",
}

---@param vehicle number
---@param windowId number
---@return boolean
function YacaHasWindow(vehicle, windowId)
    local boneName = windowBones[windowId]
    if not boneName then return false end
    return GetEntityBoneIndexByName(vehicle, boneName) ~= -1
end

---@param vehicle number
---@param doorId number
---@return boolean
function YacaHasDoor(vehicle, doorId)
    local boneName = doorBones[doorId]
    if not boneName then return false end
    return GetEntityBoneIndexByName(vehicle, boneName) ~= -1
end

---@param vehicle number
---@return boolean
function YacaVehicleHasOpening(vehicle)
    local hasDoors = false
    for i = 0, 5 do
        if i ~= 4 then
            local boneName = doorBones[i]
            if boneName and GetEntityBoneIndexByName(vehicle, boneName) ~= -1 then
                hasDoors = true
                if GetVehicleDoorAngleRatio(vehicle, i) > 0 or IsVehicleDoorDamaged(vehicle, i) then
                    return true
                end
            end
        end
    end

    if not hasDoors then return true end

    if not AreAllVehicleWindowsIntact(vehicle) then
        return true
    end

    for i = 0, 3 do
        local boneName = windowBones[i]
        if boneName and GetEntityBoneIndexByName(vehicle, boneName) ~= -1 and not IsVehicleWindowIntact(vehicle, i) then
            return true
        end
    end

    if IsVehicleAConvertible(vehicle, false) and GetConvertibleRoofState(vehicle) ~= 0 then
        return true
    end

    return false
end

YacaOutsideRoomPair = { interiorKey = 0, roomKey = 0 }

---@param value number
---@return number
function YacaToUInt32(value)
    return value & 0xFFFFFFFF
end

---@param entity number
---@return table
function YacaGetInteriorRoomPair(entity)
    local ok, pair = pcall(function()
        local interior = GetInteriorFromEntity(entity)
        if not interior or interior == 0 then
            return YacaOutsideRoomPair
        end

        local _, interiorNameHash = GetInteriorLocationAndNamehash(interior)
        local interiorKey = YacaToUInt32(interiorNameHash or 0)
        local roomKey = YacaToUInt32(GetRoomKeyFromEntity(entity) or 0)

        if interiorKey == 0 or roomKey == 0 then
            return YacaOutsideRoomPair
        end

        return { interiorKey = interiorKey, roomKey = roomKey }
    end)

    if not ok or not pair then
        return YacaOutsideRoomPair
    end
    return pair
end

---@param animDict string
---@param timeout number|nil
---@return boolean
function YacaRequestAnimDict(animDict, timeout)
    if HasAnimDictLoaded(animDict) then return true end
    if not DoesAnimDictExist(animDict) then
        print(("[YaCA] Invalid animDict: %s"):format(animDict))
        return false
    end

    RequestAnimDict(animDict)
    local timer = timeout or 30000
    local elapsed = 0
    while not HasAnimDictLoaded(animDict) and elapsed < timer do
        Citizen.Wait(10)
        elapsed = elapsed + 10
    end

    return HasAnimDictLoaded(animDict)
end

---@param modelName string|number
---@param timeout number|nil
---@return number|nil
function YacaRequestModel(modelName, timeout)
    local modelHash = modelName
    if type(modelName) == "string" then
        modelHash = YacaJoaat(modelName)
    end

    if HasModelLoaded(modelHash) then return modelHash end
    if not IsModelValid(modelHash) then
        print(("[YaCA] Invalid model: %s"):format(tostring(modelName)))
        return nil
    end

    RequestModel(modelHash)
    local timer = timeout or 30000
    local elapsed = 0
    while not HasModelLoaded(modelHash) and elapsed < timer do
        Citizen.Wait(10)
        elapsed = elapsed + 10
    end

    if HasModelLoaded(modelHash) then
        return modelHash
    end
    return nil
end

---@param targetPed number
---@param model string|number
---@param boneId number
---@param offset table|nil
---@param rotation table|nil
---@param networked boolean|nil
---@return number|nil
function YacaCreateProp(targetPed, model, boneId, offset, rotation, networked)
    if networked == nil then networked = true end
    offset = offset or { 0.0, 0.0, 0.0 }
    rotation = rotation or { 0.0, 0.0, 0.0 }

    if not targetPed or not DoesEntityExist(targetPed) then
        return nil
    end

    local modelHash = YacaRequestModel(model)
    if not modelHash then return nil end

    local coords = GetEntityCoords(targetPed, true)
    local obj = CreateObject(modelHash, coords.x, coords.y, coords.z, networked == true, true, false)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(
        obj, targetPed,
        GetPedBoneIndex(targetPed, boneId),
        offset[1] or offset.x or 0.0,
        offset[2] or offset.y or 0.0,
        offset[3] or offset.z or 0.0,
        rotation[1] or rotation.x or 0.0,
        rotation[2] or rotation.y or 0.0,
        rotation[3] or rotation.z or 0.0,
        true, false, false, true, 2, true
    )

    SetModelAsNoLongerNeeded(modelHash)
    return obj
end

YacaRedmKeyToHash = {
    A = 0x7065027d, B = 0x4cc0e2fe, C = 0x9959a6f0, D = 0xb4e465b4,
    E = 0xcefd9220, F = 0xb2f377e8, G = 0x760a9c6f, H = 0x24978a28,
    I = 0xc1989f95, J = 0xf3830d8e, L = 0x80f28e95, M = 0xe31c6a41,
    N = 0x4bc9dabb, O = 0xf1301666, P = 0xd82e0bd2, Q = 0xde794e3e,
    R = 0xe30cd707, S = 0xd27782e3, U = 0xd8f73058, V = 0x7f8d09b8,
    W = 0x8fd015d8, X = 0x8cc9cd42, Z = 0x26e9dc00,
    RIGHTBRACKET = 0xa5bdcd3c, LEFTBRACKET = 0x430593aa,
    MOUSE1 = 0x07ce1e61, MOUSE2 = 0xf84fa74f, MOUSE3 = 0xcee12b50, MWUP = 0x3076e97c,
    CTRL = 0xdb096b85, LCONTROL = 0xdb096b85, TAB = 0xb238fe0b, SHIFT = 0x8ffc75d6,
    SPACEBAR = 0xd9d0e1c0, ENTER = 0xc7b5340a, BACKSPACE = 0x156f7119,
    LALT = 0x8aaa0ad4, DEL = 0x4af4d473, PGUP = 0x446258b6, PGDN = 0x3c3dd371,
    F1 = 0xa8e3f467, F4 = 0x1f6d95e5, F6 = 0x3c0a40f2,
    ["1"] = 0xe6f612e4, ["2"] = 0x1ce6d9eb, ["3"] = 0x4f49cc4c, ["4"] = 0x8f9f9e58,
    ["5"] = 0xab62e997, ["6"] = 0xa1fde2a6, ["7"] = 0xb03a913b, ["8"] = 0x42385422,
    DOWN = 0x05ca7c52, UP = 0x6319db71, LEFT = 0xa65ebab4, RIGHT = 0xdeb34313,
}

---@param key string
---@param onPressed function|nil
---@param onReleased function|nil
function YacaRegisterRdrKeyBind(key, onPressed, onReleased)
    if not key or key == false then return end

    local keyHash = YacaRedmKeyToHash[string.upper(tostring(key))]
    if not keyHash then
        print(("[YaCA] No key hash available for %s, please choose another keybind"):format(tostring(key)))
        return
    end

    Citizen.CreateThread(function()
        while true do
            DisableControlAction(0, keyHash, true)
            if onPressed and IsDisabledControlJustPressed(0, keyHash) then
                onPressed()
            end
            if onReleased and IsDisabledControlJustReleased(0, keyHash) then
                onReleased()
            end
            Citizen.Wait(0)
        end
    end)
end

---@param ped number
---@param animName string
---@param animDict string
function YacaPlayRdrFacialAnim(ped, animName, animDict)
    if not YacaRequestAnimDict(animDict, 1500) then return end
    SetFacialIdleAnimOverride(ped, animName, animDict)
end

---@param text string
---@param duration number|nil
function YacaDisplayRdrNotification(text, duration)
    duration = duration or 2000
    local ok = pcall(function()
        local str = VarString(10, "LITERAL_STRING", text)
        Citizen.InvokeNative(0x202709F4C58A0424, str)
        Citizen.InvokeNative(0x2A4765812202E671)
    end)
    if not ok then
        print(("[YaCA] %s"):format(text))
    end
end

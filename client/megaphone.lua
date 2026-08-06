YacaMegaphone = {
    canUseMegaphone = false,
    lastMegaphoneState = false,
    megaphoneVehicleWhitelistHashes = {},
}

local function initMegaphoneModule()
    YacaMegaphone:registerEvents()
    YacaMegaphone:registerExports()
    YacaMegaphone:registerStateBagHandlers()

    if YacaClient.isFiveM then
        YacaMegaphone:registerKeybinds()

        if YacaClient.sharedConfig.megaphone.allowedVehicleModels then
            for _, vehicleModel in ipairs(YacaClient.sharedConfig.megaphone.allowedVehicleModels) do
                YacaMegaphone.megaphoneVehicleWhitelistHashes[YacaJoaat(vehicleModel)] = true
            end
        end
    elseif YacaClient.isRedM then
        YacaMegaphone:registerRdrKeybinds()
        YacaMegaphone.canUseMegaphone = true
    end
end

function YacaMegaphone:registerEvents()
    RegisterNetEvent("client:yaca:setLastMegaphoneState", function(state)
        self.lastMegaphoneState = state
    end)

    if YacaClient.isFiveM and YacaClient.sharedConfig.megaphone.automaticVehicleDetection then
        local lastVehicle = false
        local lastSeat = false

        Citizen.CreateThread(function()
            while true do
                local currentVehicle = YacaCache.vehicle
                local currentSeat = YacaCache.seat

                if currentVehicle ~= lastVehicle or currentSeat ~= lastSeat then
                    lastVehicle = currentVehicle
                    lastSeat = currentSeat

                    if currentSeat == false or currentSeat > 0 or not currentVehicle then
                        self.canUseMegaphone = false
                        TriggerServerEvent("server:yaca:playerLeftVehicle")
                    else
                        local vehicleClass = GetVehicleClass(currentVehicle)
                        local vehicleModel = GetEntityModel(currentVehicle)

                        local allowedClasses = YacaClient.sharedConfig.megaphone.allowedVehicleClasses or {}
                        local classAllowed = false
                        for _, cls in ipairs(allowedClasses) do
                            if cls == vehicleClass then
                                classAllowed = true
                                break
                            end
                        end

                        self.canUseMegaphone = classAllowed or self.megaphoneVehicleWhitelistHashes[vehicleModel] == true
                    end
                end

                Citizen.Wait(500)
            end
        end)
    end
end

function YacaMegaphone:registerKeybinds()
    if YacaClient.sharedConfig.keyBinds.megaphone == false then return end

    RegisterCommand("+yaca:megaphone", function()
        self:useMegaphone(true)
    end, false)
    RegisterCommand("-yaca:megaphone", function()
        self:useMegaphone(false)
    end, false)
    RegisterKeyMapping("+yaca:megaphone", YacaLocale("use_megaphone"), "keyboard", YacaClient.sharedConfig.keyBinds.megaphone)
end

function YacaMegaphone:registerRdrKeybinds()
    if YacaClient.sharedConfig.keyBinds.megaphone == false then return end

    YacaRegisterRdrKeyBind(YacaClient.sharedConfig.keyBinds.megaphone, function()
        self:useMegaphone(not self.lastMegaphoneState)
    end)
end

function YacaMegaphone:registerExports()
    exports("getCanUseMegaphone", function()
        return self.canUseMegaphone
    end)

    exports("setCanUseMegaphone", function(state)
        self.canUseMegaphone = state
        if not state and self.lastMegaphoneState then
            TriggerServerEvent("server:yaca:playerLeftVehicle")
        end
    end)

    exports("useMegaphone", function(state)
        self:useMegaphone(state or false)
    end)
end

function YacaMegaphone:registerStateBagHandlers()
    AddStateBagChangeHandler(YACA_STATE_MEGAPHONE, "", function(bagName, _, value, _, replicated)
        if replicated then return end

        local playerId = GetPlayerFromStateBagName(bagName)
        if playerId == 0 then return end

        local playerSource = GetPlayerServerId(playerId)
        if playerSource == 0 then return end

        if playerSource == YacaCache.serverId then
            YacaClient:setPlayersCommType(
                {}, YacaFilterEnum.MEGAPHONE,
                type(value) == "number", nil, value,
                CommDeviceMode.SENDER, CommDeviceMode.RECEIVER
            )
        else
            local player = YacaClient:getPlayerByID(playerSource)
            if not player then return end

            YacaClient:setPlayersCommType(
                player, YacaFilterEnum.MEGAPHONE,
                type(value) == "number", nil, value,
                CommDeviceMode.RECEIVER, CommDeviceMode.SENDER
            )
        end
    end)
end

function YacaMegaphone:useMegaphone(state)
    state = state or false

    if YacaClient.isFiveM then
        if (not YacaCache.vehicle and YacaClient.sharedConfig.megaphone.automaticVehicleDetection)
            or not self.canUseMegaphone
            or state == self.lastMegaphoneState then
            return
        end
    else
        if not self.canUseMegaphone or state == self.lastMegaphoneState then
            return
        end
    end

    self.lastMegaphoneState = not self.lastMegaphoneState
    TriggerServerEvent("server:yaca:useMegaphone", state)
    TriggerEvent("yaca:external:megaphoneState", state)
end

Citizen.CreateThread(function()
    while not YacaClient.sharedConfig do
        Citizen.Wait(100)
    end
    initMegaphoneModule()
end)

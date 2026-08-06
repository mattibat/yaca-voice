YacaClient = {
    sharedConfig = nil,
    towerConfig = nil,

    mufflingVehicleWhitelistHash = {},
    whitelistedRoomIds = {},
    allPlayers = {},
    firstConnect = true,

    canChangeVoiceRange = true,
    defaultVoiceRange = 1,
    maxVoiceRange = -1,
    rangeIndex = 1,
    rangeIntervalToken = 0,
    visualVoiceRangeTimeout = nil,
    visualVoiceRangeTick = nil,
    voiceRangeViaMouseWheelTick = nil,

    isTalking = false,
    useWhisper = false,
    spectatingPlayer = false,
    notificationTimeout = {},

    isMicrophoneMuted = false,
    isMicrophoneDisabled = false,
    isSoundMuted = false,
    isSoundDisabled = false,

    currentlyPhoneSpeakerApplied = {},
    currentlySendingPhoneSpeakerSender = {},
    phoneHearNearbyPlayer = {},
    currentlyAirborneApplied = {},

    disabledFilters = {},
    teamSpeakUniqueIdentifier = nil,

    isFiveM = (GetGameName() == "fivem"),
    isRedM = (GetGameName() == "redm"),

    currentPluginState = nil,
    nuiConnectRetryActive = false,
}

local function startVoiceJoinRetryLoop()
    if not YacaClient.sharedConfig or not YacaClient.sharedConfig.autoConnectOnJoin then return end

    TriggerServerEvent("server:yaca:nuiReady")

    if YacaClient.nuiConnectRetryActive then return end
    YacaClient.nuiConnectRetryActive = true

    Citizen.CreateThread(function()
        local attempts = 0

        while YacaClient.nuiConnectRetryActive do
            if YacaClient:isPluginInitialized(true) then
                break
            end

            TriggerServerEvent("server:yaca:nuiReady")
            attempts = attempts + 1

            if attempts < 10 then
                Citizen.Wait(3000)
            elseif attempts < 25 then
                Citizen.Wait(5000)
            else
                Citizen.Wait(10000)
            end
        end

        YacaClient.nuiConnectRetryActive = false
    end)
end

local function initializeClient()
    YacaClient.sharedConfig = YacaSharedConfig
    YacaClient.towerConfig = YacaTowerConfig or { towerPositions = {} }
    YacaInitLocale(YacaClient.sharedConfig.locale)

    YacaClient.rangeIndex = YacaClient.sharedConfig.voiceRange.defaultIndex
    if YacaClient.sharedConfig.voiceRange.ranges[YacaClient.rangeIndex] then
        YacaClient.defaultVoiceRange = YacaClient.sharedConfig.voiceRange.ranges[YacaClient.rangeIndex]
    else
        YacaClient.defaultVoiceRange = 1
        YacaClient.rangeIndex = 1
        YacaClient.sharedConfig.voiceRange.ranges = { 1 }
        print("[YaCA] Default voice range is not set correctly in the config.")
    end

    if YacaClient.isFiveM then
        for _, vehicleModel in ipairs(YacaClient.sharedConfig.mufflingSettings.vehicleMuffling.vehicleWhitelist) do
            YacaClient.mufflingVehicleWhitelistHash[YacaJoaat(vehicleModel)] = true
        end
    end

    local whitelistRooms = YacaClient.sharedConfig.mufflingSettings.whitelistedRoomIds or {}
    for _, roomId in ipairs(whitelistRooms) do
        YacaClient.whitelistedRoomIds[roomId] = true
    end

    YacaClient.disabledFilters = YacaClient:parseDisabledFilters(YacaClient.sharedConfig.disabledFilters)

    YacaClient:setCurrentPluginState(YacaPluginStates.NOT_CONNECTED)

    RegisterNUICallback("YACA_OnNuiReady", function(_, cb)
        YacaWebSocket.nuiReady = true

        if YacaClient.sharedConfig.autoConnectOnJoin then
            startVoiceJoinRetryLoop()
        end

        cb({})
    end)

    YacaClient:registerExports()
    YacaClient:registerEvents()
    YacaClient:registerStateBagCaches()
    if YacaClient.isFiveM then
        YacaClient:registerKeybindings()
    elseif YacaClient.isRedM then
        YacaClient:registerRdrKeybindings()
    end

    if not YacaClient.sharedConfig.useLocalLipSync then
        AddStateBagChangeHandler(YACA_STATE_LIP_SYNC, "", function(bagName, _, value, _)
            local playerId = GetPlayerFromStateBagName(bagName)
            if playerId == 0 then return end

            SetPlayerTalkingOverride(playerId, value)

            local player = YacaClient:getPlayerByID(GetPlayerServerId(playerId))
            if player then
                player.isTalking = value
            end
        end)

        AddStateBagChangeHandler(YACA_STATE_GLOBAL_ERROR_LEVEL, "", function(_, _, _, _)
            SetTimeout(0, function()
                if YacaPhone and YacaPhone.inCallWith then
                    local callMembers = {}
                    for id in pairs(YacaPhone.inCallWith) do
                        callMembers[#callMembers + 1] = id
                    end
                    YacaPhone:enablePhoneCall(callMembers, true)
                end
            end)
        end)
    end

    if YacaClient.sharedConfig.saltyChatBridge then
        if YacaRadio then
            YacaRadio.secondaryRadioChannel = 2
        end
        YacaSaltyChatBridge:init()
    end

    print("[Client] YaCA Client loaded.")
end

function YacaClient:setCurrentPluginState(state)
    if self.currentPluginState == state then return end
    self.currentPluginState = state
    TriggerEvent("yaca:external:pluginStateChanged", state)

    if YacaClient.sharedConfig.saltyChatBridge and YacaSaltyChatBridge then
        YacaSaltyChatBridge:handleChangePluginState(state)
    end
end

function YacaClient:notification(message, notifType)
    if self.sharedConfig.notifications.oxLib then
        TriggerEvent("ox_lib:notify", {
            id = "yaca",
            title = "YaCA",
            description = message,
            type = notifType,
        })
    end

    if self.sharedConfig.notifications.okoknotify and GetResourceState("okokNotify") == "started" then
        local okType = notifType == YacaNotificationType.INFO and "info" or notifType
        exports.okokNotify:Alert("YaCA", message, 2000, okType)
    end

    if self.sharedConfig.notifications.gta then
        if self.isFiveM then
            BeginTextCommandThefeedPost("STRING")
            AddTextComponentSubstringPlayerName("YaCA: " .. message)
            if notifType == YacaNotificationType.ERROR then
                ThefeedSetNextPostBackgroundColor(6)
            end
            EndTextCommandThefeedPostTicker(false, false)
        else
            print("[YaCA] GTA notification is only available in FiveM.")
        end
    end

    if self.sharedConfig.notifications.redm then
        if self.isRedM then
            YacaDisplayRdrNotification("YaCA: " .. message, 2000)
        else
            print("[YaCA] RedM notification is only available in RedM.")
        end
    end

    if self.sharedConfig.notifications.own then
        TriggerEvent("yaca:external:notification", message, notifType)
    end
end

function YacaClient:getPlayerByID(remoteId)
    return self.allPlayers[remoteId]
end

function YacaClient:getPlayerByClientId(clientId)
    for _, player in pairs(self.allPlayers) do
        if player.clientId == clientId then
            return player
        end
    end
    return nil
end

function YacaClient:setPlayerVariable(playerId, variable, value)
    local currentData = self:getPlayerByID(playerId)
    if not currentData then return end
    currentData[variable] = value
end

function YacaClient:getVoiceRange(serverId)
    if serverId ~= nil then
        local playerState = Player(serverId).state
        return playerState[YACA_STATE_VOICE_RANGE] or self.defaultVoiceRange
    end
    return LocalPlayer.state[YACA_STATE_VOICE_RANGE] or self.defaultVoiceRange
end

function YacaClient:changeVoiceRange(increase)
    if increase == nil then increase = true end
    if not self.canChangeVoiceRange then return end

    local currentVoiceRange = self:getVoiceRange()
    local ranges = self.sharedConfig.voiceRange.ranges

    if increase then
        local newIndex = nil
        for i, range in ipairs(ranges) do
            if ((self.maxVoiceRange ~= -1 and range <= self.maxVoiceRange) or self.maxVoiceRange == -1) and range > currentVoiceRange then
                newIndex = i
                break
            end
        end
        self.rangeIndex = newIndex or 1
    else
        local newIndex = nil
        for i = #ranges, 1, -1 do
            if ranges[i] < currentVoiceRange then
                newIndex = i
                break
            end
        end
        self.rangeIndex = newIndex or #ranges

        if self.maxVoiceRange ~= -1 and ranges[self.rangeIndex] > self.maxVoiceRange then
            for i = #ranges, 1, -1 do
                if ranges[i] <= self.maxVoiceRange then
                    self.rangeIndex = i
                    break
                end
            end
        end
    end

    local voiceRange = ranges[self.rangeIndex] or 1
    self:changeVoiceRangeInternal(voiceRange)
end

function YacaClient:setVoiceRange(voiceRange)
    self.rangeIndex = -1
    self:changeVoiceRangeInternal(voiceRange)
end

function YacaClient:changeVoiceRangeInternal(voiceRange)
    if not self.canChangeVoiceRange then return end
    if self.maxVoiceRange ~= -1 and voiceRange > self.maxVoiceRange then return end

    self:showRangeVisual(voiceRange)
    LocalPlayer.state:set(YACA_STATE_VOICE_RANGE, voiceRange, true)

    TriggerEvent("yaca:external:voiceRangeUpdate", voiceRange, self.rangeIndex)

    if self.sharedConfig.saltyChatBridge then
        TriggerEvent("SaltyChat_VoiceRangeChanged", string.format("%.1f", voiceRange), self.rangeIndex, #self.sharedConfig.voiceRange.ranges)
    end
end

function YacaClient:showRangeVisual(newVoiceRange)
    if self.visualVoiceRangeTimeout then
        ClearTimeout(self.visualVoiceRangeTimeout)
        self.visualVoiceRangeTimeout = nil
    end

    if self.visualVoiceRangeTick then
        ClearTimeout(self.visualVoiceRangeTick)
        self.visualVoiceRangeTick = nil
    end

    if self.sharedConfig.voiceRange.sendNotification then
        self:notification(YacaLocale("voice_range_changed", newVoiceRange), YacaNotificationType.INFO)
    end

    if self.sharedConfig.voiceRange.markerColor.enabled then
        local mc = self.sharedConfig.voiceRange.markerColor
        local markerActive = true

        self.visualVoiceRangeTimeout = SetTimeout(mc.duration, function()
            markerActive = false
            self.visualVoiceRangeTimeout = nil
        end)

        Citizen.CreateThread(function()
            while markerActive do
                local entity = YacaCache.vehicle or YacaCache.ped
                local pos = GetEntityCoords(entity, false)
                local posZ = (YacaCache.vehicle and pos.z - 0.6 or pos.z - 0.98) + (mc.zOffset or 0)

                DrawMarker(
                    mc.type,
                    pos.x, pos.y, posZ,
                    0, 0, 0,
                    0, 0, 0,
                    newVoiceRange * 2, newVoiceRange * 2, 1,
                    mc.r, mc.g, mc.b, mc.a,
                    false, true, 2,
                    mc.rotate,
                    nil, nil, false
                )
                Citizen.Wait(0)
            end
        end)
    end
end

function YacaClient:handleVoiceRangeViaMouseWheel()
    if self.isFiveM then
        HudWeaponWheelIgnoreSelection()
    end

    local newValue = 0
    local currentVoiceRange = self:getVoiceRange()

    if IsControlPressed(0, 242) then
        newValue = math.max(1, currentVoiceRange - 1)
    elseif IsControlPressed(0, 241) then
        local maxRange = self.sharedConfig.voiceRange.ranges[#self.sharedConfig.voiceRange.ranges]
        newValue = math.min(maxRange, currentVoiceRange + 1)
        if self.maxVoiceRange ~= -1 and newValue > self.maxVoiceRange then
            newValue = self.maxVoiceRange
        end
    end

    if newValue <= 0 or currentVoiceRange == newValue then return end
    self:setVoiceRange(newValue)
end

function YacaClient:isCommTypeValid(commType)
    if YacaFilterEnum[commType] ~= nil then return true end
    for _, v in pairs(YacaFilterEnum) do
        if v == commType then return true end
    end
    print(("[YaCA-Websocket]: Invalid comm type: %s"):format(tostring(commType)))
    return false
end

function YacaClient:setPlayersCommType(players, commType, state, channel, range, ownMode, otherPlayersMode, errorLevel)
    if type(players) ~= "table" or players.clientId then
        players = { players }
    end

    local clientIds = {}
    if ownMode ~= nil then
        local localPlayer = self:getPlayerByID(YacaCache.serverId)
        if localPlayer then
            clientIds[#clientIds + 1] = {
                client_id = localPlayer.clientId,
                mode = ownMode,
            }
        end
    end

    for _, player in ipairs(players) do
        if player then
            local clientProtocol = {
                client_id = player.clientId,
                mode = otherPlayersMode,
            }
            if errorLevel ~= nil then
                clientProtocol.errorLevel = errorLevel
            end
            clientIds[#clientIds + 1] = clientProtocol
        end
    end

    local protocol = {
        on = state,
        comm_type = commType,
        members = clientIds,
    }

    if channel ~= nil then protocol.channel = channel end
    if range ~= nil then protocol.range = range end

    self:sendWebsocket({
        base = { request_type = "INGAME" },
        comm_device = protocol,
    })
end

function YacaClient:setCommDeviceVolume(commType, volume, channel)
    if not self:isCommTypeValid(commType) then return end

    local protocol = {
        comm_type = commType,
        volume = YacaClamp(volume, 0, 1),
    }
    if channel ~= nil then protocol.channel = channel end

    self:sendWebsocket({
        base = { request_type = "INGAME" },
        comm_device_settings = protocol,
    })
end

function YacaClient:setCommDeviceStereoMode(commType, mode, channel)
    if not self:isCommTypeValid(commType) then return end

    local protocol = {
        comm_type = commType,
        output_mode = mode,
    }
    if channel ~= nil then protocol.channel = channel end

    self:sendWebsocket({
        base = { request_type = "INGAME" },
        comm_device_settings = protocol,
    })
end

function YacaClient:sendWebsocket(msg)
    YacaWebSocket:send(msg)
end

function YacaClient:parseDisabledFilters(filters)
    local parsed = {}
    if type(filters) ~= "table" then return parsed end

    local known = {}
    for _, value in pairs(YacaFilterEnum) do known[value] = true end
    for _, value in pairs(YacaEffectFilterEnum) do known[value] = true end

    for _, filter in ipairs(filters) do
        if known[filter] then
            parsed[#parsed + 1] = filter
        else
            print(("[YaCA] Unknown filter '%s' in disabledFilters, it will be ignored."):format(tostring(filter)))
        end
    end

    return parsed
end

function YacaClient:registerStateBagCaches()
    AddStateBagChangeHandler(YACA_STATE_VOICE_RANGE, "", function(bagName, _, value, _)
        local playerId = GetPlayerFromStateBagName(bagName)
        if playerId == 0 then return end
        local serverId = GetPlayerServerId(playerId)
        local player = self:getPlayerByID(serverId)
        if player then
            player.cachedVoiceRange = value
        end
    end)

    AddStateBagChangeHandler(YACA_STATE_MEGAPHONE, "", function(bagName, _, value, _)
        local playerId = GetPlayerFromStateBagName(bagName)
        if playerId == 0 then return end
        local serverId = GetPlayerServerId(playerId)
        local player = self:getPlayerByID(serverId)
        if player then
            player.cachedUsesMegaphone = value ~= nil
        end
    end)
end

function YacaClient:initRequest(dataObj)
    if not dataObj or not dataObj.suid or type(dataObj.chid) ~= "number"
       or not dataObj.deChid or not dataObj.ingameName
       or dataObj.channelPassword == nil then
        print("[YACA-Websocket]: Error while initializing plugin")
        self:notification(YacaLocale("connect_error"), YacaNotificationType.ERROR)
        return
    end

    self:sendWebsocket({
        base = { request_type = "INIT" },
        server_guid = dataObj.suid,
        ingame_name = dataObj.ingameName,
        ingame_channel = dataObj.chid,
        default_channel = dataObj.deChid,
        ingame_channel_password = dataObj.channelPassword,
        excluded_channels = dataObj.excludeChannels,
        muffling_range = self.sharedConfig.mufflingSettings.mufflingRange,
        build_type = self.sharedConfig.buildType,
        unmute_delay = self.sharedConfig.unmuteDelay,
        operation_mode = dataObj.useWhisper and 1 or 0,
        disabled_filters = self.disabledFilters,
    })

    self.useWhisper = dataObj.useWhisper or false
end

function YacaClient:isPluginInitialized(silent)
    local initialized = self:getPlayerByID(YacaCache.serverId) ~= nil
    if not initialized and not silent then
        self:notification(YacaLocale("plugin_not_initialized"), YacaNotificationType.ERROR)
    end
    return initialized
end

function YacaClient:handleResponse(payload)
    if not payload then return end

    local parsedPayload
    if type(payload) == "string" then
        local ok, result = pcall(json.decode, payload)
        if not ok then
            print("[YaCA-Websocket]: Error while parsing message: " .. tostring(result))
            return
        end
        parsedPayload = result
    else
        parsedPayload = payload
    end

    if not parsedPayload or not parsedPayload.code then return end

    local code = parsedPayload.code

    if code == "OK" then
        if parsedPayload.requestType == "JOIN" then
            local clientId = tonumber(parsedPayload.message)
            self.teamSpeakUniqueIdentifier = parsedPayload.additionalMessage or nil
            TriggerServerEvent("server:yaca:addPlayer", clientId, self.teamSpeakUniqueIdentifier)

            self.nuiConnectRetryActive = false

            self.rangeIntervalToken = (self.rangeIntervalToken or 0) + 1
            local token = self.rangeIntervalToken
            Citizen.CreateThread(function()
                while self.rangeIntervalToken == token do
                    self:calcPlayers()
                    Citizen.Wait(250)
                end
            end)

            if YacaRadio and YacaRadio.radioInitialized then
                YacaRadio:initRadioSettings()
            end

            TriggerEvent("yaca:external:pluginInitialized", clientId, self.teamSpeakUniqueIdentifier)
        end
        return

    elseif code == "TALK_STATE" then
        self:handleTalkState(parsedPayload)
        return

    elseif code == "SOUND_STATE" then
        self:handleSoundState(parsedPayload)
        return

    elseif code == "OTHER_TALK_STATE" then
        self:handleOtherTalkState(parsedPayload)
        return

    elseif code == "MOVED_CHANNEL" then
        self:handleMovedChannel(parsedPayload.message)
        return

    elseif code == "WRONG_TS_SERVER" then
        self:setCurrentPluginState(YacaPluginStates.WRONG_TS_SERVER)
        local currentTimeout = self.notificationTimeout["WRONG_TS_SERVER"]
        if currentTimeout and currentTimeout > GetGameTimer() then return end
        self.notificationTimeout["WRONG_TS_SERVER"] = GetGameTimer() + 10000
        self:notification(YacaLocale("wrong_ts_server"), YacaNotificationType.ERROR)
        return

    elseif code == "OUTDATED_VERSION" then
        self:setCurrentPluginState(YacaPluginStates.OUTDATED_VERSION)
        self:notification(YacaLocale("outdated_plugin", parsedPayload.message), YacaNotificationType.ERROR)
        return

    elseif code == "MAX_PLAYER_COUNT_REACHED" then
        self:notification(YacaLocale("max_players_reached"), YacaNotificationType.ERROR)
        return

    elseif code == "LICENSE_SERVER_TIMED_OUT" then
        self:notification(YacaLocale("license_server_timed_out"), YacaNotificationType.ERROR)
        return

    elseif code == "MOVE_ERROR" then
        self:notification(YacaLocale("move_error"), YacaNotificationType.ERROR)
        return

    elseif code == "WAIT_GAME_INIT" or code == "HEARTBEAT" or code == "MUTE_STATE" then
        return

    else
        print(("[YaCA-Websocket]: Unknown error code: %s"):format(tostring(code)))
        self:notification(YacaLocale("unknown_error", tostring(code)), YacaNotificationType.ERROR)
        return
    end
end

function YacaClient:syncLipsPlayer(ped, playerId, talking)
    SetPlayerTalkingOverride(playerId, talking)
    if self.isFiveM then
        if talking then
            PlayFacialAnim(ped, "mic_chatter", "mp_facial")
        else
            PlayFacialAnim(ped, "mood_normal_1", "facials@gen_male@variations@normal")
        end
    elseif self.isRedM then
        if talking then
            YacaPlayRdrFacialAnim(ped, "mood_talking_normal", "face_human@gen_male@base")
        else
            YacaPlayRdrFacialAnim(ped, "mood_normal", "face_human@gen_male@base")
        end
    end
end

function YacaClient:handleTalkState(payload)
    local messageState = payload.message == "1"
    local isPlayerMuted = self.isMicrophoneMuted or self.isMicrophoneDisabled or self.isSoundMuted or self.isSoundDisabled

    local talking = not isPlayerMuted and messageState
    if self.isTalking ~= talking then
        self.isTalking = talking

        self:syncLipsPlayer(YacaCache.ped, YacaCache.serverId, talking)
        LocalPlayer.state:set(YACA_STATE_LIP_SYNC, talking, true)

        TriggerEvent("yaca:external:isTalking", talking)

        if self.sharedConfig.saltyChatBridge then
            TriggerEvent("SaltyChat_TalkStateChanged", talking)
        end
    end
end

function YacaClient:handleSoundState(payload)
    local soundStates
    if type(payload.message) == "string" then
        soundStates = json.decode(payload.message)
    else
        soundStates = payload.message
    end
    if not soundStates then return end

    if self.isMicrophoneMuted ~= soundStates.microphoneMuted then
        self.isMicrophoneMuted = soundStates.microphoneMuted
        TriggerEvent("yaca:external:microphoneMuteStateChanged", soundStates.microphoneMuted)
        TriggerEvent("yaca:external:muteStateChanged", soundStates.microphoneMuted)
        if self.sharedConfig.saltyChatBridge then
            TriggerEvent("SaltyChat_MicStateChanged", soundStates.microphoneMuted)
        end
    end

    if self.isMicrophoneDisabled ~= soundStates.microphoneDisabled then
        self.isMicrophoneDisabled = soundStates.microphoneDisabled
        TriggerEvent("yaca:external:microphoneDisabledStateChanged", soundStates.microphoneDisabled)
        if self.sharedConfig.saltyChatBridge then
            TriggerEvent("SaltyChat_MicEnabledChanged", soundStates.microphoneDisabled)
        end
    end

    if self.isSoundMuted ~= soundStates.soundMuted then
        self.isSoundMuted = soundStates.soundMuted
        TriggerEvent("yaca:external:soundMuteStateChanged", soundStates.soundMuted)
        if self.sharedConfig.saltyChatBridge then
            TriggerEvent("SaltyChat_SoundStateChanged", soundStates.soundMuted)
        end
    end

    if self.isSoundDisabled ~= soundStates.soundDisabled then
        self.isSoundDisabled = soundStates.soundDisabled
        TriggerEvent("yaca:external:soundDisabledStateChanged", soundStates.soundDisabled)
        if self.sharedConfig.saltyChatBridge then
            TriggerEvent("SaltyChat_SoundEnabledChanged", soundStates.soundDisabled)
        end
    end
end

function YacaClient:handleOtherTalkState(payload)
    if not self.sharedConfig.useLocalLipSync then return end

    local talkData
    if type(payload.message) == "string" then
        local ok, result = pcall(json.decode, payload.message)
        if not ok then
            print("[YaCA-Websocket]: Error while parsing other talk state message")
            return
        end
        talkData = result
    else
        talkData = payload.message
    end

    local player = self:getPlayerByClientId(talkData.clientId)
    if not player or not player.remoteID then return end

    local playerId = GetPlayerFromServerId(player.remoteID)
    if playerId == -1 then return end

    SetPlayerTalkingOverride(playerId, talkData.isTalking)
end

function YacaClient:handleMovedChannel(newChannel)
    if newChannel ~= "INGAME_CHANNEL" and newChannel ~= "EXCLUDED_CHANNEL" then
        print("[YaCA-Websocket]: Unknown channel type: " .. tostring(newChannel))
        return
    end

    if newChannel == "INGAME_CHANNEL" then
        self:setCurrentPluginState(YacaPluginStates.IN_INGAME_CHANNEL)
    else
        self:setCurrentPluginState(YacaPluginStates.IN_EXCLUDED_CHANNEL)
    end

    TriggerEvent("yaca:external:channelChanged", newChannel)
end

function YacaClient:checkIfVehicleHasOpening(vehicle)
    if not vehicle then return true end
    if self.mufflingVehicleWhitelistHash[GetEntityModel(vehicle)] then return true end
    return YacaVehicleHasOpening(vehicle)
end

function YacaClient:getMuffleIntensity(playerPed, nearbyPlayerPed, playerVehicle, ownCurrentRoom, ownVehicleHasOpening, nearbyUsesMegaphone, vehicleOpeningCache)
    local intensities = self.sharedConfig.mufflingSettings.intensities
    local targetRoom = GetRoomKeyFromEntity(nearbyPlayerPed)

    if ownCurrentRoom ~= targetRoom and not HasEntityClearLosToEntity(playerPed, nearbyPlayerPed, 17) then
        if targetRoom ~= 0 and self.whitelistedRoomIds[targetRoom] then
            return 0
        end
        return intensities.differentRoom
    end

    if self.isRedM or not self.sharedConfig.mufflingSettings.vehicleMuffling.enabled then
        return 0
    end

    local nearbyPlayerVehicle = GetVehiclePedIsIn(nearbyPlayerPed, false)
    local ownVehicleId = playerVehicle or 0

    if ownVehicleId == nearbyPlayerVehicle then return 0 end

    if nearbyUsesMegaphone then
        if ownVehicleHasOpening then return 0 end
        return intensities.megaPhoneInCar
    end

    local nearbyPlayerVehicleHasOpening = vehicleOpeningCache[nearbyPlayerVehicle]
    if nearbyPlayerVehicleHasOpening == nil then
        nearbyPlayerVehicleHasOpening = self:checkIfVehicleHasOpening(nearbyPlayerVehicle > 0 and nearbyPlayerVehicle or false)
        vehicleOpeningCache[nearbyPlayerVehicle] = nearbyPlayerVehicleHasOpening
    end

    if not ownVehicleHasOpening and not nearbyPlayerVehicleHasOpening then
        return intensities.bothCarsClosed
    end

    if not ownVehicleHasOpening or not nearbyPlayerVehicleHasOpening then
        return intensities.oneCarClosed
    end

    return 0
end

function YacaClient:getRoomPair(ped, isolatedFromRoom)
    if not self.isFiveM or isolatedFromRoom then
        return YacaOutsideRoomPair
    end
    return YacaGetInteriorRoomPair(ped)
end

function YacaClient:isAirborneVehicle(vehicle)
    if not self.sharedConfig.airborne or not self.sharedConfig.airborne.enabled or not self.isFiveM or not vehicle then
        return false
    end

    local vehicleClass = GetVehicleClass(vehicle)
    for _, cls in ipairs(self.sharedConfig.airborne.vehicleClasses or {}) do
        if cls == vehicleClass then
            return true
        end
    end
    return false
end

function YacaClient:handleAirborneEmit(crewMembers)
    for playerId in pairs(self.currentlyAirborneApplied) do
        if not crewMembers[playerId] then
            self.currentlyAirborneApplied[playerId] = nil
            local player = self:getPlayerByID(playerId)
            if player then
                self:setPlayersCommType(
                    player, YacaFilterEnum.AIRBORNE, false,
                    nil, nil, CommDeviceMode.TRANSCEIVER, CommDeviceMode.TRANSCEIVER
                )
            end
        end
    end

    for playerId in pairs(crewMembers) do
        if not self.currentlyAirborneApplied[playerId] then
            local player = self:getPlayerByID(playerId)
            if player then
                self:setPlayersCommType(
                    player, YacaFilterEnum.AIRBORNE, true,
                    nil, nil, CommDeviceMode.TRANSCEIVER, CommDeviceMode.TRANSCEIVER
                )
                self.currentlyAirborneApplied[playerId] = true
            end
        end
    end
end

function YacaClient:setPlayerVolumeModifier(serverId, volumeModifier)
    local player = self:getPlayerByID(serverId)
    if not player then return end

    if type(volumeModifier) ~= "number" then
        print(("[YaCA] Invalid volume modifier for player %s: %s"):format(tostring(serverId), tostring(volumeModifier)))
        return
    end

    player.volumeModifier = YacaClamp(volumeModifier, 0.1, 2)
end

function YacaClient:handlePhoneSpeakerEmit(playersToPhoneSpeaker, playersOnPhoneSpeaker)
    if self.useWhisper then
        local phoneSpeakerActive = YacaPhone and YacaPhone.phoneSpeakerActive
        local inCallSize = YacaPhone and next(YacaPhone.inCallWith) ~= nil

        if (phoneSpeakerActive and inCallSize) or ((not phoneSpeakerActive or not inCallSize) and next(self.currentlySendingPhoneSpeakerSender) ~= nil) then
            local playersToNotReceive = {}
            local playersNeedsReceive = {}

            for id in pairs(self.currentlySendingPhoneSpeakerSender) do
                if not playersToPhoneSpeaker[id] then
                    playersToNotReceive[#playersToNotReceive + 1] = id
                end
            end
            for id in pairs(playersToPhoneSpeaker) do
                if not self.currentlySendingPhoneSpeakerSender[id] then
                    playersNeedsReceive[#playersNeedsReceive + 1] = id
                end
            end

            self.currentlySendingPhoneSpeakerSender = playersToPhoneSpeaker

            if #playersNeedsReceive > 0 or #playersToNotReceive > 0 then
                TriggerServerEvent("server:yaca:phoneSpeakerEmitWhisper", playersNeedsReceive, playersToNotReceive)
            end
        end
    end

    for playerId in pairs(self.currentlyPhoneSpeakerApplied) do
        if not playersOnPhoneSpeaker[playerId] then
            self.currentlyPhoneSpeakerApplied[playerId] = nil
            local player = self:getPlayerByID(playerId)
            if player then
                self:setPlayersCommType(
                    player, YacaFilterEnum.PHONE_SPEAKER, false,
                    nil, self.sharedConfig.maxPhoneSpeakerRange,
                    CommDeviceMode.RECEIVER, CommDeviceMode.SENDER
                )
            end
        end
    end
end

function YacaClient:handlePhoneEmit(playerToHearOnPhone)
    if not self.sharedConfig.phoneHearPlayersNearby then return end

    local phoneSpeakerActive = YacaPhone and YacaPhone.phoneSpeakerActive
    local inCallSize = YacaPhone and next(YacaPhone.inCallWith) ~= nil

    if self.sharedConfig.phoneHearPlayersNearby == "PHONE_SPEAKER" then
        if not ((phoneSpeakerActive and inCallSize) or ((not phoneSpeakerActive or not inCallSize) and next(self.phoneHearNearbyPlayer) ~= nil)) then
            return
        end
    else
        if not (inCallSize or (not inCallSize and next(self.phoneHearNearbyPlayer) ~= nil)) then
            return
        end
    end

    local playersToNotHear = {}
    local playersToHear = {}

    for id in pairs(self.phoneHearNearbyPlayer) do
        if not playerToHearOnPhone[id] then
            playersToNotHear[#playersToNotHear + 1] = id
        end
    end
    for id in pairs(playerToHearOnPhone) do
        if not self.phoneHearNearbyPlayer[id] then
            playersToHear[#playersToHear + 1] = id
        end
    end

    self.phoneHearNearbyPlayer = playerToHearOnPhone

    if #playersToHear > 0 or #playersToNotHear > 0 then
        TriggerServerEvent("server:yaca:phoneEmit", playersToHear, playersToNotHear)
    end
end

function YacaClient:calcPlayers()
    local allPlayers = self.allPlayers
    local localData = allPlayers[YacaCache.serverId]
    if not localData then return end

    local playersList = {}
    local playersByRemoteId = {}
    local playersToPhoneSpeaker = {}
    local playersOnPhoneSpeaker = {}
    local playerToHearOnPhone = {}
    local vehicleOpeningCache = {}
    local airborneCrewMembers = {}

    local localPlayerPed = YacaCache.ped
    local localPlayerVehicle = YacaCache.vehicle

    if self.spectatingPlayer then
        local remotePlayerId = GetPlayerFromServerId(self.spectatingPlayer)
        if remotePlayerId ~= -1 then
            local remotePlayerPed = GetPlayerPed(remotePlayerId)
            if remotePlayerPed ~= 0 then
                localPlayerPed = remotePlayerPed
                local remotePlayerVehicle = GetVehiclePedIsIn(remotePlayerPed, false)
                localPlayerVehicle = remotePlayerVehicle ~= 0 and remotePlayerVehicle or false
            end
        end
    end

    local localPos = GetEntityCoords(localPlayerPed, false)
    local currentRoom = GetRoomKeyFromEntity(localPlayerPed)
    local localRoomPair = self:getRoomPair(localPlayerPed, localPlayerVehicle and true or false)
    local hasVehicleOpening = self.isFiveM and self:checkIfVehicleHasOpening(localPlayerVehicle) or true
    local phoneSpeakerActive = YacaPhone and YacaPhone.phoneSpeakerActive and next(YacaPhone.inCallWith) ~= nil
    local phoneHearNearby = self.sharedConfig.phoneHearPlayersNearby
    local maxPhoneSpeakerRange = self.sharedConfig.maxPhoneSpeakerRange
    local serverId = YacaCache.serverId
    local defaultVoiceRange = self.defaultVoiceRange
    local useWhisper = self.useWhisper
    local localVehicleIsAirborne = self:isAirborneVehicle(localPlayerVehicle)

    local activePlayers = GetActivePlayers()
    for _, player in ipairs(activePlayers) do
        local remoteId = GetPlayerServerId(player)
        local playerPed = GetPlayerPed(player)
        if remoteId ~= 0 and remoteId ~= serverId and playerPed > 0 then
            local voiceSetting = allPlayers[remoteId]
            if voiceSetting and voiceSetting.clientId then
                local range = voiceSetting.cachedVoiceRange
                if range == nil then
                    range = Player(remoteId).state[YACA_STATE_VOICE_RANGE] or defaultVoiceRange
                    voiceSetting.cachedVoiceRange = range
                end

                local usesMegaphone = voiceSetting.cachedUsesMegaphone
                if usesMegaphone == nil then
                    usesMegaphone = Player(remoteId).state[YACA_STATE_MEGAPHONE] ~= nil
                    voiceSetting.cachedUsesMegaphone = usesMegaphone
                end

                local muffleIntensity = self:getMuffleIntensity(
                    localPlayerPed, playerPed, localPlayerVehicle,
                    currentRoom, hasVehicleOpening,
                    usesMegaphone,
                    vehicleOpeningCache
                )

                local playerPos = GetEntityCoords(playerPed, false)
                local distanceToPlayer = #(localPos - playerPos)
                local playerDirection = GetEntityForwardVector(playerPed)
                local isUnderwater = IsPedSwimmingUnderWater(playerPed)
                local playerVehicle = GetVehiclePedIsIn(playerPed, false)
                local sharesLocalVehicle = localPlayerVehicle and playerVehicle == localPlayerVehicle
                local playerRoomPair = self:getRoomPair(playerPed, sharesLocalVehicle)

                if localVehicleIsAirborne and sharesLocalVehicle then
                    airborneCrewMembers[remoteId] = true
                end

                if not playersOnPhoneSpeaker[remoteId] then
                    local entry = {
                        client_id = voiceSetting.clientId,
                        position = YacaConvertToXYZ(playerPos),
                        direction = YacaConvertToXYZ(playerDirection),
                        range = range,
                        is_underwater = isUnderwater,
                        muffle_intensity = muffleIntensity,
                        is_muted = voiceSetting.forceMuted or false,
                    }
                    if type(voiceSetting.volumeModifier) == "number" then
                        entry.volume_modifier = voiceSetting.volumeModifier
                    end
                    if playerRoomPair.interiorKey ~= 0 and playerRoomPair.roomKey ~= 0 then
                        entry.interior_key = playerRoomPair.interiorKey
                        entry.room_key = playerRoomPair.roomKey
                    end
                    playersList[#playersList + 1] = entry
                    playersByRemoteId[remoteId] = #playersList
                end

                if phoneHearNearby and not localData.mutedOnPhone and not voiceSetting.forceMuted and distanceToPlayer <= range then
                    if phoneHearNearby == "PHONE_SPEAKER" and phoneSpeakerActive then
                        playerToHearOnPhone[remoteId] = true
                    elseif phoneHearNearby == true and YacaPhone and next(YacaPhone.inCallWith) ~= nil then
                        playerToHearOnPhone[remoteId] = true
                    end
                end

                if distanceToPlayer <= maxPhoneSpeakerRange then
                    if useWhisper and phoneSpeakerActive then
                        playersToPhoneSpeaker[remoteId] = true
                    end

                    if voiceSetting.phoneCallMemberIds then
                        local posXYZ = YacaConvertToXYZ(playerPos)
                        local dirXYZ = YacaConvertToXYZ(playerDirection)
                        for _, phoneCallMemberId in ipairs(voiceSetting.phoneCallMemberIds) do
                            local phoneCallMember = allPlayers[phoneCallMemberId]
                            if phoneCallMember and phoneCallMember.clientId and not phoneCallMember.mutedOnPhone and not phoneCallMember.forceMuted then
                                local speakerEntry = {
                                    client_id = phoneCallMember.clientId,
                                    position = posXYZ,
                                    direction = dirXYZ,
                                    range = maxPhoneSpeakerRange,
                                    is_underwater = isUnderwater,
                                    muffle_intensity = muffleIntensity,
                                    is_muted = false,
                                }
                                if type(phoneCallMember.volumeModifier) == "number" then
                                    speakerEntry.volume_modifier = phoneCallMember.volumeModifier
                                end
                                if playerRoomPair.interiorKey ~= 0 and playerRoomPair.roomKey ~= 0 then
                                    speakerEntry.interior_key = playerRoomPair.interiorKey
                                    speakerEntry.room_key = playerRoomPair.roomKey
                                end

                                local existingIndex = playersByRemoteId[phoneCallMemberId]
                                if existingIndex then
                                    playersList[existingIndex] = speakerEntry
                                else
                                    playersList[#playersList + 1] = speakerEntry
                                    playersByRemoteId[phoneCallMemberId] = #playersList
                                end

                                playersOnPhoneSpeaker[phoneCallMemberId] = true

                                if not self.currentlyPhoneSpeakerApplied[phoneCallMemberId] then
                                    self:setPlayersCommType(
                                        phoneCallMember, YacaFilterEnum.PHONE_SPEAKER, true,
                                        nil, maxPhoneSpeakerRange,
                                        CommDeviceMode.RECEIVER, CommDeviceMode.SENDER
                                    )
                                    self.currentlyPhoneSpeakerApplied[phoneCallMemberId] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    self:handlePhoneSpeakerEmit(playersToPhoneSpeaker, playersOnPhoneSpeaker)
    self:handlePhoneEmit(playerToHearOnPhone)
    self:handleAirborneEmit(airborneCrewMembers)

    local playerPayload = {
        player_direction = YacaGetCamDirection(),
        player_position = YacaConvertToXYZ(localPos),
        player_range = LocalPlayer.state[YACA_STATE_VOICE_RANGE] or defaultVoiceRange,
        player_is_underwater = IsPedSwimmingUnderWater(localPlayerPed),
        player_is_muted = localData.forceMuted or false,
        players_list = playersList,
    }
    if localRoomPair.roomKey ~= 0 then
        playerPayload.room_key = localRoomPair.roomKey
    end
    if localRoomPair.interiorKey ~= 0 then
        playerPayload.interior_key = localRoomPair.interiorKey
    end

    self:sendWebsocket({
        base = { request_type = "INGAME" },
        player = playerPayload,
    })
end

function YacaClient:registerKeybindings()
    local kb = self.sharedConfig.keyBinds

    if kb.increaseVoiceRange and kb.increaseVoiceRange ~= false then
        RegisterCommand("yaca:increaseVoiceRange", function()
            self:changeVoiceRange(true)
        end, false)
        RegisterKeyMapping("yaca:increaseVoiceRange", YacaLocale("change_voice_range_increase"), "keyboard", kb.increaseVoiceRange)
    end

    if kb.decreaseVoiceRange and kb.decreaseVoiceRange ~= false then
        RegisterCommand("yaca:decreaseVoiceRange", function()
            self:changeVoiceRange(false)
        end, false)
        RegisterKeyMapping("yaca:decreaseVoiceRange", YacaLocale("change_voice_range_decrease"), "keyboard", kb.decreaseVoiceRange)
    end

    if kb.voiceRangeWithMouseWheel and kb.voiceRangeWithMouseWheel ~= false then
        local mousewheelActive = false
        RegisterCommand("+yaca:changeVoiceRangeWithMousewheel", function()
            mousewheelActive = true
            Citizen.CreateThread(function()
                while mousewheelActive do
                    self:handleVoiceRangeViaMouseWheel()
                    Citizen.Wait(0)
                end
            end)
        end, false)

        RegisterCommand("-yaca:changeVoiceRangeWithMousewheel", function()
            mousewheelActive = false
        end, false)

        RegisterKeyMapping("+yaca:changeVoiceRangeWithMousewheel", YacaLocale("change_voice_range_via_mousewheel"), "keyboard", kb.voiceRangeWithMouseWheel)
    end
end

function YacaClient:registerRdrKeybindings()
    local kb = self.sharedConfig.keyBinds

    if kb.increaseVoiceRange and kb.increaseVoiceRange ~= false then
        YacaRegisterRdrKeyBind(kb.increaseVoiceRange, function()
            self:changeVoiceRange(true)
        end)
    end

    if kb.decreaseVoiceRange and kb.decreaseVoiceRange ~= false then
        YacaRegisterRdrKeyBind(kb.decreaseVoiceRange, function()
            self:changeVoiceRange(false)
        end)
    end

    if kb.voiceRangeWithMouseWheel and kb.voiceRangeWithMouseWheel ~= false then
        YacaRegisterRdrKeyBind(
            kb.voiceRangeWithMouseWheel,
            function()
                self.voiceRangeViaMouseWheelTick = true
                Citizen.CreateThread(function()
                    while self.voiceRangeViaMouseWheelTick do
                        self:handleVoiceRangeViaMouseWheel()
                        Citizen.Wait(0)
                    end
                end)
            end,
            function()
                self.voiceRangeViaMouseWheelTick = nil
            end
        )
    end
end

function YacaClient:registerExports()
    exports("isEnabled", function() return GetConvarBool("yaca_enabled", true) end)
    exports("getVoiceRange", function(serverId) return self:getVoiceRange(serverId) end)
    exports("getVoiceRanges", function() return self.sharedConfig.voiceRange.ranges end)
    exports("changeVoiceRange", function(increase) self:changeVoiceRange(increase) end)
    exports("setVoiceRange", function(range) self:setVoiceRange(range) end)
    exports("isPlayerTalking", function(serverId)
        local playerState = self:getPlayerByID(serverId)
        return playerState and playerState.isTalking or false
    end)
    exports("setVoiceRangeChangeAllowedState", function(state) self.canChangeVoiceRange = state end)
    exports("getVoiceRangeChangeAllowedState", function() return self.canChangeVoiceRange end)
    exports("setMaxVoiceRange", function(maxRange) self.maxVoiceRange = maxRange end)
    exports("getMaxVoiceRange", function() return self.maxVoiceRange end)
    exports("getMicrophoneMuteState", function() return self.isMicrophoneMuted end)
    exports("getMicrophoneDisabledState", function() return self.isMicrophoneDisabled end)
    exports("getSoundMuteState", function() return self.isSoundMuted end)
    exports("getSoundDisabledState", function() return self.isSoundDisabled end)
    exports("getPluginState", function() return self.currentPluginState or YacaPluginStates.NOT_CONNECTED end)
    exports("getTeamSpeakUniqueIdentifier", function() return self.teamSpeakUniqueIdentifier end)
    exports("setPlayerVolumeModifier", function(serverId, volumeModifier)
        self:setPlayerVolumeModifier(serverId, volumeModifier)
    end)
    exports("getPlayerVolumeModifier", function(serverId)
        local player = self:getPlayerByID(serverId)
        return (player and player.volumeModifier) or 1
    end)
    exports("getGlobalErrorLevel", function() return GlobalState[YACA_STATE_GLOBAL_ERROR_LEVEL] or 0 end)
    exports("setSpectatingPlayer", function(player) self.spectatingPlayer = player end)
    exports("getSpectatingPlayer", function() return self.spectatingPlayer end)
    exports("setVoiceRangeMarkerColor", function(r, g, b, a)
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" or type(a) ~= "number" then
            print("[YaCA] Invalid color value in setVoiceRangeMarkerColor")
            return
        end
        self.sharedConfig.voiceRange.markerColor.r = r
        self.sharedConfig.voiceRange.markerColor.g = g
        self.sharedConfig.voiceRange.markerColor.b = b
        self.sharedConfig.voiceRange.markerColor.a = a
    end)
    exports("getVoiceRangeMarkerColor", function()
        local mc = self.sharedConfig.voiceRange.markerColor
        return { mc.r, mc.g, mc.b, mc.a }
    end)
    exports("resetVoiceRangeMarkerColor", function()
        self.sharedConfig.voiceRange.markerColor.r = 0
        self.sharedConfig.voiceRange.markerColor.g = 255
        self.sharedConfig.voiceRange.markerColor.b = 0
        self.sharedConfig.voiceRange.markerColor.a = 50
    end)
end

function YacaClient:registerEvents()
    RegisterNetEvent("onPlayerJoining", function(target)
        local player = self:getPlayerByID(target)
        if not player then return end

        if YacaRadio then
            local frequency = YacaRadio.playersWithShortRange[target]
            if frequency then
                local channel = YacaRadio:findRadioChannelByFrequency(frequency)
                if channel then
                    self:setPlayersCommType(
                        player, YacaFilterEnum.RADIO, true, channel,
                        nil, CommDeviceMode.RECEIVER, CommDeviceMode.SENDER,
                        GlobalState[YACA_STATE_GLOBAL_ERROR_LEVEL]
                    )
                    if YacaSaltyChatBridge and self.sharedConfig.saltyChatBridge then
                        YacaSaltyChatBridge:handleRadioReceivingStateChange(true, channel)
                    end
                end
            end
        end
    end)

    RegisterNetEvent("onPlayerDropped", function(target)
        local player = self:getPlayerByID(target)
        if not player then return end

        if YacaPhone then
            YacaPhone:removePhoneSpeakerFromEntity(target)
        end

        if YacaRadio then
            local frequency = YacaRadio.playersWithShortRange[target]
            if frequency then
                local channel = YacaRadio:findRadioChannelByFrequency(frequency)
                if channel then
                    self:setPlayersCommType(
                        player, YacaFilterEnum.RADIO, false, channel,
                        nil, CommDeviceMode.RECEIVER, CommDeviceMode.SENDER,
                        GlobalState[YACA_STATE_GLOBAL_ERROR_LEVEL]
                    )

                    if YacaSaltyChatBridge and self.sharedConfig.saltyChatBridge then
                        local inRadio = YacaRadio.playersInRadioChannel[channel]
                        if inRadio then
                            local count = 0
                            for id in pairs(inRadio) do
                                if id ~= target then
                                    count = count + 1
                                end
                            end
                            YacaSaltyChatBridge:handleRadioReceivingStateChange(count > 0, channel)
                        end
                    end
                end
            end
        end
    end)

    AddEventHandler("onResourceStop", function(resourceName)
        if YacaCache.resource ~= resourceName then return end
        if YacaWebSocket.initialized then
            YacaWebSocket:close()
        end
    end)

    RegisterNetEvent("client:yaca:init", function(dataObj)
        self.rangeIntervalToken = (self.rangeIntervalToken or 0) + 1

        if not YacaWebSocket.initialized then
            YacaWebSocket.initialized = true

            YacaWebSocket:on("message", function(msg)
                self:handleResponse(msg)
            end)

            YacaWebSocket:on("close", function(code, reason)
                self:setCurrentPluginState(YacaPluginStates.NOT_CONNECTED)
                print(("[YACA-Websocket]: client disconnected %s %s"):format(tostring(code), tostring(reason)))

                if self.sharedConfig.autoConnectOnJoin then
                    startVoiceJoinRetryLoop()
                end
            end)

            YacaWebSocket:on("open", function()
                self:setCurrentPluginState(YacaPluginStates.CONNECTED)
                if self.firstConnect then
                    self:initRequest(dataObj)
                    self.firstConnect = false
                else
                    TriggerServerEvent("server:yaca:wsReady")
                end
                print("[YACA-Websocket]: Successfully connected to the voice plugin")
            end)

            YacaWebSocket:start()
        end

        if self.firstConnect then return end
        self:initRequest(dataObj)
    end)

    RegisterNetEvent("client:yaca:disconnect", function(remoteId)
        if YacaPhone then
            YacaPhone:handleDisconnect(remoteId)
        end
        self.currentlyAirborneApplied[remoteId] = nil
        self.allPlayers[remoteId] = nil
    end)

    RegisterNetEvent("client:yaca:addPlayers", function(dataObjects)
        if type(dataObjects) ~= "table" then return end
        if dataObjects.clientId ~= nil then
            dataObjects = { dataObjects }
        end

        local newPlayers = {}
        for _, dataObj in ipairs(dataObjects) do
            if dataObj and dataObj.clientId ~= nil and dataObj.playerId ~= nil then
                local currentData = self:getPlayerByID(dataObj.playerId)
                local playerState = Player(dataObj.playerId).state
                self.allPlayers[dataObj.playerId] = {
                    remoteID = dataObj.playerId,
                    clientId = dataObj.clientId,
                    forceMuted = dataObj.forceMuted or false,
                    phoneCallMemberIds = currentData and currentData.phoneCallMemberIds or nil,
                    mutedOnPhone = dataObj.mutedOnPhone or false,
                    isTalking = currentData and currentData.isTalking or false,
                    volumeModifier = dataObj.volumeModifier ~= nil and dataObj.volumeModifier or (currentData and currentData.volumeModifier) or nil,
                    cachedVoiceRange = playerState[YACA_STATE_VOICE_RANGE] or self.defaultVoiceRange,
                    cachedUsesMegaphone = playerState[YACA_STATE_MEGAPHONE] ~= nil,
                    radioProp = currentData and currentData.radioProp or nil,
                }
                newPlayers[#newPlayers + 1] = dataObj.playerId
            end
        end

        if YacaPhone then
            YacaPhone:reestablishCalls(newPlayers)
        end
    end)

    RegisterNetEvent("client:yaca:muteTarget", function(target, muted)
        local player = self:getPlayerByID(target)
        if not player then return end
        player.forceMuted = muted
    end)

    RegisterNetEvent("client:yaca:setPlayerVolumeModifier", function(target, volumeModifier)
        self:setPlayerVolumeModifier(target, volumeModifier)
    end)

    RegisterNetEvent("client:yaca:changeVoiceRange", function(range)
        TriggerEvent("yaca:external:voiceRangeUpdate", range, self.rangeIndex)
        if self.sharedConfig.saltyChatBridge then
            TriggerEvent("SaltyChat_VoiceRangeChanged", string.format("%.1f", range), self.rangeIndex, #self.sharedConfig.voiceRange.ranges)
        end
    end)

    RegisterNetEvent("client:yaca:notification", function(message, notifType)
        self:notification(message, notifType)
    end)

    RegisterNetEvent("txcl:spectate:start", function(targetServerId)
        self.spectatingPlayer = targetServerId
    end)

    RegisterNetEvent("client:yaca:txadmin:stopspectate", function()
        self.spectatingPlayer = false
    end)
end

if GetConvarBool("yaca_enabled", true) then
    Citizen.CreateThread(function()
        Citizen.Wait(0)
        initializeClient()
    end)
end

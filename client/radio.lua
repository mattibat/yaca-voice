YacaRadio = {
    radioEnabled = false,
    radioInitialized = false,

    talkingInChannels = {},
    radioChannelSettings = {},
    playersWithShortRange = {},
    playersInRadioChannel = {},
    radioTowerCalculation = {},

    radioMode = "None",
    activeRadioChannel = 1,
    secondaryRadioChannel = 2,

    radioOnCooldown = false,
    currentRadioProp = nil,

    defaultRadioSettings = {
        frequency = "0",
        muted = false,
        volume = 1,
        stereo = YacaStereoMode.STEREO,
    },
}

local function initRadioModule()
    if YacaClient.sharedConfig then
        YacaRadio.radioMode = YacaClient.sharedConfig.radioSettings.mode or "None"
    end

    YacaRadio:registerExports()
    YacaRadio:registerEvents()
    YacaRadio:registerStateBagHandlers()

    if YacaClient.isFiveM then
        YacaRadio:registerKeybinds()
    elseif YacaClient.isRedM then
        YacaRadio:registerRdrKeybinds()
    end
end

function YacaRadio:registerStateBagHandlers()
    AddStateBagChangeHandler(YACA_STATE_RADIO_PROP, "", function(bagName, _, value, _, replicated)
        if replicated then return end

        local playerId = GetPlayerFromStateBagName(bagName)
        if playerId == 0 then return end

        local playerSource = GetPlayerServerId(playerId)
        if playerSource == 0 then return end

        local player = YacaClient:getPlayerByID(playerSource)
        if not player then return end

        local propCfg = YacaClient.sharedConfig.radioSettings.propWhileTalking
        if value then
            if propCfg and propCfg.prop ~= false then
                player.radioProp = YacaCreateProp(
                    GetPlayerPed(playerId),
                    propCfg.prop,
                    propCfg.boneId,
                    propCfg.position,
                    propCfg.rotation,
                    false
                )
            end
        else
            self:removeRadioProp(player)
        end
    end)
end

function YacaRadio:removeRadioProp(player)
    if not player or not player.radioProp then return end

    if DoesEntityExist(player.radioProp) then
        DeleteEntity(player.radioProp)
    end

    local propCfg = YacaClient.sharedConfig.radioSettings.propWhileTalking
    if propCfg and propCfg.prop ~= false then
        SetModelAsNoLongerNeeded(propCfg.prop)
    end

    player.radioProp = nil
end

function YacaRadio:registerExports()
    exports("enableRadio", function(state) self:enableRadio(state) end)
    exports("isRadioEnabled", function() return self.radioEnabled end)
    exports("changeRadioFrequency", function(frequency) self:changeRadioFrequencyRaw(frequency) end)
    exports("changeRadioFrequencyRaw", function(channel, frequency) self:changeRadioFrequencyRaw(frequency, channel) end)
    exports("getRadioFrequency", function(channel) return self:getRadioFrequency(channel) end)
    exports("muteRadioChannel", function(state) self:muteRadioChannel(state) end)
    exports("muteRadioChannelRaw", function(channel, state) self:muteRadioChannelRaw(channel, state) end)
    exports("isRadioChannelMuted", function(channel) return self:isRadioChannelMuted(channel or self.activeRadioChannel) end)
    exports("setActiveRadioChannel", function(channel) return self:setActiveRadioChannel(channel) end)
    exports("getActiveRadioChannel", function() return self.activeRadioChannel end)
    exports("setSecondaryRadioChannel", function(channel) return self:setSecondaryRadioChannel(channel) end)
    exports("getSecondaryRadioChannel", function() return self.secondaryRadioChannel end)
    exports("changeRadioChannelVolume", function(higher) return self:changeRadioChannelVolume(higher) end)
    exports("changeRadioChannelVolumeRaw", function(channel, volume) return self:changeRadioChannelVolumeRaw(volume, channel) end)
    exports("getRadioChannelVolume", function(channel) return self:getRadioChannelVolume(channel) end)
    exports("changeRadioChannelStereo", function() return self:changeRadioChannelStereo() end)
    exports("changeRadioChannelStereoRaw", function(channel, stereo) return self:changeRadioChannelStereoRaw(stereo, channel) end)
    exports("getRadioChannelStereo", function(channel) return self:getRadioChannelStereo(channel) end)
    exports("radioTalkingStart", function(state, channel) self:radioTalkingStart(state, channel) end)
    exports("setRadioMode", function(mode) self.radioMode = mode end)
    exports("getRadioMode", function() return self.radioMode end)
end

function YacaRadio:registerEvents()
    RegisterNetEvent("onPlayerDropped", function(target)
        local propCfg = YacaClient.sharedConfig.radioSettings.propWhileTalking
        if not propCfg or propCfg.createMode ~= "stateBag" then return end

        local player = YacaClient:getPlayerByID(target)
        if player then
            self:removeRadioProp(player)
        end
    end)

    RegisterNetEvent("client:yaca:setRadioFreq", function(channel, frequency)
        self:setRadioFrequency(channel, frequency)
    end)

    RegisterNetEvent("client:yaca:radioTalking", function(target, frequency, state, infos, senderDistanceToTower, senderPosition)
        senderDistanceToTower = senderDistanceToTower or -1
        senderPosition = senderPosition or { 0, 0, 0 }

        local channel = self:findRadioChannelByFrequency(frequency)
        if not channel then return end

        local ownDistanceToTowerOrSender = self:getDistanceToTowerOrSender(senderPosition)

        if state then
            if self.radioMode ~= "None" and ownDistanceToTowerOrSender > YacaClient.sharedConfig.radioSettings.maxDistance then
                return
            end
            if self.radioMode == "Tower" and senderDistanceToTower > YacaClient.sharedConfig.radioSettings.maxDistance then
                return
            end
        end

        local player = YacaClient:getPlayerByID(target)
        if not player then return end

        local info = infos and (infos[tostring(YacaCache.serverId)] or infos[YacaCache.serverId])

        if not info or not info.shortRange or (info.shortRange and GetPlayerFromServerId(target) ~= -1) then
            local errorLevel = self:getErrorLevelFromDistance(ownDistanceToTowerOrSender, senderDistanceToTower)
            YacaClient:setPlayersCommType(
                player, YacaFilterEnum.RADIO, state, channel,
                nil, CommDeviceMode.RECEIVER, CommDeviceMode.SENDER, errorLevel
            )
        end

        if not self.playersInRadioChannel[channel] then
            self.playersInRadioChannel[channel] = {}
        end

        if state then
            self.playersInRadioChannel[channel][target] = true
            if info and info.shortRange then
                self.playersWithShortRange[target] = frequency
            end

            TriggerEvent("yaca:external:isRadioReceiving", true, channel, target)
            if YacaSaltyChatBridge then
                YacaSaltyChatBridge:handleRadioReceivingStateChange(true, channel)
            end
        else
            self.playersInRadioChannel[channel][target] = nil
            if info and info.shortRange then
                self.playersWithShortRange[target] = nil
            end

            local count = 0
            for _ in pairs(self.playersInRadioChannel[channel]) do
                count = count + 1
            end
            local receiveState = count > 0
            TriggerEvent("yaca:external:isRadioReceiving", receiveState, channel, target)
            if YacaSaltyChatBridge then
                YacaSaltyChatBridge:handleRadioReceivingStateChange(receiveState, channel)
            end
        end
    end)

    RegisterNetEvent("client:yaca:radioTalkingWhisper", function(targets, frequency, state, senderPosition)
        senderPosition = senderPosition or { 0, 0, 0 }

        local channel = self:findRadioChannelByFrequency(frequency)
        if not channel then return end

        local ownDistanceToTowerOrSender = self:getDistanceToTowerOrSender(senderPosition)

        if state and self.radioMode ~= "None" and ownDistanceToTowerOrSender > YacaClient.sharedConfig.radioSettings.maxDistance then
            targets = {}
        end

        self:radioTalkingStateToPluginWithWhisper(state, targets, channel)
    end)

    RegisterNetEvent("client:yaca:setRadioMuteState", function(channel, state)
        local channelSettings = self.radioChannelSettings[channel]
        if not channelSettings then return end

        channelSettings.muted = state
        TriggerEvent("yaca:external:setRadioMuteState", channel, state)
        self:disableRadioFromPlayerInChannel(channel)
        self:updateRadioChannelData(channel)
    end)

    RegisterNetEvent("client:yaca:leaveRadioChannel", function(client_ids, frequency)
        if type(client_ids) ~= "table" then
            client_ids = { client_ids }
        end

        local channel = self:findRadioChannelByFrequency(frequency)
        if not channel then return end

        local playerData = YacaClient:getPlayerByID(YacaCache.serverId)
        if not playerData or not playerData.clientId then return end

        local shouldLeave = false
        for _, cid in ipairs(client_ids) do
            if cid == playerData.clientId then
                shouldLeave = true
                break
            end
        end

        if shouldLeave then
            self:setRadioFrequency(channel, "0")
            self.talkingInChannels[channel] = nil
            self.radioTowerCalculation[channel] = nil
            self:stopTalkingVisuals(channel)
        end

        YacaClient:sendWebsocket({
            base = { request_type = "INGAME" },
            comm_device_left = {
                comm_type = YacaFilterEnum.RADIO,
                client_ids = client_ids,
                channel = channel,
            },
        })
    end)
end

function YacaRadio:registerKeybinds()
    if YacaClient.sharedConfig.keyBinds.primaryRadioTransmit and YacaClient.sharedConfig.keyBinds.primaryRadioTransmit ~= false then
        RegisterCommand("+yaca:radioTalking", function()
            self:radioTalkingStart(true, self.activeRadioChannel)
        end, false)
        RegisterCommand("-yaca:radioTalking", function()
            self:radioTalkingStart(false, self.activeRadioChannel)
        end, false)
        RegisterKeyMapping("+yaca:radioTalking", YacaLocale("use_radio"), "keyboard", YacaClient.sharedConfig.keyBinds.primaryRadioTransmit)
    end

    if YacaClient.sharedConfig.keyBinds.secondaryRadioTransmit and YacaClient.sharedConfig.keyBinds.secondaryRadioTransmit ~= false then
        RegisterCommand("+yaca:secondaryRadioTalking", function()
            self:radioTalkingStart(true, self.secondaryRadioChannel)
        end, false)
        RegisterCommand("-yaca:secondaryRadioTalking", function()
            self:radioTalkingStart(false, self.secondaryRadioChannel)
        end, false)
        RegisterKeyMapping("+yaca:secondaryRadioTalking", YacaLocale("use_secondary_radio"), "keyboard", YacaClient.sharedConfig.keyBinds.secondaryRadioTransmit)
    end
end

function YacaRadio:registerRdrKeybinds()
    if YacaClient.sharedConfig.keyBinds.primaryRadioTransmit and YacaClient.sharedConfig.keyBinds.primaryRadioTransmit ~= false then
        YacaRegisterRdrKeyBind(
            YacaClient.sharedConfig.keyBinds.primaryRadioTransmit,
            function() self:radioTalkingStart(true, self.activeRadioChannel) end,
            function() self:radioTalkingStart(false, self.activeRadioChannel) end
        )
    end

    if YacaClient.sharedConfig.keyBinds.secondaryRadioTransmit and YacaClient.sharedConfig.keyBinds.secondaryRadioTransmit ~= false then
        YacaRegisterRdrKeyBind(
            YacaClient.sharedConfig.keyBinds.secondaryRadioTransmit,
            function() self:radioTalkingStart(true, self.secondaryRadioChannel) end,
            function() self:radioTalkingStart(false, self.secondaryRadioChannel) end
        )
    end
end

function YacaRadio:getErrorLevelFromDistance(ownDistanceToTower, senderDistanceToTower)
    local globalErrorLevel = GlobalState[YACA_STATE_GLOBAL_ERROR_LEVEL] or 0

    if self.radioMode == "Tower" then
        local ownSignalStrength = self:calculateSignalStrength(ownDistanceToTower)
        local senderSignalStrength = self:calculateSignalStrength(senderDistanceToTower)
        return math.max(ownSignalStrength, senderSignalStrength, globalErrorLevel)
    elseif self.radioMode == "Direct" then
        local signalStrength = self:calculateSignalStrength(ownDistanceToTower)
        return math.max(signalStrength, globalErrorLevel)
    else
        return globalErrorLevel
    end
end

function YacaRadio:getDistanceToTowerOrSender(senderPosition)
    local ownDistance = math.huge

    if self.radioMode == "Tower" then
        ownDistance = self:getNearestRadioTower()
    elseif self.radioMode == "Direct" then
        local pedPos = GetEntityCoords(YacaCache.ped, false)
        local sx = senderPosition.x or senderPosition[1] or 0
        local sy = senderPosition.y or senderPosition[2] or 0
        local sz = senderPosition.z or senderPosition[3] or 0
        ownDistance = #(pedPos - vector3(sx, sy, sz))
    end

    return ownDistance
end

function YacaRadio:calculateSignalStrength(distance, maxDistance)
    maxDistance = maxDistance or YacaClient.sharedConfig.radioSettings.maxDistance
    local ratio = distance / maxDistance
    return YacaClamp(math.log(1 + ratio * 8.5) / math.log(10), 0, 1)
end

function YacaRadio:getNearestRadioTower()
    local nearestTowerDistance = math.huge
    local playerPos = GetEntityCoords(YacaCache.ped, false)

    if YacaClient.towerConfig and YacaClient.towerConfig.towerPositions then
        for _, coords in ipairs(YacaClient.towerConfig.towerPositions) do
            local distance = #(playerPos - vector3(coords[1], coords[2], coords[3]))
            if distance < nearestTowerDistance then
                nearestTowerDistance = distance
            end
        end
    end

    return nearestTowerDistance
end

function YacaRadio:enableRadio(state)
    if not YacaClient:isPluginInitialized() then return end

    if self.radioEnabled ~= state then
        self.radioEnabled = state
        TriggerServerEvent("server:yaca:enableRadio", state)

        if not state then
            local channelCount = YacaClient.sharedConfig.radioSettings.channelCount
            for i = 1, channelCount do
                self:disableRadioFromPlayerInChannel(i)
            end
        end

        if state and not self.radioInitialized then
            self.radioInitialized = true
            self:initRadioSettings()
            self:updateRadioChannelData(self.activeRadioChannel)
        end

        TriggerEvent("yaca:external:isRadioEnabled", state)
    end
end

function YacaRadio:changeRadioFrequencyRaw(frequency, channel)
    channel = channel or self.activeRadioChannel
    if not YacaClient:isPluginInitialized() then return end
    TriggerServerEvent("server:yaca:changeRadioFrequency", channel, frequency)
end

function YacaRadio:getRadioFrequency(channel)
    channel = channel or self.activeRadioChannel
    local channelData = self.radioChannelSettings[channel]
    if not channelData then return "0" end
    return channelData.frequency
end

function YacaRadio:muteRadioChannel(state)
    self:muteRadioChannelRaw(self.activeRadioChannel, state)
end

function YacaRadio:muteRadioChannelRaw(channel, state)
    channel = channel or self.activeRadioChannel
    if not YacaClient:isPluginInitialized() or not self.radioEnabled then return end

    local channelSettings = self.radioChannelSettings[channel]
    if not channelSettings then return end
    if channelSettings.frequency == "0" then return end

    TriggerServerEvent("server:yaca:muteRadioChannel", channel, state)
end

function YacaRadio:isRadioChannelMuted(channel)
    channel = channel or self.activeRadioChannel
    local channelData = self.radioChannelSettings[channel]
    if not channelData then return true end
    return channelData.muted
end

function YacaRadio:setActiveRadioChannel(channel)
    if not YacaClient:isPluginInitialized() or not self.radioEnabled then return false end
    self.activeRadioChannel = channel
    self:updateRadioChannelData(channel)
    TriggerEvent("yaca:external:changedActiveRadioChannel", channel)
    return true
end

function YacaRadio:setSecondaryRadioChannel(channel)
    if not YacaClient:isPluginInitialized() or not self.radioEnabled then return false end

    if self.secondaryRadioChannel == channel then
        self.secondaryRadioChannel = -1
        YacaClient:notification(YacaLocale("secondary_radio_channel_disabled"), YacaNotificationType.INFO)
    else
        self.secondaryRadioChannel = channel
        YacaClient:notification(YacaLocale("secondary_radio_channel_enabled", channel), YacaNotificationType.INFO)
    end

    TriggerEvent("yaca:external:changedSecondaryRadioChannel", self.secondaryRadioChannel)
    return true
end

function YacaRadio:changeRadioChannelVolume(higher)
    local channel = self.activeRadioChannel
    local radioSettings = self.radioChannelSettings[channel]
    if not radioSettings then return false end

    local oldVolume = radioSettings.volume
    return self:changeRadioChannelVolumeRaw(oldVolume + (higher and 0.17 or -0.17), channel)
end

function YacaRadio:changeRadioChannelVolumeRaw(volume, channel)
    channel = channel or self.activeRadioChannel
    if not YacaClient:isPluginInitialized() or not self.radioEnabled then return false end

    local channelSettings = self.radioChannelSettings[channel]
    if not channelSettings then return false end

    local oldVolume = channelSettings.volume
    channelSettings.volume = YacaClamp(volume, 0, 1)

    if oldVolume == channelSettings.volume then return true end

    if channelSettings.volume == 0 or (oldVolume == 0 and channelSettings.volume > 0) then
        TriggerServerEvent("server:yaca:muteRadioChannel", channel, channelSettings.volume == 0)
    end

    if channelSettings.volume > 0 then
        TriggerEvent("yaca:external:setRadioVolume", channel, channelSettings.volume)
        self:updateRadioChannelData(channel)
    end

    YacaClient:setCommDeviceVolume(YacaFilterEnum.RADIO, channelSettings.volume, channel)
    return true
end

function YacaRadio:getRadioChannelVolume(channel)
    channel = channel or self.activeRadioChannel
    local channelData = self.radioChannelSettings[channel]
    if not channelData then return 0 end
    return channelData.volume
end

function YacaRadio:changeRadioChannelStereo(channel)
    channel = channel or self.activeRadioChannel
    local channelSettings = self.radioChannelSettings[channel]
    if not channelSettings then return false end

    if channelSettings.stereo == YacaStereoMode.STEREO then
        if self:changeRadioChannelStereoRaw(YacaStereoMode.MONO_LEFT, channel) then
            YacaClient:notification(YacaLocale("changed_stereo_mode", channel, YacaLocale("left_ear")), YacaNotificationType.INFO)
            return true
        end
    elseif channelSettings.stereo == YacaStereoMode.MONO_LEFT then
        if self:changeRadioChannelStereoRaw(YacaStereoMode.MONO_RIGHT, channel) then
            YacaClient:notification(YacaLocale("changed_stereo_mode", channel, YacaLocale("right_ear")), YacaNotificationType.INFO)
            return true
        end
    else
        if self:changeRadioChannelStereoRaw(YacaStereoMode.STEREO, channel) then
            YacaClient:notification(YacaLocale("changed_stereo_mode", channel, YacaLocale("both_ears")), YacaNotificationType.INFO)
            return true
        end
    end

    return false
end

function YacaRadio:changeRadioChannelStereoRaw(stereo, channel)
    channel = channel or self.activeRadioChannel
    if not YacaClient:isPluginInitialized() or not self.radioEnabled then return false end

    local channelSettings = self.radioChannelSettings[channel]
    if not channelSettings then return false end

    channelSettings.stereo = stereo
    YacaClient:setCommDeviceStereoMode(YacaFilterEnum.RADIO, stereo, channel)
    TriggerEvent("yaca:external:setRadioChannelStereo", channel, tostring(stereo))

    return true
end

function YacaRadio:getRadioChannelStereo(channel)
    channel = channel or self.activeRadioChannel
    local channelData = self.radioChannelSettings[channel]
    if not channelData then return tostring(YacaStereoMode.STEREO) end
    return tostring(channelData.stereo)
end

function YacaRadio:initRadioSettings()
    local channelCount = YacaClient.sharedConfig.radioSettings.channelCount
    for i = 1, channelCount do
        if not self.radioChannelSettings[i] then
            self.radioChannelSettings[i] = {
                frequency = self.defaultRadioSettings.frequency,
                muted = self.defaultRadioSettings.muted,
                volume = self.defaultRadioSettings.volume,
                stereo = self.defaultRadioSettings.stereo,
            }
        end
        if not self.playersInRadioChannel[i] then
            self.playersInRadioChannel[i] = {}
        end

        local settings = self.radioChannelSettings[i]
        YacaClient:setCommDeviceStereoMode(YacaFilterEnum.RADIO, settings.stereo, i)
        YacaClient:setCommDeviceVolume(YacaFilterEnum.RADIO, settings.volume, i)

        if settings.frequency ~= "0" then
            TriggerServerEvent("server:yaca:changeRadioFrequency", i, settings.frequency)
        end
    end
end

function YacaRadio:radioTalkingStateToPlugin(state, channel)
    local player = YacaClient:getPlayerByID(YacaCache.serverId)
    if not player then return end
    YacaClient:setPlayersCommType(player, YacaFilterEnum.RADIO, state, channel)
end

function YacaRadio:radioTalkingStateToPluginWithWhisper(state, targets, channel)
    local comDeviceTargets = {}
    for _, target in ipairs(targets) do
        local player = YacaClient:getPlayerByID(target)
        if player then
            comDeviceTargets[#comDeviceTargets + 1] = player
        end
    end

    YacaClient:setPlayersCommType(comDeviceTargets, YacaFilterEnum.RADIO, state, channel, nil, CommDeviceMode.SENDER, CommDeviceMode.RECEIVER)
end

function YacaRadio:findRadioChannelByFrequency(frequency)
    for channel, data in pairs(self.radioChannelSettings) do
        if data.frequency == frequency then
            return channel
        end
    end
    return nil
end

function YacaRadio:setRadioFrequency(channel, frequency)
    local channelSettings = self.radioChannelSettings[channel]
    if not channelSettings then return end

    if channelSettings.frequency ~= frequency then
        self:disableRadioFromPlayerInChannel(channel)
    end

    channelSettings.frequency = frequency
    TriggerEvent("yaca:external:setRadioFrequency", channel, frequency)

    if YacaClient.sharedConfig.saltyChatBridge and YacaSaltyChatBridge then
        local saltyFrequency = channelSettings.frequency == "0" and "" or channelSettings.frequency
        TriggerEvent("SaltyChat_RadioChannelChanged", saltyFrequency, channel == 1)
    end
end

function YacaRadio:disableRadioFromPlayerInChannel(channel)
    local players = self.playersInRadioChannel[channel]
    if not players then return end

    local hasPlayers = false
    for _ in pairs(players) do hasPlayers = true break end
    if not hasPlayers then return end

    local targets = {}
    local toRemove = {}
    for playerId in pairs(players) do
        local player = YacaClient:getPlayerByID(playerId)
        if player and player.remoteID then
            targets[#targets + 1] = player
            toRemove[#toRemove + 1] = player.remoteID
        end
    end

    for _, remoteId in ipairs(toRemove) do
        players[remoteId] = nil
    end

    if #targets > 0 then
        YacaClient:setPlayersCommType(targets, YacaFilterEnum.RADIO, false, channel, nil, CommDeviceMode.RECEIVER, CommDeviceMode.SENDER)
    end
end

function YacaRadio:anyChannelTalking()
    for _, talking in pairs(self.talkingInChannels) do
        if talking then return true end
    end
    return false
end

function YacaRadio:startTalkingVisuals()
    local animCfg = YacaClient.sharedConfig.radioSettings.animation
    if animCfg and animCfg.dictionary and animCfg.name then
        if YacaRequestAnimDict(animCfg.dictionary, 1500) then
            TaskPlayAnim(
                YacaCache.ped,
                animCfg.dictionary,
                animCfg.name,
                3, -4, -1,
                animCfg.flag,
                0.0,
                false, false, false
            )
        end
    end

    local propCfg = YacaClient.sharedConfig.radioSettings.propWhileTalking
    if not propCfg or propCfg.prop == false then return end

    local createMode = propCfg.createMode or "stateBag"
    if createMode == "stateBag" then
        LocalPlayer.state:set(YACA_STATE_RADIO_PROP, true, true)
    elseif createMode == "client" then
        if not self.currentRadioProp then
            self.currentRadioProp = YacaCreateProp(
                YacaCache.ped,
                propCfg.prop,
                propCfg.boneId,
                propCfg.position,
                propCfg.rotation,
                true
            )
        end
    end
end

function YacaRadio:stopTalkingVisuals(_channel)
    if self:anyChannelTalking() then return end

    local animCfg = YacaClient.sharedConfig.radioSettings.animation
    if animCfg and animCfg.dictionary and animCfg.name then
        StopAnimTask(YacaCache.ped, animCfg.dictionary, animCfg.name, 4)
        RemoveAnimDict(animCfg.dictionary)
    end

    local propCfg = YacaClient.sharedConfig.radioSettings.propWhileTalking
    if not propCfg then return end

    local createMode = propCfg.createMode or "stateBag"
    if createMode == "stateBag" then
        LocalPlayer.state:set(YACA_STATE_RADIO_PROP, false, true)
    elseif createMode == "client" then
        if self.currentRadioProp then
            if DoesEntityExist(self.currentRadioProp) then
                DeleteEntity(self.currentRadioProp)
            end
            if propCfg.prop ~= false then
                SetModelAsNoLongerNeeded(propCfg.prop)
            end
            self.currentRadioProp = nil
        end
    end
end

function YacaRadio:radioTalkingStart(state, channel)
    state = (state == true)
    channel = tonumber(channel) or channel

    if type(channel) ~= "number" then return end
    if channel == -1 then return end

    if not state then
        if self.talkingInChannels[channel] then
            self.talkingInChannels[channel] = nil
            self.radioTowerCalculation[channel] = nil

            if YacaSaltyChatBridge then
                YacaSaltyChatBridge:handleRadioTalkingStateChange(false, channel)
            end

            if not YacaClient.useWhisper then
                self:radioTalkingStateToPlugin(false, channel)
            end

            TriggerServerEvent("server:yaca:radioTalking", false, channel, -1)
            TriggerEvent("yaca:external:isRadioTalking", false, channel)

            self:stopTalkingVisuals(channel)
        end
        return
    end

    if YacaClient.sharedConfig.radioAntiSpamCooldown then
        if self.radioOnCooldown then return end
        self.radioOnCooldown = true
        SetTimeout(YacaClient.sharedConfig.radioAntiSpamCooldown, function()
            self.radioOnCooldown = false
        end)
    end

    local channelSettings = self.radioChannelSettings[channel]
    if not self.radioEnabled or not channelSettings or channelSettings.frequency == "0" or self.talkingInChannels[channel] then
        return
    end

    self.talkingInChannels[channel] = true
    if not YacaClient.useWhisper then
        self:radioTalkingStateToPlugin(true, channel)
    end

    self:startTalkingVisuals()

    if YacaSaltyChatBridge then
        YacaSaltyChatBridge:handleRadioTalkingStateChange(true, channel)
    end

    self:sendRadioRequestToServer(channel)
    if not self.radioTowerCalculation[channel] then
        self.radioTowerCalculation[channel] = true
        Citizen.CreateThread(function()
            while self.talkingInChannels[channel] do
                Citizen.Wait(1000)
                if self.talkingInChannels[channel] then
                    self:sendRadioRequestToServer(channel)
                end
            end
            self.radioTowerCalculation[channel] = nil
        end)
    end

    TriggerEvent("yaca:external:isRadioTalking", true, channel)
end

function YacaRadio:sendRadioRequestToServer(channel)
    local distanceToTower = self:getNearestRadioTower() or -1
    TriggerServerEvent("server:yaca:radioTalking", true, channel, distanceToTower)
end

function YacaRadio:updateRadioChannelData(channel)
    if channel ~= self.activeRadioChannel or GetResourceState("yaca-ui") ~= "started" then return end
    exports["yaca-ui"]:setRadioChannelData(self.radioChannelSettings[channel])
end

Citizen.CreateThread(function()
    while not YacaClient.sharedConfig do
        Citizen.Wait(100)
    end
    initRadioModule()
end)

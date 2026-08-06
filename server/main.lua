YacaServer = {
    nameSet = {},
    players = {},
    initRetry = {},
    defaultVoiceRange = 1,
    serverConfig = nil,
    sharedConfig = nil,
    towerConfig = nil,
}

local function initializeServer()
    YacaServer.serverConfig = YacaServerConfig
    YacaServer.sharedConfig = YacaSharedConfig
    YacaServer.towerConfig = YacaTowerConfig or { towerPositions = {} }

    YacaInitLocale(YacaServer.sharedConfig.locale)

    if YacaServer.sharedConfig.voiceRange.ranges[YacaServer.sharedConfig.voiceRange.defaultIndex] then
        YacaServer.defaultVoiceRange = YacaServer.sharedConfig.voiceRange.ranges[YacaServer.sharedConfig.voiceRange.defaultIndex]
    else
        YacaServer.defaultVoiceRange = 1
        YacaServer.sharedConfig.voiceRange.ranges = { 1 }
        print("[YaCA] Default voice range is not set correctly in the config.")
    end

    YacaServer:registerExports()
    YacaServer:registerEvents()

    if YacaServer.sharedConfig.saltyChatBridge then
        YacaServerSaltyChatBridge:init()
    end

    if YacaServer.sharedConfig.versionCheck then
        YacaCheckVersion()
    end

    GlobalState:set(YACA_STATE_GLOBAL_ERROR_LEVEL, 0, true)

    print("--> YaCA: Server loaded")
end

function YacaServer:getPlayer(playerId)
    playerId = tonumber(playerId) or playerId
    return self.players[playerId]
end

function YacaServer:startInitRetryLoop(src, force)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player then return end
    force = force == true

    if player.voicePlugin and not force then
        self.initRetry[src] = nil
        return
    end

    if self.initRetry[src] then return end
    self.initRetry[src] = {
        force = force,
    }

    Citizen.CreateThread(function()
        local attempts = 0

        while self.initRetry[src] do
            local retryState = self.initRetry[src]
            local currentPlayer = self.players[src]
            if not currentPlayer then
                break
            end

            if not retryState.force and currentPlayer.voicePlugin then
                break
            end

            self:connect(src)
            attempts = attempts + 1

            if retryState.force and attempts >= 8 then
                break
            end

            if attempts < 10 then
                Citizen.Wait(3000)
            elseif attempts < 25 then
                Citizen.Wait(5000)
            else
                Citizen.Wait(10000)
            end
        end

        self.initRetry[src] = nil
    end)
end

function YacaServer:connectToVoice(src)
    src = tonumber(src) or src

    if self.players[src] then
        self:connect(src)
        self:startInitRetryLoop(src, false)
        return
    end

    local name = YacaGenerateRandomName(src, self.nameSet, self.serverConfig.userNamePattern)
    if not name then
        DropPlayer(tostring(src), "[YaCA] Failed to generate a random name.")
        return
    end

    local playerState = Player(src).state
    playerState:set(YACA_STATE_VOICE_RANGE, self.defaultVoiceRange, true)

    self.players[src] = {
        voiceSettings = {
            voiceFirstConnect = false,
            forceMuted = false,
            ingameName = name,
            mutedOnPhone = false,
            inCallWith = {},
            emittedPhoneSpeaker = {},
        },
        radioSettings = {
            activated = false,
            hasLong = true,
            frequencies = {},
            permittedRadioFrequencies = {},
        },
        voicePlugin = nil,
    }

    self:connect(src)
    self:startInitRetryLoop(src, false)
end

function YacaServer:registerExports()
    exports("isEnabled", function()
        return GetConvarBool("yaca_enabled", true)
    end)

    exports("connectToVoice", function(src) self:connectToVoice(src) end)

    exports("getPlayerAliveStatus", function(playerId)
        return self:getPlayerAliveStatus(playerId)
    end)

    exports("setPlayerAliveStatus", function(playerId, state)
        self:changePlayerAliveStatus(playerId, state)
    end)

    exports("getPlayerVoiceRange", function(playerId)
        return self:getPlayerVoiceRange(playerId)
    end)

    exports("setPlayerVoiceRange", function(playerId, range)
        self:changeVoiceRange(playerId, range)
    end)

    exports("setGlobalErrorLevel", function(errorLevel)
        YacaSetGlobalErrorLevel(errorLevel)
    end)

    exports("getGlobalErrorLevel", function()
        return YacaGetGlobalErrorLevel()
    end)

    exports("setPlayerVolumeModifier", function(playerId, volumeModifier)
        self:setPlayerVolumeModifier(playerId, volumeModifier)
    end)

    exports("getPlayerVolumeModifier", function(playerId)
        local player = self:getPlayer(playerId)
        if not player or not player.voiceSettings then return 1 end
        return player.voiceSettings.volumeModifier or 1
    end)

    exports("getPlayerTeamSpeakUniqueIdentifier", function(playerId)
        local player = self:getPlayer(playerId)
        if not player or not player.voiceSettings then return "" end
        return player.voiceSettings.tsUniqueIdentifier or ""
    end)

    exports("getPlayerIngameName", function(playerId)
        local player = self:getPlayer(playerId)
        if not player then
            print(("[YaCA] Player %d not found."):format(playerId))
            return ""
        end
        if not player.voiceSettings or not player.voiceSettings.ingameName then
            print(("[YaCA] Ingame name not set for player %d."):format(playerId))
            return ""
        end
        return player.voiceSettings.ingameName
    end)
end

function YacaServer:registerEvents()
    AddEventHandler("playerJoining", function(_oldId)
        if not self.sharedConfig.autoConnectOnJoin then return end

        local src = tonumber(source) or source

        SetTimeout(20000, function()
            if not GetPlayerName(tostring(src)) then return end

            local player = self.players[src]
            if not player or not player.voicePlugin then
                self:connectToVoice(src)
            end
        end)
    end)

    AddEventHandler("playerDropped", function(_reason)
        self:handlePlayerDisconnect(source)
    end)

    RegisterNetEvent("server:yaca:nuiReady", function()
        if not self.sharedConfig.autoConnectOnJoin then return end
        self:connectToVoice(source)
    end)

    RegisterNetEvent("server:yaca:addPlayer", function(clientId, tsUniqueIdentifier)
        self:addNewPlayer(source, clientId, tsUniqueIdentifier)
    end)

    RegisterNetEvent("server:yaca:wsReady", function()
        self:playerReconnect(source)
    end)

    RegisterNetEvent("txsv:req:spectate:end", function()
        TriggerClientEvent("client:yaca:txadmin:stopspectate", source)
    end)
end

function YacaServer:handlePlayerDisconnect(src)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player then return end

    self.initRetry[src] = nil

    if player.voiceSettings and player.voiceSettings.ingameName then
        self.nameSet[player.voiceSettings.ingameName] = nil
    end

    if YacaServerRadio then
        for frequency, players in pairs(YacaServerRadio.radioFrequencyMap) do
            players[src] = nil
            local isEmpty = true
            for _ in pairs(players) do isEmpty = false break end
            if isEmpty then
                YacaServerRadio.radioFrequencyMap[frequency] = nil
            end
        end
    end

    if player.voiceSettings and player.voiceSettings.emittedPhoneSpeaker then
        for targetId, emitterTargets in pairs(player.voiceSettings.emittedPhoneSpeaker) do
            local target = self.players[targetId]
            if target and target.voicePlugin then
                local callMemberIds = {}
                for callMemberId in pairs(emitterTargets) do
                    callMemberIds[#callMemberIds + 1] = callMemberId
                end
                YacaTriggerClientEvent("client:yaca:phoneHearAround", callMemberIds, { target.voicePlugin.clientId }, false)
            end
        end
    end

    TriggerClientEvent("client:yaca:disconnect", -1, src)
    self.players[src] = nil
end

function YacaServer:changePlayerAliveStatus(src, alive)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player then return end

    player.voiceSettings.forceMuted = not alive
    TriggerClientEvent("client:yaca:muteTarget", -1, src, not alive)

    if player.voicePlugin then
        player.voicePlugin.forceMuted = not alive
    end
end

function YacaServer:setPlayerVolumeModifier(src, volumeModifier)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player then
        print(YacaLocale("player_not_found", src))
        return
    end

    if type(volumeModifier) ~= "number" then
        print(("[YaCA] Invalid volume modifier for player %s: %s"):format(tostring(src), tostring(volumeModifier)))
        return
    end

    local clampedModifier = YacaClamp(volumeModifier, 0.1, 2)
    player.voiceSettings.volumeModifier = clampedModifier

    if player.voicePlugin then
        player.voicePlugin.volumeModifier = clampedModifier
    end

    TriggerClientEvent("client:yaca:setPlayerVolumeModifier", -1, src, clampedModifier)
end

function YacaServer:getPlayerAliveStatus(playerId)
    playerId = tonumber(playerId) or playerId
    local player = self.players[playerId]
    if not player then return false end
    return player.voiceSettings.forceMuted
end

function YacaServer:playerReconnect(src)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player then return end

    if not player.voiceSettings.voiceFirstConnect then return end

    self:connect(src)
    self:startInitRetryLoop(src, true)
end

function YacaServer:changeVoiceRange(src, range)
    src = tonumber(src) or src
    local playerState = Player(src).state
    playerState:set(YACA_STATE_VOICE_RANGE, range or self.defaultVoiceRange, true)
    TriggerClientEvent("client:yaca:changeVoiceRange", src, range)
end

function YacaServer:getPlayerVoiceRange(playerId)
    playerId = tonumber(playerId) or playerId
    local playerState = Player(playerId).state
    return playerState[YACA_STATE_VOICE_RANGE] or self.defaultVoiceRange
end

function YacaServer:connect(src)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player then
        print(("[YaCA] Missing player data for %d."):format(src))
        return
    end

    player.voiceSettings.voiceFirstConnect = true

    local initObject = {
        suid = self.serverConfig.uniqueServerId,
        chid = self.serverConfig.ingameChannelId,
        deChid = self.serverConfig.defaultChannelId,
        channelPassword = self.serverConfig.ingameChannelPassword,
        ingameName = player.voiceSettings.ingameName,
        useWhisper = self.serverConfig.useWhisper,
        excludeChannels = self.serverConfig.excludeChannels,
    }

    TriggerClientEvent("client:yaca:init", src, initObject)
end

function YacaServer:addNewPlayer(src, clientId, tsUniqueIdentifier)
    src = tonumber(src) or src
    local player = self.players[src]
    if not player or not clientId then return end

    self.initRetry[src] = nil

    if tsUniqueIdentifier and tsUniqueIdentifier ~= "" then
        player.voiceSettings.tsUniqueIdentifier = tsUniqueIdentifier
        TriggerEvent("yaca:external:playerTeamSpeakIdentifier", src, tsUniqueIdentifier)
    end

    player.voicePlugin = {
        playerId = src,
        clientId = clientId,
        forceMuted = player.voiceSettings.forceMuted,
        mutedOnPhone = player.voiceSettings.mutedOnPhone,
        volumeModifier = player.voiceSettings.volumeModifier,
    }

    TriggerClientEvent("client:yaca:addPlayers", -1, player.voicePlugin)

    local allPlayersData = {}
    local activePlayers = GetPlayers()
    for _, playerSource in ipairs(activePlayers) do
        local intPlayerSource = tonumber(playerSource)
        if intPlayerSource and intPlayerSource ~= src then
            local playerServer = self.players[intPlayerSource]
            if playerServer and playerServer.voicePlugin then
                allPlayersData[#allPlayersData + 1] = playerServer.voicePlugin
            end
        end
    end

    TriggerClientEvent("client:yaca:addPlayers", src, allPlayersData)
end

Citizen.CreateThread(function()
    initializeServer()
end)

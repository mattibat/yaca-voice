YacaSharedConfig = {
    -- Enable the version check to get notified about new versions.
    versionCheck = false,
    -- Enable manual or automatic connecting to the voice channel when joining the server.
    autoConnectOnJoin = true,
    -- The build type of the plugin. 0 = release, 1 = develop (develop allows using all yaca plugin version)
    buildType = 0, -- 0 = RELEASE, 1 = DEVELOP
    -- The locale that should be used.
    locale = "de",
    -- The time before the teamspeak client is being unmuted after joining the ingame channel.
    unmuteDelay = 400,
    -- The range in which you can hear the phone speaker when active.
    maxPhoneSpeakerRange = 5,
    -- Choose if players near other players that are in a call, should be heard by the players on the opposite side of the call.
    --
    -- Following options are available:
    -- - false: Disable the feature completely
    -- - true: Enable the feature always
    -- - "PHONE_SPEAKER": Enable the feature only when the player on the phone has the phone speaker enabled.
    phoneHearPlayersNearby = true, -- false | "PHONE_SPEAKER" | true

    -- Choose which notifications should be enabled.
    notifications = {
        -- Enable notifications from ox_lib
        oxLib = true,
        -- Enable notifications from okokNotify
        okoknotify = false,
        -- Enable notifications from GTA (FiveM only)
        gta = false,
        -- Enable notifications from Rdr 2 (RedM only)
        redm = false,
        -- Enable the option to implement a custom notification
        own = false,
    },

    -- Set the default key binds for the plugin, which can be then changed by the player.
    keyBinds = {
        -- The key to increase the voice range
        increaseVoiceRange = "ADD",
        -- The key to decrease the voice range
        decreaseVoiceRange = "SUBTRACT",
        -- The key to transmit on the primary radio
        primaryRadioTransmit = "N",
        -- The key to transmit on the secondary radio
        secondaryRadioTransmit = "CAPITAL",
        -- The key to use the megaphone
        megaphone = "B",
        -- The key to hold additional to change voice range via mousewheel by 1 meter, false to disable that feature
        voiceRangeWithMouseWheel = "LCONTROL",
    },

    radioSettings = {
        -- Customize radio animation
        animation = {
            dictionary = "random@arrests",
            name = "generic_radio_chatter",
            flag = 49,
        },
        propWhileTalking = {
            -- How the prop is created: "stateBag" syncs via state bags, "client" only locally.
            createMode = "stateBag", -- "stateBag" | "client"
            -- The prop that should be shown while talking on the radio.
            prop = false,
            -- The bone that the prop should be attached to.
            boneId = 28422,
            -- The position of the prop.
            position = { 0.0, 0.0, 0.0 },
            -- The rotation of the prop.
            rotation = { 0.0, 0.0, 0.0 },
        },
        -- The maximum amount of radio channels that can be used.
        channelCount = 9,
        -- Choose the mode of the radio system.
        --
        -- Following options are available:
        -- - "Tower": The radio system is based on towers, which means that the range is limited by the distance to the next tower.
        -- - "Direct": The radio system is based on the distance between the players.
        -- - "None": The radio always works no matter the distance.
        mode = "None", -- "None" | "Direct" | "Tower"
        -- The maximum distance between two players or to the tower to be able to hear each other.
        maxDistance = 1000,
    },

    airborne = {
        -- Enable the airborne voice filter for crew in the same aircraft. (FiveM only)
        enabled = false,
        -- Vehicle classes that count as aircraft (15 = Helicopters, 16 = Planes).
        vehicleClasses = { 15, 16 },
    },

    voiceRange = {
        -- The default index which should be used for the voice range when a player joins the server.
        defaultIndex = 2, -- Lua 1-based index (maps to ranges[2] = 3)
        -- The ranges that should be available for the players.
        ranges = { 1, 3, 8, 15, 20, 25, 30, 40 },
        -- Choose if a notification should be sent when the voice range is changed.
        sendNotification = true,
        markerColor = {
            -- Choose if the marker should be enabled.
            enabled = true,
            -- The color of the marker, r = red, g = green, b = blue, a = alpha
            r = 0,
            g = 255,
            b = 0,
            a = 50,
            -- The duration the marker should be shown.
            duration = 1000,
            type = 1,
            rotate = true,
            zOffset = 0,
        },
    },

    megaphone = {
        -- The range of the megaphone.
        range = 30,
        -- Choose if the plugin should automatically detect if the player should be able to use the megaphone in the vehicle. (FiveM only)
        automaticVehicleDetection = true,
        -- The allowed vehicle classes for the megaphone. (FiveM only)
        allowedVehicleClasses = { 18, 19 },
        -- The allowed vehicle models for the megaphone. (FiveM only)
        allowedVehicleModels = { "polmav" },
    },

    -- Choose if the saltyChatBridge should be enabled.
    saltyChatBridge = true,

    mufflingSettings = {
        -- If set to -1, the player voice range is used, all values >= 0 sets the muffling range before it gets completely cut off
        mufflingRange = -1,
        -- Room IDs that should not apply different-room muffling when LOS is blocked.
        whitelistedRoomIds = {},
        vehicleMuffling = {
            -- If set to true, the vehicle muffling feature is enabled. (FiveM only)
            enabled = true,
            -- Whitelist of vehicles that should be not be affected by the vehicle muffling. (FiveM only)
            vehicleWhitelist = {
                "gauntlet6", "draugur", "bodhi2", "vagrant", "outlaw",
                "trophytruck", "ratel", "drifttampa", "sm722", "tornado4",
                "swinger", "locust", "hotring",
            },
        },
        -- The intensities of the muffling. (0 = no muffling, 10 = full muffling)
        intensities = {
            -- The intensity when the players are in different rooms.
            differentRoom = 10,
            -- The intensity when both cars are closed. (FiveM only)
            bothCarsClosed = 10,
            -- The intensity when one car is closed. (FiveM only)
            oneCarClosed = 6,
            -- The intensity of muffling of the megaphone of a player in a different car. (FiveM only)
            megaPhoneInCar = 6,
        },
    },

    -- Cooldown in milliseconds which the player has to wait to use the radio again, defaults to false which disables the feature.
    radioAntiSpamCooldown = false, -- false or number (ms)
    -- When set to true the plugin syncs the talk state via the plugin, instead of the default way via statebags. This imitates the way how saltychat syncs the talk state, but has some drawbacks.
    useLocalLipSync = true,
    -- Filters/effects disabled for the plugin INIT (devices keep working without coloring).
    -- Valid: RADIO, PHONE, PHONE_SPEAKER, PHONE_HISTORICAL, MEGAPHONE, INTERCOM, AIRBORNE, MUFFLE, WATER, ECHO, REVERB
    disabledFilters = {},
}

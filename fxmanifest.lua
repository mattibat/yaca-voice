fx_version 'cerulean'
games { 'gta5', 'rdr3' }
lua54 'yes'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'MineMalox, LuftigerLuca & C0kkie - lua by mattibat'
version '1.0.2'
description 'YACA Voice Integration for FiveM & RedM'

dependencies {
    '/server:7290',
    '/onesync',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/script.js',
}

shared_scripts {
    'config/shared.lua',
    'shared/enums.lua',
    'shared/constants.lua',
    'locales/en.lua',
    'locales/de.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/cache.lua',
    'client/utils.lua',
    'client/websocket.lua',
    'client/main.lua',
    'client/radio.lua',
    'client/phone.lua',
    'client/megaphone.lua',
    'client/intercom.lua',
    'client/bridge_saltychat.lua',
}

server_scripts {
    'config/server.lua',
    'config/towers.lua',
    'server/utils.lua',
    'server/main.lua',
    'server/radio.lua',
    'server/phone.lua',
    'server/megaphone.lua',
    'server/bridge_saltychat.lua',
}

provide 'saltychat'

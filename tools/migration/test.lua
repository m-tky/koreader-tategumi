-- Isolated contract tests, not an on-device migration test.
-- Run from the repository root: luajit tools/migration/test.lua
local device = { model = "kindle", kind = "ota" }
function device:otaModel() return self.model, self.kind end
function device:isDeprecated() return false end
local gettext = setmetatable({ pgettext = function(_, s) return s end }, {
    __call = function(_, s) return s end,
})
local util = {
    arrayAppend = function(t, values) for _, v in ipairs(values) do t[#t+1] = v end end,
    shell_escape = function(t) return table.concat(t, " ") end,
}
local requested_url, command
local manifest = "koreader-kindle-v2026.07.1.targz"
local revision = "v2026.07.1"
local modules = {
    ["device"] = device,
    ["datastorage"] = { getDataDir = function() return "." end },
    ["gettext"] = gettext,
    ["ffi/util"] = { template = function(s) return s end },
    ["util"] = util,
    ["logger"] = { dbg = function() end, warn = function() end },
    ["libs/libkoreader-lfs"] = { attributes = function() return nil end },
    ["version"] = {
        getCurrentRevision = function() return revision end,
        getNormalizedVersion = function(_, s)
            if s:find("2026.07.1", 1, true) then return 1 end
            if s:find("2026.08", 1, true) then return 2 end
            error("Invalid version")
        end,
    },
    ["socketutil"] = { set_timeout = function() end, reset_timeout = function() end },
    ["socket"] = { skip = function(_, ...) return select(2, ...) end },
    ["socket.http"] = { request = function(opts)
        requested_url = opts.url
        return 1, 200, {}, "OK"
    end },
    ["ltn12"] = { sink = { file = function() return function() end end } },
}
for _, name in ipairs({ "ui/bidi", "ui/widget/confirmbox", "ui/widget/infomessage",
    "ui/widget/multiconfirmbox", "ui/network/manager", "ui/uimanager" }) do
    modules[name] = {}
end
for name, value in pairs(modules) do package.loaded[name] = value end
G_reader_settings = {
    readSetting = function(_, key)
        return ({ ota_server = "http://vanilla.invalid/", ota_channel = "nightly" })[key]
    end,
    saveSetting = function() error("Migration must not change saved settings") end,
}
local updater = assert(loadfile("tools/migration/otamanager.lua"))()
local real_open, real_execute = io.open, os.execute
io.open = function()
    return {
        close = function() end,
        lines = function()
            local done = false
            return function()
                if not done then done = true; return "Filename: " .. manifest end
            end
        end,
    }
end
os.execute = function(cmd) command = cmd; return 0 end
local server = "https://github.com/m-tky/koreader-tategumi/releases/latest/download/"
assert(updater:getOTAServer() == server)
assert(updater:getOTAChannel() == "stable")
updater:setOTAChannel("nightly")
updater:setOTAServer("http://vanilla.invalid/")
-- Equal version numbers must still offer switching forks.
local available, installed = updater:checkUpdate()
assert(available == 1 and installed == 1)
assert(requested_url == server .. "koreader-kindle-latest-stable.zsync")
manifest = "koreader-kindle-v2026.08.targz"
assert(updater:checkUpdate() == 2)
revision = "v2026.08"
manifest = "koreader-kindle-v2026.07.1.targz"
assert(updater:checkUpdate() == 1) -- Existing downgrade confirmation remains usable.
updater._buildLocalPackage = function() return 0 end
assert(updater:zsync() == 0)
assert(command:find("-o ./ota/koreader.updated.tar", 1, true))
assert(command:find("-i ./ota/koreader.installed.tar", 1, true))
assert(command:find("-u " .. server, 1, true))
assert(updater:zsync(true) == 0)
assert(not command:find("-i ", 1, true))
for _, kind in ipairs({ "kotasync", "link" }) do
    device.kind = kind
    assert(updater:checkUpdate() == -1)
end
device.model = nil
assert(updater:checkUpdate() == -2)
io.open, os.execute = real_open, real_execute
print("Legacy migration contract tests passed (mocked; no device or network).")

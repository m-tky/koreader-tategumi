--[[--
Auto-detects page progression direction (RTL/LTR) from document metadata and
applies it to the reader view when the user has not made an explicit choice.

Supported sources:
- EPUB: `page-progression-direction` attribute on the OPF `<spine>` element
  (read directly from the archive, independently of the native DOM cache)
- CBZ/CBR/CBT: `<Manga>YesAndRightToLeft</Manga>` inside ComicInfo.xml,
  with `<ReadingDirection>` accepted for compatibility

This module is intentionally separate from ReaderView so that upstream
merges to readerview.lua do not conflict with fork-specific detection logic.
The module runs its onReadSettings *after* ReaderView (registered later), so
view state set by ReaderView is already available.
]]

local BD = require("ui/bidi")
local EventListener = require("ui/widget/eventlistener")
local logger = require("logger")
local Notification = require("ui/widget/notification")
local _ = require("gettext")

local ReaderAutoDirection = EventListener:extend{}
ReaderAutoDirection.DETECTION_VERSION = 3

function ReaderAutoDirection:onReadSettings(config)
    -- inverse_reading_order is serialized for every document on close, even
    -- when it only contains the default value. Only this explicit marker can
    -- distinguish a user override from such an automatically saved default.
    if config:isTrue("page_direction_user_override") then
        logger.dbg("ReaderAutoDirection: preserving explicit user override for", self.document.file)
        return
    end

    local detected_version = tonumber(config:readSetting("direction_auto_detected_version")) or 0
    if detected_version >= self.DETECTION_VERSION then
        logger.dbg("ReaderAutoDirection: current detection already recorded for", self.document.file)
        return
    end

    local has_legacy_detection = config:has("direction_auto_detected")

    -- Global RTL default already in effect – nothing to do.
    if not has_legacy_detection and self.view.inverse_reading_order then
        logger.dbg("ReaderAutoDirection: global RTL default already applies to", self.document.file)
        return
    end

    local ok, PageDirection = pcall(require, "util/page_direction")
    if not ok then return end

    local dir = PageDirection.getDirection(self.document)
    logger.dbg("ReaderAutoDirection: detected", dir, "for", self.document.file)

    -- Mark detection as done regardless of outcome so we don't re-scan on
    -- every open. The version lets corrected detectors revisit only results
    -- produced by an older implementation.
    config:saveSetting("direction_auto_detected", dir or "none")
    config:saveSetting("direction_auto_detected_version", self.DETECTION_VERSION)

    if dir ~= "rtl" then return end

    -- Apply RTL reading order and keep the progress bar in sync.
    -- ReaderView:onReadSettings ran first and set the bar for the non-detected
    -- value; re-apply now to reflect the auto-detected reading order.
    self.view.inverse_reading_order = not BD.mirroredUILayout()
    self.view:refreshPageTurnInput()
    self.view:syncProgressBarDirection()
    Notification:notify(_("RTL page order detected – switching automatically."))
end

return ReaderAutoDirection

local Cache = require("txtautotoc_cache")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Mapper = require("txtautotoc_mapper")
local Notification = require("ui/widget/notification")
local Parser = require("txtautotoc_parser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

local TxtAutoToc = WidgetContainer:extend{
    name = "txtautotoc",
    title = _("TXT Auto TOC"),
    is_doc_only = true,
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copied = {}
    for key, item in pairs(value) do
        copied[key] = deepCopy(item)
    end
    return copied
end

local function readFile(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end

    local content = handle:read("*a")
    handle:close()
    return content
end

function TxtAutoToc:init()
    self.ui.menu:registerToMainMenu(self)
end

function TxtAutoToc:isEnabled()
    return G_reader_settings:readSetting("txtautotoc_enabled", true) ~= false
end

function TxtAutoToc:shouldNotify()
    return G_reader_settings:readSetting("txtautotoc_notify", true) ~= false
end

function TxtAutoToc:getMinHits()
    return G_reader_settings:readSetting("txtautotoc_min_hits", 3)
end

function TxtAutoToc:saveStatus(status)
    self.ui.doc_settings:saveSetting("txtautotoc_last_status", status)
end

function TxtAutoToc:showMessage(text)
    if not self:shouldNotify() then
        return
    end

    UIManager:show(Notification:new{
        text = text,
        timeout = 3,
    })
end

function TxtAutoToc:buildSignature()
    local file = self.ui.document.file
    local mtime = lfs.attributes(file, "modification")
    local size = lfs.attributes(file, "size")
    return Cache.buildSignature(file, mtime, size, Parser.DETECTOR_VERSION)
end

function TxtAutoToc:removeInjectedToc()
    local document = self.ui and self.ui.document
    if document and self.injected_getter and document.getToc == self.injected_getter then
        document.getToc = self.original_getter
    end
    self.injected_getter = nil
    self.original_getter = nil
    self.current_toc = nil
    self.active = false
end

function TxtAutoToc:injectToc(entries)
    local document = self.ui.document
    self.original_getter = self.original_getter or document.getToc
    self.current_toc = deepCopy(entries)
    self.injected_getter = function()
        return deepCopy(self.current_toc)
    end
    document.getToc = self.injected_getter
    self.active = true
end

function TxtAutoToc:refreshToc()
    self.ui:handleEvent(Event:new("UpdateToc"))
end

function TxtAutoToc:shouldHandleDocument()
    if not self.ui or not self.ui.document or not self.ui.doc_settings then
        return false
    end

    if not self.ui.document.is_txt then
        self:removeInjectedToc()
        self:saveStatus("not_txt")
        return false
    end

    if not self:isEnabled() then
        self:removeInjectedToc()
        self:saveStatus("disabled")
        return false
    end

    if self.ui.handmade and self.ui.handmade:isHandmadeTocEnabled() then
        self:removeInjectedToc()
        self:saveStatus("handmade")
        return false
    end

    return true
end

function TxtAutoToc:generateToc(signature)
    local text = readFile(self.ui.document.file)
    if not text then
        self:removeInjectedToc()
        self:saveStatus("file_error")
        return false
    end

    local parsed = Parser.detect(text)
    local mapped = Mapper.map(self.ui.document, parsed.entries or {})

    if not Cache.shouldActivate(mapped, self:getMinHits()) then
        self:removeInjectedToc()
        self:saveStatus("insufficient")
        return false
    end

    Cache.store(self.ui.doc_settings, signature, mapped, "ready", Parser.DETECTOR_VERSION)
    self:injectToc(mapped)
    self:saveStatus("ready")
    self:refreshToc()
    return true
end

function TxtAutoToc:processCurrentBook(force_rebuild)
    if not self:shouldHandleDocument() then
        return false
    end

    local signature = self:buildSignature()
    if not force_rebuild then
        local cached_entries = Cache.load(self.ui.doc_settings, signature, Parser.DETECTOR_VERSION)
        if cached_entries then
            self:injectToc(cached_entries)
            self:saveStatus("ready")
            self:refreshToc()
            return true
        end
    end

    return self:generateToc(signature)
end

function TxtAutoToc:onReaderReady()
    self:processCurrentBook(false)
end

function TxtAutoToc:onUpdateToc()
    if self.active and self.current_toc and self.ui.document.getToc ~= self.injected_getter then
        self.ui.document.getToc = self.injected_getter
    end
end

function TxtAutoToc:onRebuildCurrentBookToc()
    local ok = self:processCurrentBook(true)
    if ok then
        self:showMessage(_("TXT Auto TOC rebuilt"))
    else
        UIManager:show(InfoMessage:new{
            text = _("TXT Auto TOC was not activated for this book."),
        })
    end
end

function TxtAutoToc:onClearCurrentBookCache()
    Cache.clear(self.ui.doc_settings)
    self:removeInjectedToc()
    self:saveStatus("cleared")
    self:refreshToc()
    self:showMessage(_("TXT Auto TOC cache cleared"))
end

function TxtAutoToc:addToMainMenu(menu_items)
    menu_items.txt_auto_toc = {
        text = self.title,
        sub_item_table = {
            {
                text = _("启用自动生成"),
                checked_func = function()
                    return self:isEnabled()
                end,
                callback = function()
                    G_reader_settings:saveSetting("txtautotoc_enabled", not self:isEnabled())
                end,
            },
            {
                text = _("重建当前书籍目录"),
                callback = function()
                    self:onRebuildCurrentBookToc()
                end,
            },
            {
                text = _("清除当前书籍缓存"),
                callback = function()
                    self:onClearCurrentBookCache()
                end,
            },
            {
                text = _("显示通知"),
                checked_func = function()
                    return self:shouldNotify()
                end,
                callback = function()
                    G_reader_settings:saveSetting("txtautotoc_notify", not self:shouldNotify())
                end,
            },
        },
    }
end

return TxtAutoToc

local helpers = require("spec.helpers")
local root = helpers.setupPackagePath()

local function makeDocSettings()
    local values = {}

    return {
        values = values,
        readSetting = function(_, key, default)
            local value = values[key]
            if value == nil then
                return default
            end
            return value
        end,
        saveSetting = function(_, key, value)
            values[key] = value
        end,
        delSetting = function(_, key)
            values[key] = nil
        end,
        isTrue = function(_, key)
            return values[key] == true
        end,
    }
end

local function makeTempTxt(name, content)
    local path = root .. "/" .. name
    local handle = assert(io.open(path, "wb"))
    handle:write(content or "test")
    handle:close()
    return path
end

local function loadPlugin(deps)
    for _, module_name in ipairs({
        "gettext",
        "ui/widget/container/widgetcontainer",
        "ui/uimanager",
        "ui/widget/notification",
        "ui/widget/infomessage",
        "ui/event",
        "logger",
        "libs/libkoreader-lfs",
        "txtautotoc_parser",
        "txtautotoc_mapper",
        "txtautotoc_cache",
    }) do
        package.loaded[module_name] = nil
    end

    local WidgetContainer = {}
    function WidgetContainer:extend(proto)
        proto = proto or {}
        setmetatable(proto, { __index = self })
        self.__index = self
        return proto
    end
    function WidgetContainer:new(proto)
        proto = self:extend(proto)
        if proto.init then
            proto:init()
        end
        return proto
    end

    package.preload["gettext"] = function()
        return function(text)
            return text
        end
    end
    package.preload["ui/widget/container/widgetcontainer"] = function()
        return WidgetContainer
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function() end,
        }
    end
    package.preload["ui/widget/notification"] = function()
        return {
            new = function(_, args)
                return args
            end,
        }
    end
    package.preload["ui/widget/infomessage"] = function()
        return {
            new = function(_, args)
                return args
            end,
        }
    end
    package.preload["ui/event"] = function()
        return {
            new = function(_, name, ...)
                return { name = name, args = { ... } }
            end,
        }
    end
    package.preload["logger"] = function()
        return {
            dbg = function() end,
            warn = function() end,
            err = function() end,
        }
    end
    package.preload["libs/libkoreader-lfs"] = function()
        return {
            attributes = function(path, key)
                local attrs = deps.file_attrs[path] or {}
                return attrs[key]
            end,
        }
    end
    package.preload["txtautotoc_parser"] = function()
        return deps.parser
    end
    package.preload["txtautotoc_mapper"] = function()
        return deps.mapper
    end
    package.preload["txtautotoc_cache"] = function()
        return deps.cache
    end

    _G.G_reader_settings = deps.reader_settings

    return dofile(root .. "/txtautotoc.koplugin/main.lua")
end

local function makeUI(doc_settings, document, handmade_enabled)
    local events = {}
    local ui = {}
    ui.menu = {
        registerToMainMenu = function(_, plugin)
            ui.registered_plugin = plugin
        end,
    }
    ui.document = document
    ui.doc_settings = doc_settings
    ui.handmade = {
        isHandmadeTocEnabled = function()
            return handmade_enabled
        end,
    }
    ui.handleEvent = function(_, event)
        table.insert(events, event.name)
    end
    ui.events = events
    return ui
end

do
    local parser_called = false
    local file = makeTempTxt("spec-main-handmade.txt", "第1章\n第2章\n第3章\n")
    local cache = {
        buildSignature = function() return "sig" end,
        load = function() return nil end,
        store = function() end,
        shouldActivate = function() return true end,
        clear = function() end,
    }
    local Plugin = loadPlugin({
        file_attrs = {
            [file] = { modification = 1700000000, size = 4096 },
        },
        reader_settings = {
            readSetting = function(_, _, default) return default end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function()
                parser_called = true
                return { entries = {} }
            end,
        },
        mapper = {
            map = function()
                return {}
            end,
        },
        cache = cache,
    })

    local doc_settings = makeDocSettings()
    local document = {
        is_txt = true,
        file = file,
        getToc = function()
            return { { title = "native" } }
        end,
    }
    local plugin = Plugin:new({
        ui = makeUI(doc_settings, document, true),
    })

    plugin:onReaderReady()

    helpers.assertFalsy(parser_called, "should not scan when handmade toc is already enabled")
    helpers.assertEquals(doc_settings.values.txtautotoc_last_status, "handmade", "should record handmade override status")
    helpers.assertEquals(document.getToc()[1].title, "native", "should preserve the native toc getter")
    os.remove(file)
end

do
    local stored_entries
    local parser_calls = 0
    local mapper_calls = 0
    local file = makeTempTxt("spec-main-generate.txt", "第1章\n第2章\n第3章\n")
    local cache = {
        buildSignature = function() return "sig" end,
        load = function() return nil end,
        store = function(_, _, entries, status)
            stored_entries = { entries = entries, status = status }
        end,
        shouldActivate = function(entries, min_hits)
            return #entries >= min_hits
        end,
        clear = function() end,
    }
    local Plugin = loadPlugin({
        file_attrs = {
            [file] = { modification = 1700000000, size = 4096 },
        },
        reader_settings = {
            readSetting = function(_, key, default)
                if key == "txtautotoc_min_hits" then
                    return 3
                end
                return default
            end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function()
                parser_calls = parser_calls + 1
                return {
                    entries = {
                        { title = "第1章", search_term = "第1章", depth = 1 },
                        { title = "第2章", search_term = "第2章", depth = 1 },
                        { title = "第3章", search_term = "第3章", depth = 1 },
                    },
                }
            end,
        },
        mapper = {
            map = function(_, entries)
                mapper_calls = mapper_calls + 1
                for index, entry in ipairs(entries) do
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                    entry.page = index
                end
                return entries
            end,
        },
        cache = cache,
    })

    local doc_settings = makeDocSettings()
    local document = {
        is_txt = true,
        file = file,
        getToc = function()
            return {}
        end,
    }
    local ui = makeUI(doc_settings, document, false)
    local plugin = Plugin:new({
        ui = ui,
    })

    plugin:onReaderReady()

    helpers.assertEquals(parser_calls, 1, "should parse the txt file on first open")
    helpers.assertEquals(mapper_calls, 1, "should map parser results into xpointer toc entries")
    helpers.assertEquals(stored_entries.status, "ready", "should cache ready toc entries")
    helpers.assertTableLength(document.getToc(), 3, "should inject the generated toc into the default toc entrypoint")
    helpers.assertEquals(ui.events[1], "UpdateToc", "should notify KOReader to refresh the toc view")
    os.remove(file)
end

do
    local parser_called = false
    local mapper_called = false
    local file = makeTempTxt("spec-main-cache.txt", "第1章\n第2章\n第3章\n")
    local cached_entries = {
        { title = "第1章", depth = 1, xpointer = "/body/DocFragment[1]", page = 1 },
        { title = "第2章", depth = 1, xpointer = "/body/DocFragment[2]", page = 2 },
        { title = "第3章", depth = 1, xpointer = "/body/DocFragment[3]", page = 3 },
    }
    local Plugin = loadPlugin({
        file_attrs = {
            [file] = { modification = 1700000000, size = 4096 },
        },
        reader_settings = {
            readSetting = function(_, _, default) return default end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function()
                parser_called = true
            end,
        },
        mapper = {
            map = function()
                mapper_called = true
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function()
                return cached_entries, "ready"
            end,
            store = function() end,
            shouldActivate = function() return true end,
            clear = function() end,
        },
    })

    local doc_settings = makeDocSettings()
    local document = {
        is_txt = true,
        file = file,
        getToc = function()
            return {}
        end,
    }
    local plugin = Plugin:new({
        ui = makeUI(doc_settings, document, false),
    })

    plugin:onReaderReady()

    helpers.assertFalsy(parser_called, "should skip parsing on cache hit")
    helpers.assertFalsy(mapper_called, "should skip mapping on cache hit")
    helpers.assertTableLength(document.getToc(), 3, "should inject cached toc entries")
    os.remove(file)
end

do
    local file = makeTempTxt("spec-main-insufficient.txt", "第1章\n第2章\n")
    local Plugin = loadPlugin({
        file_attrs = {
            [file] = { modification = 1700000000, size = 4096 },
        },
        reader_settings = {
            readSetting = function(_, key, default)
                if key == "txtautotoc_min_hits" then
                    return 3
                end
                return default
            end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function()
                return {
                    entries = {
                        { title = "第1章", search_term = "第1章", depth = 1 },
                        { title = "第2章", search_term = "第2章", depth = 1 },
                    },
                }
            end,
        },
        mapper = {
            map = function(_, entries)
                for index, entry in ipairs(entries) do
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                    entry.page = index
                end
                return entries
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function()
                return nil
            end,
            store = function() end,
            shouldActivate = function(entries, min_hits)
                return #entries >= min_hits
            end,
            clear = function() end,
        },
    })

    local doc_settings = makeDocSettings()
    local document = {
        is_txt = true,
        file = file,
        getToc = function()
            return { { title = "native" } }
        end,
    }
    local plugin = Plugin:new({
        ui = makeUI(doc_settings, document, false),
    })

    plugin:onReaderReady()

    helpers.assertEquals(doc_settings.values.txtautotoc_last_status, "insufficient", "should record insufficient-hit status")
    helpers.assertEquals(document.getToc()[1].title, "native", "should keep the native toc when too few headings were mapped")
    os.remove(file)
end

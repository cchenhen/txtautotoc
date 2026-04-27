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
        "ui/widget/progressbardialog",
        "ui/event",
        "logger",
        "libs/libkoreader-lfs",
        "txtautotoc_parser",
        "txtautotoc_reader",
        "txtautotoc_mapper",
        "txtautotoc_cache",
    }) do
        package.loaded[module_name] = nil
        package.preload[module_name] = nil
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
    if not deps.omit_progressbar_dialog then
        package.preload["ui/widget/progressbardialog"] = function()
            return deps.progressbar_dialog or {
                new = function(_, args)
                    args.reportProgress = function() end
                    args.show = function() end
                    args.close = function() end
                    return args
                end,
            }
        end
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
    package.preload["txtautotoc_reader"] = function()
        if deps.reader then
            return deps.reader
        end

        return {
            readFile = function(path)
                local handle = io.open(path, "rb")
                if not handle then
                    return nil
                end
                local content = handle:read("*a")
                handle:close()
                return content, "utf-8"
            end,
        }
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
    local ok, result = pcall(loadPlugin, {
        omit_progressbar_dialog = true,
        file_attrs = {},
        reader_settings = {
            readSetting = function(_, _, default) return default end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function()
                return { entries = {} }
            end,
        },
        mapper = {
            map = function()
                return {}
            end,
            mapFast = function()
                return {}
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function() return nil end,
            store = function() end,
            shouldActivate = function() return false end,
            clear = function() end,
        },
    })

    helpers.assertTruthy(ok, "plugin should load on KOReader builds without progressbardialog: " .. tostring(result))
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
    local parser_text
    local stored_entries
    local file = makeTempTxt("spec-main-reader.txt", "raw file bytes")
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
        reader = {
            readFile = function()
                return "第1章\n第2章\n第3章\n", "gb18030"
            end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function(text)
                parser_text = text
                return {
                    entries = {
                        { title = "第1章", search_term = "第1章", depth = 1, line_number = 1 },
                        { title = "第2章", search_term = "第2章", depth = 1, line_number = 2 },
                        { title = "第3章", search_term = "第3章", depth = 1, line_number = 3 },
                    },
                    total_lines = 3,
                }
            end,
        },
        mapper = {
            map = function(_, entries)
                return entries
            end,
            mapBatched = function(_, entries)
                for index, entry in ipairs(entries) do
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                    entry.page = index
                end
                return entries
            end,
            mapFast = function(_, entries)
                return entries
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function() return nil end,
            store = function(_, _, entries)
                stored_entries = entries
            end,
            shouldActivate = function(entries, min_hits) return #entries >= min_hits end,
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

    helpers.assertEquals(parser_text, "第1章\n第2章\n第3章\n", "plugin should parse text returned by reader compatibility layer")
    helpers.assertEquals(doc_settings.values.txtautotoc_last_encoding, "gb18030", "plugin should record the detected reader encoding")
    helpers.assertTableLength(stored_entries, 3, "reader-decoded text should still be cached after mapping")
    os.remove(file)
end

do
    local stored_entries
    local parser_calls = 0
    local exact_mapper_calls = 0
    local fast_mapper_calls = 0
    local batched_mapper_calls = 0
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
                        { title = "第1章", search_term = "第1章", depth = 1, line_number = 1 },
                        { title = "第2章", search_term = "第2章", depth = 1, line_number = 2 },
                        { title = "第3章", search_term = "第3章", depth = 1, line_number = 3 },
                    },
                    total_lines = 3,
                }
            end,
        },
        mapper = {
            map = function(_, entries)
                exact_mapper_calls = exact_mapper_calls + 1
                return entries
            end,
            mapBatched = function(_, entries)
                batched_mapper_calls = batched_mapper_calls + 1
                for index, entry in ipairs(entries) do
                    entry.xpointer = "/body/DocFragment[" .. (index * 10) .. "]"
                    entry.page = index * 10
                end
                return entries
            end,
            mapFast = function(_, entries)
                fast_mapper_calls = fast_mapper_calls + 1
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
    helpers.assertEquals(batched_mapper_calls, 1, "reader startup should use batched exact mapping for accurate jumps")
    helpers.assertEquals(fast_mapper_calls, 0, "reader startup should not use fast mapping when exact mapping succeeds")
    helpers.assertEquals(exact_mapper_calls, 0, "reader startup should not run exact fulltext mapping")
    helpers.assertEquals(stored_entries.status, "ready", "should cache ready toc entries")
    helpers.assertEquals(stored_entries.entries[1].xpointer, "/body/DocFragment[10]", "cached startup toc should use exact title xpointer")
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
    local parser_called = false
    local fast_mapper_called = false
    local exact_mapper_called = false
    local batched_mapper_called = false
    local file = makeTempTxt("spec-main-large-file.txt", "第1章\n第2章\n第3章\n")
    local Plugin = loadPlugin({
        file_attrs = {
            [file] = { modification = 1700000000, size = 2 * 1024 * 1024 },
        },
        reader_settings = {
            readSetting = function(_, _, default) return default end,
        },
        parser = {
            DETECTOR_VERSION = 1,
            detect = function()
                parser_called = true
                return {
                    entries = {
                        { title = "第1章", depth = 1, line_number = 1 },
                        { title = "第2章", depth = 1, line_number = 2 },
                        { title = "第3章", depth = 1, line_number = 3 },
                    },
                    total_lines = 3,
                }
            end,
        },
        mapper = {
            map = function()
                exact_mapper_called = true
                return {}
            end,
            mapBatched = function(_, entries)
                batched_mapper_called = true
                for index, entry in ipairs(entries) do
                    entry.page = index * 10
                    entry.xpointer = "/body/DocFragment[" .. (index * 10) .. "]"
                end
                return entries
            end,
            mapFast = function(_, entries)
                fast_mapper_called = true
                for index, entry in ipairs(entries) do
                    entry.page = index
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                end
                return entries
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function() return nil end,
            store = function() end,
            shouldActivate = function(entries, min_hits) return #entries >= min_hits end,
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

    helpers.assertTruthy(parser_called, "large uncached txt files should still be parsed for fast auto generation")
    helpers.assertTruthy(batched_mapper_called, "large uncached txt files should use batched exact auto mapping")
    helpers.assertFalsy(fast_mapper_called, "large uncached txt files should not use fast auto mapping when exact mapping succeeds")
    helpers.assertFalsy(exact_mapper_called, "large uncached txt files should not run exact fulltext mapping during reader startup")
    helpers.assertEquals(doc_settings.values.txtautotoc_last_status, "ready", "should record ready status for fast-generated large files")
    helpers.assertTableLength(document.getToc(), 3, "should inject fast-generated toc for large files")
    os.remove(file)
end

do
    local fast_mapper_called = false
    local exact_mapper_called = false
    local batched_mapper_called = false
    local file = makeTempTxt("spec-main-too-many-candidates.txt", "第1章\n第2章\n第3章\n")
    local many_entries = {}
    for index = 1, 81 do
        many_entries[index] = {
            title = "第" .. index .. "章",
            search_term = "第" .. index .. "章",
            depth = 1,
        }
    end
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
                return { entries = many_entries }
            end,
        },
        mapper = {
            map = function()
                exact_mapper_called = true
                return {}
            end,
            mapBatched = function(_, entries)
                batched_mapper_called = true
                for index, entry in ipairs(entries) do
                    entry.page = index
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                end
                return entries
            end,
            mapFast = function(_, entries)
                fast_mapper_called = true
                for index, entry in ipairs(entries) do
                    entry.page = index
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                end
                return entries
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function() return nil end,
            store = function() end,
            shouldActivate = function(entries, min_hits) return #entries >= min_hits end,
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

    helpers.assertTruthy(batched_mapper_called, "many candidates should use batched exact auto mapping")
    helpers.assertFalsy(fast_mapper_called, "many candidates should not use fast auto mapping when exact mapping succeeds")
    helpers.assertFalsy(exact_mapper_called, "many candidates should not run exact fulltext mapping during reader startup")
    helpers.assertEquals(doc_settings.values.txtautotoc_last_status, "ready", "should record ready status for fast-generated many-candidate files")
    helpers.assertTableLength(document.getToc(), 81, "should inject fast-generated toc for many-candidate files")
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
                return entries
            end,
            mapFast = function(_, entries)
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

do
    local fast_mapper_called = false
    local file = makeTempTxt("spec-main-exact-fallback.txt", "第1章\n第2章\n第3章\n")
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
                        { title = "第1章", search_term = "第1章", depth = 1, line_number = 1 },
                        { title = "第2章", search_term = "第2章", depth = 1, line_number = 2 },
                        { title = "第3章", search_term = "第3章", depth = 1, line_number = 3 },
                    },
                    total_lines = 3,
                }
            end,
        },
        mapper = {
            map = function()
                return {}
            end,
            mapBatched = function()
                return {
                    { title = "第1章", depth = 1, page = 1, xpointer = "/body/DocFragment[1]" },
                }
            end,
            mapFast = function(_, entries)
                fast_mapper_called = true
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
            return {}
        end,
    }
    local plugin = Plugin:new({
        ui = makeUI(doc_settings, document, false),
    })

    plugin:onReaderReady()

    helpers.assertTruthy(fast_mapper_called, "startup should fall back to fast mapping when batched exact mapping is insufficient")
    helpers.assertEquals(doc_settings.values.txtautotoc_last_status, "fast", "should record fast status when falling back to estimated toc")
    helpers.assertTableLength(document.getToc(), 3, "fallback should still inject a usable toc")
    os.remove(file)
end

do
    local progress_values = {}
    local dialog_shown = false
    local dialog_closed = false
    local exact_mapper_options
    local file = makeTempTxt("spec-main-manual-progress.txt", "第1章\n第2章\n第3章\n")
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
                        { title = "第1章", search_term = "第1章", depth = 1, line_number = 1 },
                        { title = "第2章", search_term = "第2章", depth = 1, line_number = 2 },
                        { title = "第3章", search_term = "第3章", depth = 1, line_number = 3 },
                    },
                    total_lines = 3,
                }
            end,
        },
        mapper = {
            map = function(_, entries, options)
                exact_mapper_options = options
                for index, entry in ipairs(entries) do
                    options.progress_callback(index, #entries, entry)
                    entry.xpointer = "/body/DocFragment[" .. index .. "]"
                    entry.page = index
                end
                return entries
            end,
            mapFast = function()
                return {}
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function() return nil end,
            store = function() end,
            shouldActivate = function(entries, min_hits) return #entries >= min_hits end,
            clear = function() end,
        },
        progressbar_dialog = {
            new = function(_, args)
                helpers.assertEquals(args.progress_max, 3, "manual rebuild progress should know the candidate count")
                args.reportProgress = function(_, value)
                    table.insert(progress_values, value)
                end
                args.show = function()
                    dialog_shown = true
                end
                args.close = function()
                    dialog_closed = true
                end
                return args
            end,
        },
    })

    local plugin = Plugin:new({
        ui = makeUI(makeDocSettings(), {
            is_txt = true,
            file = file,
            getToc = function()
                return {}
            end,
        }, false),
    })

    plugin:onRebuildCurrentBookToc()

    helpers.assertTruthy(dialog_shown, "manual rebuild should show a progress dialog")
    helpers.assertTruthy(dialog_closed, "manual rebuild should close the progress dialog")
    helpers.assertTruthy(exact_mapper_options and exact_mapper_options.progress_callback, "manual rebuild should pass progress callback to exact mapper")
    helpers.assertEquals(progress_values[1], 1, "manual rebuild should report first progress value")
    helpers.assertEquals(progress_values[3], 3, "manual rebuild should report final progress value")
    os.remove(file)
end

do
    local file = makeTempTxt("spec-main-menu.txt", "第1章\n第2章\n第3章\n")
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
                return { entries = {} }
            end,
        },
        mapper = {
            map = function()
                return {}
            end,
        },
        cache = {
            buildSignature = function() return "sig" end,
            load = function() return nil end,
            store = function() end,
            shouldActivate = function() return false end,
            clear = function() end,
        },
    })

    local plugin = Plugin:new({
        ui = makeUI(makeDocSettings(), {
            is_txt = true,
            file = file,
            getToc = function()
                return {}
            end,
        }, false),
    })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)

    helpers.assertEquals(menu_items.txt_auto_toc.text, "TXT 自动目录", "should show Chinese label for the plugin menu")
    helpers.assertEquals(menu_items.txt_auto_toc.sub_item_table[1].text, "启用自动生成", "should show Chinese label for auto generation")
    helpers.assertEquals(menu_items.txt_auto_toc.sub_item_table[2].text, "打开时精确定位", "should show Chinese label for automatic exact mapping")
    helpers.assertEquals(menu_items.txt_auto_toc.sub_item_table[3].text, "立即生成/重建目录", "should show Chinese label for rebuild")
    helpers.assertEquals(menu_items.txt_auto_toc.sub_item_table[4].text, "清除当前书籍缓存", "should show Chinese label for cache clearing")
    helpers.assertEquals(menu_items.txt_auto_toc.sub_item_table[5].text, "显示通知", "should show Chinese label for notifications")
    os.remove(file)
end

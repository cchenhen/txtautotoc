local helpers = require("spec.helpers")
helpers.setupPackagePath()

local Cache = require("txtautotoc_cache")

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
    }
end

do
    local doc_settings = makeDocSettings()
    local entries = {
        { title = "第1章 少年下山", depth = 1, xpointer = "/body/DocFragment[12]" },
        { title = "第2章 初入长安", depth = 1, xpointer = "/body/DocFragment[24]" },
        { title = "尾声", depth = 1, xpointer = "/body/DocFragment[89]" },
    }
    local signature = Cache.buildSignature("/books/demo.txt", 1700000000, 8192, 1)

    Cache.store(doc_settings, signature, entries, "ready")

    local cached_entries, status = Cache.load(doc_settings, signature, 1)
    helpers.assertTableLength(cached_entries, 3, "should load cached toc when signature matches")
    helpers.assertEquals(status, "ready", "should preserve last status")
end

do
    local doc_settings = makeDocSettings()
    local signature = Cache.buildSignature("/books/demo.txt", 1700000000, 8192, 1)
    Cache.store(doc_settings, signature, {
        { title = "第1章", depth = 1, xpointer = "/body/DocFragment[1]" },
    }, "ready")

    local cached_entries = Cache.load(doc_settings, Cache.buildSignature("/books/demo.txt", 1700000001, 8192, 1), 1)
    helpers.assertFalsy(cached_entries, "should invalidate cache when the document signature changes")
end

do
    local doc_settings = makeDocSettings()
    local signature = Cache.buildSignature("/books/demo.txt", 1700000000, 8192, 1)
    Cache.store(doc_settings, signature, {
        { title = "第1章", depth = 1, xpointer = "/body/DocFragment[1]" },
    }, "ready")
    doc_settings:saveSetting("txtautotoc_last_encoding", "gb18030")
    Cache.clear(doc_settings)

    helpers.assertFalsy(doc_settings.values.txtautotoc_cache, "clear should remove cached toc")
    helpers.assertFalsy(doc_settings.values.txtautotoc_cache_signature, "clear should remove signature")
    helpers.assertFalsy(doc_settings.values.txtautotoc_cache_version, "clear should remove cache version")
    helpers.assertFalsy(doc_settings.values.txtautotoc_last_encoding, "clear should remove last reader encoding")
end

do
    helpers.assertFalsy(Cache.shouldActivate({
        { title = "第1章", xpointer = "/1" },
        { title = "第2章", xpointer = "/2" },
    }, 3), "should refuse activation below the minimum hit threshold")

    helpers.assertTruthy(Cache.shouldActivate({
        { title = "第1章", xpointer = "/1" },
        { title = "第2章", xpointer = "/2" },
        { title = "第3章", xpointer = "/3" },
    }, 3), "should activate when the minimum hit threshold is met")
end

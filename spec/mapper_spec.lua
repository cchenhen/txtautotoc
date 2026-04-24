local helpers = require("spec.helpers")
helpers.setupPackagePath()

local Mapper = require("txtautotoc_mapper")

local function makeDocument(search_results, page_map)
    local document = {
        requested_terms = {},
    }

    function document:findAllText(term)
        table.insert(self.requested_terms, term)
        return search_results[term]
    end

    function document:getPageFromXPointer(xpointer)
        return page_map[xpointer]
    end

    function document:compareXPointers(left, right)
        local lnum = tonumber(left:match("(%d+)%]$"))
        local rnum = tonumber(right:match("(%d+)%]$"))
        if lnum == rnum then
            return 0
        end
        return lnum > rnum and -1 or 1
    end

    return document
end

do
    local document = makeDocument({
        ["第一卷 江湖夜雨"] = {
            { start = "/body/DocFragment[5]", ["end"] = "/body/DocFragment[6]" },
        },
        ["第1章 少年下山"] = {
            { start = "/body/DocFragment[20]", ["end"] = "/body/DocFragment[21]" },
        },
        ["第2章 初入长安"] = {
            { start = "/body/DocFragment[18]", ["end"] = "/body/DocFragment[19]" },
            { start = "/body/DocFragment[40]", ["end"] = "/body/DocFragment[41]" },
        },
        ["尾声"] = {
            { start = "/body/DocFragment[90]", ["end"] = "/body/DocFragment[91]" },
        },
    }, {
        ["/body/DocFragment[5]"] = 1,
        ["/body/DocFragment[20]"] = 5,
        ["/body/DocFragment[40]"] = 8,
        ["/body/DocFragment[90]"] = 20,
    })

    local mapped = Mapper.map(document, {
        { title = "第一卷 江湖夜雨", search_term = "第一卷 江湖夜雨", depth = 1 },
        { title = "第1章 少年下山", search_term = "第1章 少年下山", depth = 2 },
        { title = "第2章 初入长安", search_term = "第2章 初入长安", depth = 2 },
        { title = "尾声", search_term = "尾声", depth = 1 },
    })

    helpers.assertTableLength(mapped, 4, "should map headings in monotonically increasing order")
    helpers.assertEquals(mapped[3].xpointer, "/body/DocFragment[40]", "should skip stale matches before the previous chapter")
    helpers.assertEquals(mapped[3].page, 8, "should attach page numbers to mapped entries")
end

do
    local document = makeDocument({
        ["第1章"] = {
            { start = "/body/DocFragment[20]", ["end"] = "/body/DocFragment[21]" },
        },
        ["第2章"] = {
            { start = "/body/DocFragment[20]", ["end"] = "/body/DocFragment[21]" },
            { start = "/body/DocFragment[30]", ["end"] = "/body/DocFragment[31]" },
        },
        ["第3章"] = nil,
    }, {
        ["/body/DocFragment[20]"] = 5,
        ["/body/DocFragment[30]"] = 7,
    })

    local mapped = Mapper.map(document, {
        { title = "第1章", search_term = "第1章", depth = 1 },
        { title = "第2章", search_term = "第2章", depth = 1 },
        { title = "第3章", search_term = "第3章", depth = 1 },
    })

    helpers.assertTableLength(mapped, 2, "should drop duplicate and missing matches")
    helpers.assertEquals(mapped[2].xpointer, "/body/DocFragment[30]", "should use the next valid xpointer after a duplicate hit")
end

do
    local find_all_called = false
    local document = {
        getPageCount = function()
            return 100
        end,
        getPageXPointer = function(_, page)
            return "/body/DocFragment[" .. page .. "]"
        end,
        findAllText = function()
            find_all_called = true
            return {}
        end,
    }

    local mapped = Mapper.mapFast(document, {
        { title = "第1章", depth = 1, line_number = 1 },
        { title = "第2章", depth = 1, line_number = 51 },
        { title = "尾声", depth = 1, line_number = 101 },
    }, 101)

    helpers.assertFalsy(find_all_called, "fast mapping should not call fulltext search")
    helpers.assertTableLength(mapped, 3, "fast mapping should keep all detected toc entries")
    helpers.assertEquals(mapped[1].page, 1, "first heading should map to the first page")
    helpers.assertEquals(mapped[2].page, 50, "middle heading should map by line ratio")
    helpers.assertEquals(mapped[3].page, 100, "last heading should map to the last page")
    helpers.assertEquals(mapped[2].xpointer, "/body/DocFragment[50]", "fast mapping should attach page xpointers when available")
end

do
    local progress = {}
    local document = makeDocument({
        ["第1章"] = {
            { start = "/body/DocFragment[10]", ["end"] = "/body/DocFragment[11]" },
        },
        ["第2章"] = {
            { start = "/body/DocFragment[20]", ["end"] = "/body/DocFragment[21]" },
        },
    }, {
        ["/body/DocFragment[10]"] = 1,
        ["/body/DocFragment[20]"] = 2,
    })

    local mapped = Mapper.map(document, {
        { title = "第1章", search_term = "第1章", depth = 1 },
        { title = "第2章", search_term = "第2章", depth = 1 },
    }, {
        progress_callback = function(current, total)
            table.insert(progress, current .. "/" .. total)
        end,
    })

    helpers.assertTableLength(mapped, 2, "exact mapping should still map all entries")
    helpers.assertEquals(progress[1], "1/2", "exact mapping should report first progress step")
    helpers.assertEquals(progress[2], "2/2", "exact mapping should report final progress step")
end

do
    local regex_calls = {}
    local document = {
        getPageXPointer = function()
            error("batched exact mapping must not use page-top xpointers")
        end,
        findAllText = function(_, pattern, case_insensitive, nb_context_words, max_hits, regex)
            table.insert(regex_calls, {
                pattern = pattern,
                case_insensitive = case_insensitive,
                nb_context_words = nb_context_words,
                max_hits = max_hits,
                regex = regex,
            })
            return {
                { start = "/body/DocFragment[10]", matched_text = "第1章 精确标题" },
                { start = "/body/DocFragment[30]", matched_text = "第2章 精确标题" },
                { start = "/body/DocFragment[50]", matched_text = "第3章 精确标题" },
                { start = "/body/DocFragment[70]", matched_text = "第4章 终章 (test)??" },
            }
        end,
        getPageFromXPointer = function(_, xpointer)
            return tonumber(xpointer:match("(%d+)%]$"))
        end,
        compareXPointers = function(_, left, right)
            local lnum = tonumber(left:match("(%d+)%]$"))
            local rnum = tonumber(right:match("(%d+)%]$"))
            if lnum == rnum then
                return 0
            end
            return lnum > rnum and -1 or 1
        end,
    }

    local mapped = Mapper.mapBatched(document, {
        { title = "第1章 精确标题", search_term = "第1章 精确标题", depth = 1 },
        { title = "第2章 精确标题", search_term = "第2章 精确标题", depth = 1 },
        { title = "第3章 精确标题", search_term = "第3章 精确标题", depth = 1 },
        { title = "第4章 终章 (test)??", search_term = "第4章 终章 (test)??", depth = 1 },
    }, {
        chunk_size = 2,
    })

    helpers.assertTableLength(regex_calls, 2, "batched exact mapping should search headings in chunks")
    helpers.assertTruthy(regex_calls[1].regex, "batched exact mapping should use regex alternation")
    helpers.assertTruthy(regex_calls[2].pattern:find("\\(test\\)", 1, true), "batched exact mapping should escape regex parentheses")
    helpers.assertTruthy(regex_calls[2].pattern:find("\\?\\?", 1, true), "batched exact mapping should escape regex question marks")
    helpers.assertTableLength(mapped, 4, "batched exact mapping should keep all exact matches")
    helpers.assertEquals(mapped[1].xpointer, "/body/DocFragment[10]", "batched exact mapping should use matched title xpointer")
    helpers.assertEquals(mapped[2].page, 30, "batched exact mapping should attach page from exact xpointer")
end

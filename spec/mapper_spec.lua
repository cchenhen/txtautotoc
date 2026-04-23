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

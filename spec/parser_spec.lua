local helpers = require("spec.helpers")
helpers.setupPackagePath()

local Parser = require("txtautotoc_parser")

local function assertEntry(entry, expected)
    helpers.assertEquals(entry.title, expected.title, "unexpected title")
    helpers.assertEquals(entry.depth, expected.depth, "unexpected depth")
    helpers.assertEquals(entry.kind, expected.kind, "unexpected kind")
    helpers.assertEquals(entry.line_number, expected.line_number, "unexpected line number")
end

do
    local sample = table.concat({
        "\239\187\191序章",
        "",
        "这里是正文。",
        "",
        "第一卷 江湖夜雨",
        "",
        "第1章 少年下山",
        "正文第一段。",
        "",
        "第2章 初入长安",
        "",
        "尾声",
    }, "\r\n")

    local result = Parser.detect(sample)

    helpers.assertTruthy(result, "detect should return a result table")
    helpers.assertTableLength(result.entries, 5, "should detect common Chinese headings")
    assertEntry(result.entries[1], { title = "序章", depth = 1, kind = "special", line_number = 1 })
    assertEntry(result.entries[2], { title = "第一卷 江湖夜雨", depth = 1, kind = "volume", line_number = 5 })
    assertEntry(result.entries[3], { title = "第1章 少年下山", depth = 2, kind = "chapter", line_number = 7 })
    assertEntry(result.entries[4], { title = "第2章 初入长安", depth = 2, kind = "chapter", line_number = 10 })
    assertEntry(result.entries[5], { title = "尾声", depth = 1, kind = "special", line_number = 12 })
end

do
    local sample = table.concat({
        "目录",
        "第1章 这只是目录页",
        "第2章 这也是目录页",
        "",
        "# 第一部分",
        "",
        "正文开始。",
        "",
        "Chapter 1 Arrival",
        "",
        "## Side Notes",
    }, "\n")

    local result = Parser.detect(sample)

    helpers.assertTableLength(result.entries, 3, "should skip fake table-of-contents block and keep markdown/english headings")
    assertEntry(result.entries[1], { title = "# 第一部分", depth = 1, kind = "markdown", line_number = 5 })
    assertEntry(result.entries[2], { title = "Chapter 1 Arrival", depth = 1, kind = "chapter", line_number = 9 })
    assertEntry(result.entries[3], { title = "## Side Notes", depth = 2, kind = "markdown", line_number = 11 })
end

do
    local result = Parser.detect(table.concat({
        "他在第1章里提到过一次往事，但这不是标题。",
        "第二天他们继续赶路。",
        "附录材料散落在书箱里。",
    }, "\n"))

    helpers.assertTableLength(result.entries, 0, "should not treat inline prose as headings")
end

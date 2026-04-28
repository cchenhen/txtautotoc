local helpers = require("spec.helpers")
local root = helpers.setupPackagePath()
local Reader = require("txtautotoc_reader")
local Parser = require("txtautotoc_parser")

local function bytesFromHex(hex)
    return (hex:gsub("%s+", ""):gsub("..", function(byte)
        return string.char(tonumber(byte, 16))
    end))
end

local function makeTempFile(name, content)
    local path = root .. "/" .. name
    local handle = assert(io.open(path, "wb"))
    handle:write(content)
    handle:close()
    return path
end

do
    local file = makeTempFile("spec-reader-utf8.txt", "第1章 标题\n第2章 标题\n第3章 标题\n")
    local text, encoding = Reader.readFile(file)

    helpers.assertEquals(encoding, "utf-8", "valid UTF-8 files should not be transcoded")
    helpers.assertEquals(text, "第1章 标题\n第2章 标题\n第3章 标题\n", "UTF-8 content should be preserved")
    os.remove(file)
end

do
    local gb18030_fixture = bytesFromHex("b5da31d5c220b1eacce20ab5da32d5c220b1eacce20ab5da33d5c220b1eacce20a")
    local file = makeTempFile("spec-reader-gb18030.txt", gb18030_fixture)
    local text, encoding = Reader.readFile(file)
    local parsed = Parser.detect(text)

    helpers.assertEquals(encoding, "gb18030", "GB18030 files should be converted before parsing")
    helpers.assertTableLength(parsed.entries, 3, "converted GB18030 chapter lines should be recognized")
    helpers.assertEquals(parsed.entries[1].title, "第1章 标题", "converted text should keep Chinese chapter titles")
    os.remove(file)
end

do
    local gb18030_fixture = bytesFromHex("b5da31d5c220b1eacce20ab5da32d5c220b1eacce20ab5da33d5c220b1eacce20a")
    local file = makeTempFile("spec-reader-gb18030-no-iconv.txt", gb18030_fixture)
    local original_popen = io.popen
    io.popen = nil

    local ok, text, encoding = pcall(function()
        return Reader.readFile(file)
    end)

    io.popen = original_popen
    os.remove(file)

    helpers.assertTruthy(ok, "builtin GB18030 fallback should not error when iconv is unavailable")
    local parsed = Parser.detect(text)
    helpers.assertEquals(encoding, "gb18030", "GB18030 files should be decoded without relying on iconv")
    helpers.assertTableLength(parsed.entries, 3, "builtin GB18030 decoding should allow chapter detection")
    helpers.assertEquals(parsed.entries[1].title, "第1章 标题", "builtin decoder should preserve Chinese chapter titles")
end

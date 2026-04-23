local Parser = {
    DETECTOR_VERSION = 1,
}

local SPECIAL_TITLES = {
    ["序章"] = true,
    ["楔子"] = true,
    ["引子"] = true,
    ["前言"] = true,
    ["后记"] = true,
    ["尾声"] = true,
    ["终章"] = true,
    ["番外"] = true,
}

local NUMERIC_TOKEN = "[0-9零〇一二三四五六七八九十百千两壹贰叁肆伍陆柒捌玖拾佰仟廿卅IVXLCDMivxlcdm]+"

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeText(text)
    text = text or ""
    text = text:gsub("^\239\187\191", "")
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    return text
end

local function splitLines(text)
    local lines = {}
    if text == "" then
        return lines
    end

    if text:sub(-1) ~= "\n" then
        text = text .. "\n"
    end

    for line in text:gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

local function isHeadingSeparator(char)
    if not char or char == "" then
        return true
    end
    if char:match("%s") then
        return true
    end
    return char:match("[%-:：%.、，。!！?？%[%]【】%(%)（）《》·_]") ~= nil
end

local function makeEntry(title, depth, kind, line_number, search_term)
    return {
        title = title,
        depth = depth,
        kind = kind,
        line_number = line_number,
        search_term = search_term or title,
    }
end

local function detectMarkdownHeading(line, line_number)
    local hashes, title = line:match("^(#+)%s*(.-)%s*$")
    if not hashes or #hashes > 3 or title == "" then
        return nil
    end
    return makeEntry(trim(line), #hashes, "markdown", line_number, title)
end

local function detectChineseVolume(line, line_number)
    local prefix, suffix = line:match("^(第" .. NUMERIC_TOKEN .. "[卷部篇册])(.*)$")
    if not prefix then
        return nil
    end
    if not isHeadingSeparator(suffix:sub(1, 1)) then
        return nil
    end
    return makeEntry(trim(line), 1, "volume", line_number)
end

local function detectChineseChapter(line, line_number, seen_volume)
    local prefix, suffix = line:match("^(第" .. NUMERIC_TOKEN .. "[章节回])(.*)$")
    if not prefix then
        return nil
    end
    if not isHeadingSeparator(suffix:sub(1, 1)) then
        return nil
    end
    return makeEntry(trim(line), seen_volume and 2 or 1, "chapter", line_number)
end

local function detectChineseSpecial(line, line_number)
    local normalized = trim(line)
    if SPECIAL_TITLES[normalized] then
        return makeEntry(normalized, 1, "special", line_number)
    end

    local prefix, suffix = normalized:match("^(附录)(.*)$")
    if prefix and isHeadingSeparator(suffix:sub(1, 1)) then
        return makeEntry(normalized, 1, "special", line_number)
    end

    return nil
end

local function detectEnglishHeading(line, line_number, seen_volume)
    local normalized = trim(line)

    if normalized:match("^Part%s+" .. NUMERIC_TOKEN) then
        return makeEntry(normalized, 1, "volume", line_number)
    end

    if normalized:match("^Chapter%s+" .. NUMERIC_TOKEN) then
        return makeEntry(normalized, seen_volume and 2 or 1, "chapter", line_number)
    end

    if normalized == "Prologue" or normalized == "Epilogue" or normalized:match("^Appendix([%s:：%-].*)?$") then
        return makeEntry(normalized, 1, "special", line_number)
    end

    return nil
end

local function detectHeading(line, line_number, seen_volume)
    local normalized = trim(line)
    if normalized == "" then
        return nil
    end

    return detectMarkdownHeading(normalized, line_number)
        or detectChineseVolume(normalized, line_number)
        or detectChineseChapter(normalized, line_number, seen_volume)
        or detectChineseSpecial(normalized, line_number)
        or detectEnglishHeading(normalized, line_number, seen_volume)
end

local function skipFrontMatterToc(lines)
    local first_non_empty
    for index, line in ipairs(lines) do
        if trim(line) ~= "" then
            first_non_empty = index
            break
        end
    end

    if not first_non_empty then
        return 1
    end

    local marker = trim(lines[first_non_empty]):lower()
    if marker ~= "目录" and marker ~= "contents" and marker ~= "table of contents" then
        return 1
    end

    local index = first_non_empty + 1
    while lines[index] and trim(lines[index]) ~= "" do
        index = index + 1
    end

    return index
end

function Parser.detect(text)
    local normalized = normalizeText(text)
    local lines = splitLines(normalized)
    local entries = {}
    local start_line = skipFrontMatterToc(lines)
    local seen_volume = false

    for index = start_line, #lines do
        local entry = detectHeading(lines[index], index, seen_volume)
        if entry then
            if entry.kind == "volume" then
                seen_volume = true
            end
            table.insert(entries, entry)
        end
    end

    return {
        detector_version = Parser.DETECTOR_VERSION,
        entries = entries,
        normalized_text = normalized,
    }
end

return Parser

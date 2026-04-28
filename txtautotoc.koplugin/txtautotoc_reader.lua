local Reader = {}

local builtin_gb18030_loaded = false
local builtin_gb18030

local function shellQuote(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function readRaw(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end

    local content = handle:read("*a")
    handle:close()
    return content
end

local function isContinuation(byte)
    return byte and byte >= 0x80 and byte <= 0xBF
end

function Reader.isValidUtf8(text)
    if type(text) ~= "string" then
        return false
    end

    local index = 1
    local length = #text
    while index <= length do
        local first = text:byte(index)
        if first < 0x80 then
            index = index + 1
        elseif first >= 0xC2 and first <= 0xDF then
            if not isContinuation(text:byte(index + 1)) then
                return false
            end
            index = index + 2
        elseif first == 0xE0 then
            local second = text:byte(index + 1)
            local third = text:byte(index + 2)
            if not (second and second >= 0xA0 and second <= 0xBF and isContinuation(third)) then
                return false
            end
            index = index + 3
        elseif (first >= 0xE1 and first <= 0xEC) or (first >= 0xEE and first <= 0xEF) then
            if not (isContinuation(text:byte(index + 1)) and isContinuation(text:byte(index + 2))) then
                return false
            end
            index = index + 3
        elseif first == 0xED then
            local second = text:byte(index + 1)
            local third = text:byte(index + 2)
            if not (second and second >= 0x80 and second <= 0x9F and isContinuation(third)) then
                return false
            end
            index = index + 3
        elseif first == 0xF0 then
            local second = text:byte(index + 1)
            local third = text:byte(index + 2)
            local fourth = text:byte(index + 3)
            if not (second and second >= 0x90 and second <= 0xBF and isContinuation(third) and isContinuation(fourth)) then
                return false
            end
            index = index + 4
        elseif first >= 0xF1 and first <= 0xF3 then
            if not (isContinuation(text:byte(index + 1)) and isContinuation(text:byte(index + 2)) and isContinuation(text:byte(index + 3))) then
                return false
            end
            index = index + 4
        elseif first == 0xF4 then
            local second = text:byte(index + 1)
            local third = text:byte(index + 2)
            local fourth = text:byte(index + 3)
            if not (second and second >= 0x80 and second <= 0x8F and isContinuation(third) and isContinuation(fourth)) then
                return false
            end
            index = index + 4
        else
            return false
        end
    end

    return true
end

local function convertWithIconv(path, from_encoding)
    if not io.popen then
        return nil
    end

    local command = "iconv -f " .. from_encoding .. " -t utf-8 " .. shellQuote(path) .. " 2>/dev/null"
    local handle = io.popen(command)
    if not handle then
        return nil
    end

    local converted = handle:read("*a")
    local ok = handle:close()
    if ok and converted ~= "" and Reader.isValidUtf8(converted) then
        return converted
    end

    return nil
end

local function getBuiltinGb18030()
    if not builtin_gb18030_loaded then
        builtin_gb18030_loaded = true
        local ok, module = pcall(require, "txtautotoc_gb18030")
        if ok then
            builtin_gb18030 = module
        end
    end
    return builtin_gb18030
end

local function convertWithBuiltinGb18030(raw)
    local decoder = getBuiltinGb18030()
    if not decoder then
        return nil
    end

    local converted = decoder.decode(raw)
    if converted ~= "" and Reader.isValidUtf8(converted) then
        return converted
    end
    return nil
end

function Reader.readFile(path)
    local raw = readRaw(path)
    if not raw then
        return nil
    end

    if Reader.isValidUtf8(raw) then
        return raw, "utf-8"
    end

    local converted = convertWithIconv(path, "gb18030")
        or convertWithIconv(path, "gbk")
        or convertWithBuiltinGb18030(raw)
    if converted then
        return converted, "gb18030"
    end

    return raw, "raw"
end

return Reader

local M = {}

local function stringify(value)
    if type(value) ~= "table" then
        return tostring(value)
    end

    local parts = {}
    for key, item in pairs(value) do
        table.insert(parts, tostring(key) .. "=" .. stringify(item))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

function M.setupPackagePath()
    local root = debug.getinfo(1, "S").source:sub(2):match("(.+)/spec/helpers%.lua$")
    package.path = table.concat({
        root .. "/txtautotoc.koplugin/?.lua",
        root .. "/spec/?.lua",
        package.path,
    }, ";")
    return root
end

function M.assertEquals(actual, expected, message)
    if actual ~= expected then
        error((message or "values are not equal") .. "\nexpected: " .. stringify(expected) .. "\nactual:   " .. stringify(actual), 2)
    end
end

function M.assertTruthy(value, message)
    if not value then
        error(message or "expected truthy value", 2)
    end
end

function M.assertFalsy(value, message)
    if value then
        error(message or "expected falsy value", 2)
    end
end

function M.assertTableLength(value, expected, message)
    M.assertEquals(#value, expected, message)
end

return M

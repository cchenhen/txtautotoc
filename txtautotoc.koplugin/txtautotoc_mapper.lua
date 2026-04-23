local Mapper = {
    MAX_HITS = 64,
}

local function copyEntry(entry)
    local copied = {}
    for key, value in pairs(entry) do
        copied[key] = value
    end
    return copied
end

local function isAfter(document, candidate_xpointer, previous_xpointer, candidate_page, previous_page)
    if not previous_xpointer then
        return true
    end

    if document.compareXPointers then
        local cmp = document:compareXPointers(candidate_xpointer, previous_xpointer)
        if cmp ~= nil then
            return cmp < 0
        end
    end

    if candidate_page and previous_page then
        return candidate_page > previous_page
    end

    return false
end

local function pickOccurrence(document, results, previous_xpointer, previous_page)
    if type(results) ~= "table" then
        return nil
    end

    for _, item in ipairs(results) do
        local candidate_xpointer = item.start or item[1]
        if candidate_xpointer then
            local candidate_page = document:getPageFromXPointer(candidate_xpointer)
            if candidate_page and isAfter(document, candidate_xpointer, previous_xpointer, candidate_page, previous_page) then
                return candidate_xpointer, candidate_page
            end
        end
    end

    return nil
end

function Mapper.map(document, entries)
    local mapped = {}
    local previous_xpointer
    local previous_page

    for _, entry in ipairs(entries or {}) do
        local term = entry.search_term or entry.title
        local results = document:findAllText(term, true, 0, Mapper.MAX_HITS, false)
        local xpointer, page = pickOccurrence(document, results, previous_xpointer, previous_page)

        if xpointer and page then
            local mapped_entry = copyEntry(entry)
            mapped_entry.xpointer = xpointer
            mapped_entry.page = page
            table.insert(mapped, mapped_entry)
            previous_xpointer = xpointer
            previous_page = page
        end
    end

    return mapped
end

return Mapper

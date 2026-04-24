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

local function escapeRegexLiteral(value)
    return (tostring(value or ""):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?%{%}%|\\])", "\\%1"))
end

local function buildUniqueTerms(entries)
    local terms = {}
    local seen = {}

    for _, entry in ipairs(entries or {}) do
        local term = entry.search_term or entry.title
        if term and term ~= "" and not seen[term] then
            seen[term] = true
            table.insert(terms, term)
        end
    end

    return terms
end

local function copyTermsByLengthDesc(terms, first, last)
    local copied = {}
    for index = first, last do
        table.insert(copied, terms[index])
    end
    table.sort(copied, function(left, right)
        return #left > #right
    end)
    return copied
end

local function collectRegexHits(document, terms, options)
    local hits_by_term = {}
    local chunk_size = options.chunk_size or 64
    local hits_per_term = options.hits_per_term or 8
    local total = #terms

    for first = 1, total, chunk_size do
        if options.should_abort and options.should_abort() then
            break
        end

        local last = math.min(first + chunk_size - 1, total)
        local chunk = copyTermsByLengthDesc(terms, first, last)
        local escaped = {}
        for _, term in ipairs(chunk) do
            table.insert(escaped, escapeRegexLiteral(term))
        end

        local ok, results = pcall(document.findAllText, document, table.concat(escaped, "|"), true, 0, #chunk * hits_per_term, true)
        if ok and type(results) == "table" then
            for _, item in ipairs(results) do
                local matched_text = item.matched_text
                local xpointer = item.start or item[1]
                if matched_text and xpointer then
                    hits_by_term[matched_text] = hits_by_term[matched_text] or {}
                    table.insert(hits_by_term[matched_text], item)
                end
            end
        end

        if options.progress_callback then
            options.progress_callback(last, total)
        end
    end

    return hits_by_term
end

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
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

function Mapper.mapBatched(document, entries, options)
    local mapped = {}
    local previous_xpointer
    local previous_page
    options = options or {}

    local terms = buildUniqueTerms(entries)
    local hits_by_term = collectRegexHits(document, terms, options)

    for _, entry in ipairs(entries or {}) do
        if options.should_abort and options.should_abort() then
            break
        end

        local term = entry.search_term or entry.title
        local xpointer, page = pickOccurrence(document, hits_by_term[term], previous_xpointer, previous_page)
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

function Mapper.mapFast(document, entries, total_lines)
    local mapped = {}
    local page_count = document.getPageCount and document:getPageCount() or 1
    page_count = math.max(page_count or 1, 1)
    total_lines = math.max(total_lines or 1, 1)

    for _, entry in ipairs(entries or {}) do
        local mapped_entry = copyEntry(entry)
        local line_number = math.max(entry.line_number or 1, 1)
        local ratio = total_lines > 1 and (line_number - 1) / (total_lines - 1) or 0
        local page = clamp(math.floor(ratio * (page_count - 1)), 0, page_count - 1) + 1

        mapped_entry.page = page
        if document.getPageXPointer then
            mapped_entry.xpointer = document:getPageXPointer(page)
        end
        table.insert(mapped, mapped_entry)
    end

    return mapped
end

function Mapper.map(document, entries, options)
    local mapped = {}
    local previous_xpointer
    local previous_page
    local total = #(entries or {})
    options = options or {}

    for index, entry in ipairs(entries or {}) do
        if options.should_abort and options.should_abort() then
            break
        end
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

        if options.progress_callback then
            options.progress_callback(index, total, entry)
        end
    end

    return mapped
end

return Mapper

local Cache = {
    CACHE_KEY = "txtautotoc_cache",
    SIGNATURE_KEY = "txtautotoc_cache_signature",
    VERSION_KEY = "txtautotoc_cache_version",
    STATUS_KEY = "txtautotoc_last_status",
    ENCODING_KEY = "txtautotoc_last_encoding",
}

function Cache.buildSignature(file_path, mtime, size, detector_version)
    return table.concat({
        tostring(file_path or ""),
        tostring(mtime or ""),
        tostring(size or ""),
        tostring(detector_version or ""),
    }, "|")
end

function Cache.load(doc_settings, signature, expected_version)
    local stored_signature = doc_settings:readSetting(Cache.SIGNATURE_KEY)
    local stored_version = doc_settings:readSetting(Cache.VERSION_KEY)

    if stored_signature ~= signature or stored_version ~= expected_version then
        return nil
    end

    return doc_settings:readSetting(Cache.CACHE_KEY), doc_settings:readSetting(Cache.STATUS_KEY)
end

function Cache.store(doc_settings, signature, entries, status, version)
    doc_settings:saveSetting(Cache.CACHE_KEY, entries)
    doc_settings:saveSetting(Cache.SIGNATURE_KEY, signature)
    doc_settings:saveSetting(Cache.VERSION_KEY, version or 1)
    doc_settings:saveSetting(Cache.STATUS_KEY, status)
end

function Cache.clear(doc_settings)
    doc_settings:delSetting(Cache.CACHE_KEY)
    doc_settings:delSetting(Cache.SIGNATURE_KEY)
    doc_settings:delSetting(Cache.VERSION_KEY)
    doc_settings:delSetting(Cache.STATUS_KEY)
    doc_settings:delSetting(Cache.ENCODING_KEY)
end

function Cache.shouldActivate(entries, min_hits)
    return type(entries) == "table" and #entries >= (min_hits or 3)
end

return Cache

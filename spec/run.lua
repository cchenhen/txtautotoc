local specs = {
    "spec.parser_spec",
    "spec.cache_spec",
    "spec.mapper_spec",
    "spec.main_spec",
}

local failures = {}

for _, spec in ipairs(specs) do
    io.write("Running ", spec, "...\n")
    local ok, err = pcall(require, spec)
    if not ok then
        table.insert(failures, { spec = spec, err = err })
        io.write("FAILED: ", err, "\n")
    else
        io.write("OK\n")
    end
end

if #failures > 0 then
    io.write("\n", #failures, " spec(s) failed.\n")
    os.exit(1)
end

io.write("\nAll specs passed.\n")

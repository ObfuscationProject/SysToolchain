import("net.http")
import("utils.archive")

import("systoolchain.config", {alias = "toolchain_config"})

local function _marker_exists(directory, marker)
    local value = path.join(directory, marker)
    return os.isfile(value) or os.isdir(value)
end

local function _remove_tree(directory)
    if os.exists(directory) or os.islink(directory) then
        -- QEMU out-of-tree builds contain links back into the source tree.
        -- GNU/BSD rm unlinks those entries without traversing their targets.
        os.vrunv("rm", {"-rf", directory})
    end
end

local function _completion_file(directory)
    return path.join(directory, ".systoolchain-extracted")
end

local function _extraction_complete(directory, component)
    local completion = _completion_file(directory)
    return _marker_exists(directory, component.marker) and
           os.isfile(completion) and
           io.readfile(completion) == component.sha256 .. "\n"
end

local function _verify_archive(component, archivefile)
    if not os.isfile(archivefile) then
        return false, "archive does not exist"
    end
    local actual = hash.sha256(archivefile):lower()
    if actual ~= component.sha256 then
        return false, string.format("SHA-256 mismatch for %s: expected %s, got %s",
            component.filename, component.sha256, actual)
    end
    return true
end

local function _download(component, archivefile, mirror)
    os.mkdir(path.directory(archivefile))
    if os.isfile(archivefile) then
        local valid = _verify_archive(component, archivefile)
        if valid then
            print("[source] using cached %s", archivefile)
            return archivefile
        end
        cprint("${yellow}[source] discarding corrupt cache entry %s${clear}", archivefile)
        os.tryrm(archivefile)
    end

    if mirror and mirror ~= "" then
        local mirror_file = path.join(path.absolute(mirror), component.filename)
        assert(os.isfile(mirror_file), "source mirror is missing %s", mirror_file)
        local valid, errors = _verify_archive(component, mirror_file)
        assert(valid, errors)
        os.cp(mirror_file, archivefile)
        print("[source] copied %s from the local mirror", component.filename)
        return archivefile
    end

    local last_error
    for _, url in ipairs(component.urls) do
        os.tryrm(archivefile)
        print("[source] downloading %s", url)
        local downloaded = try {
            function ()
                http.download(url, archivefile)
                return true
            end,
            catch {
                function (errors)
                    last_error = tostring(errors)
                    return false
                end
            }
        }
        if downloaded then
            local valid, errors = _verify_archive(component, archivefile)
            if valid then
                return archivefile
            end
            last_error = errors
        end
    end
    os.tryrm(archivefile)
    raise("failed to download and verify %s: %s", component.filename, last_error or "no usable URL")
end

local function _extract(component, archivefile, source_root)
    local directory = path.join(source_root, component.directory)
    if _extraction_complete(directory, component) then
        print("[source] using extracted %s", directory)
        return directory
    end

    os.mkdir(source_root)
    local token = path.filename(os.tmpfile({ramdisk = false}))
    local temporary_root = path.join(source_root,
        "." .. component.directory .. ".extracting-" .. token)
    local temporary_directory = path.join(temporary_root, component.directory)
    _remove_tree(temporary_root)
    os.mkdir(temporary_root)
    print("[source] extracting %s", component.filename)
    try {
        function ()
            archive.extract(archivefile, temporary_root)
            assert(_marker_exists(temporary_directory, component.marker),
                "archive %s did not produce the expected source directory %s",
                component.filename, temporary_directory)
            io.writefile(_completion_file(temporary_directory), component.sha256 .. "\n")

            -- Another process may have completed the same cache entry while
            -- this archive was being extracted. Prefer that complete tree.
            if not _extraction_complete(directory, component) then
                _remove_tree(directory)
                os.mv(temporary_directory, directory)
            end
            assert(_extraction_complete(directory, component),
                "failed to install the extracted source directory %s", directory)
            _remove_tree(temporary_root)
        end,
        catch {
            function (errors)
                _remove_tree(temporary_root)
                raise("failed to extract %s: %s", component.filename, errors)
            end
        }
    }
    return directory
end

function prepare(opt)
    opt = opt or {}
    toolchain_config.validate()

    local cache_dir = path.absolute(opt.cache_dir or os.getenv("SYSTOOLCHAIN_SOURCE_CACHE") or
        path.join(os.projectdir(), "build", "sources"))
    local mirror = opt.mirror or os.getenv("SYSTOOLCHAIN_SOURCE_MIRROR")
    local archive_root = path.join(cache_dir, "archives")
    local source_root = path.join(cache_dir, "src")
    local result = {}

    for _, name in ipairs(toolchain_config.source_names()) do
        local component = toolchain_config.source(name)
        local archivefile = _download(component, path.join(archive_root, component.filename), mirror)
        result[name] = _extract(component, archivefile, source_root)
    end
    result.cache_dir = cache_dir
    return result
end

function verify_cached(opt)
    opt = opt or {}
    local cache_dir = path.absolute(opt.cache_dir or os.getenv("SYSTOOLCHAIN_SOURCE_CACHE") or
        path.join(os.projectdir(), "build", "sources"))
    for _, name in ipairs(toolchain_config.source_names()) do
        local component = toolchain_config.source(name)
        local valid, errors = _verify_archive(component,
            path.join(cache_dir, "archives", component.filename))
        assert(valid, errors)
    end
    return true
end

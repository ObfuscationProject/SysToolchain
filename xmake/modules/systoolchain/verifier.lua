import("systoolchain.config", {alias = "toolchain_config"})

local _REQUIRED_TOOLS = {
    "gcc", "g++", "as", "ld", "ar", "ranlib", "nm", "strip", "objcopy", "objdump", "readelf"
}

local function _tool(sdkdir, triple, name)
    return path.join(sdkdir, "bin", triple .. "-" .. name)
end

function verify_metadata(opt)
    opt = opt or {}
    local target = toolchain_config.resolve(opt.arch)
    local sdkdir = path.absolute(assert(opt.sdkdir, "metadata verification requires sdkdir"))
    local manifest = path.join(sdkdir, "share", "systoolchain", "manifest.txt")
    assert(os.isfile(manifest), "SysToolchain build manifest is missing: %s", manifest)
    local expected_manifest = toolchain_config.manifest(target)
    local actual_manifest = io.readfile(manifest)
    assert(actual_manifest == expected_manifest,
        "SysToolchain build manifest does not match the requested target/host: %s", manifest)

    local license_root = path.join(sdkdir, "share", "licenses", "systoolchain")
    local project_license = path.join(license_root, "SysToolchain-LICENSE")
    assert(os.isfile(project_license) and os.filesize(project_license) > 0,
        "SysToolchain license is missing or empty: %s", project_license)
    for _, name in ipairs(toolchain_config.source_names()) do
        local files = os.files(path.join(license_root, name, "*"))
        assert(#files > 0, "license files are missing for source component %s", name)
        for _, licensefile in ipairs(files) do
            assert(os.filesize(licensefile) > 0, "license file is empty: %s", licensefile)
        end
    end
    return true
end

local function _check_links(sdkdir, allow_absolute)
    local absolute = {}
    for _, entry in ipairs(os.filedirs(path.join(sdkdir, "**"))) do
        if os.islink(entry) then
            local target = os.readlink(entry)
            if path.is_absolute(target) then
                table.insert(absolute, string.format("%s -> %s", entry, target))
            else
                local resolved = path.absolute(path.join(path.directory(entry), target))
                assert(os.exists(resolved), "dangling relative symlink in toolchain: %s -> %s", entry, target)
            end
        end
    end
    if #absolute > 0 and not allow_absolute then
        raise("toolchain is not relocatable; found %d absolute symlink(s), first: %s",
              #absolute, absolute[1])
    elseif #absolute > 0 then
        cprint("${yellow}[verify] allowing %d legacy absolute symlink(s)${clear}", #absolute)
    end
end

local function _direct_smoke(target, sdkdir, workdir)
    local gcc = _tool(sdkdir, target.triple, "gcc")
    local gxx = _tool(sdkdir, target.triple, "g++")
    local fixture = path.join(os.projectdir(), "tests", "consumer", "src")
    local c_object = path.join(workdir, "start.o")
    local cxx_object = path.join(workdir, "smoke.o")
    local library = path.join(workdir, "libsmoke.a")
    local executable = path.join(workdir, "smoke.elf")
    local binary = path.join(workdir, "smoke.bin")

    os.vrunv(gcc, {
        "-ffreestanding", "-fno-builtin", "-fno-stack-protector",
        "-c", path.join(fixture, "start.c"), "-o", c_object
    })
    os.vrunv(gxx, {
        "-ffreestanding", "-fno-builtin", "-fno-exceptions", "-fno-rtti",
        "-c", path.join(fixture, "smoke.cpp"), "-o", cxx_object
    })
    os.vrunv(_tool(sdkdir, target.triple, "ar"), {"rcs", library, c_object, cxx_object})
    os.vrunv(_tool(sdkdir, target.triple, "ranlib"), {library})
    os.vrunv(gcc, {
        "-nostdlib", "-static", "-Wl,-e,_start",
        c_object, cxx_object, "-o", executable
    })
    os.vrunv(_tool(sdkdir, target.triple, "objdump"), {"-f", executable})
    os.vrunv(_tool(sdkdir, target.triple, "objcopy"), {"-O", "binary", executable, binary})
    assert(os.isfile(binary) and os.filesize(binary) > 0,
        "objcopy did not create a non-empty binary for %s", target.triple)
end

local function _check_cxx_runtime_archives(target, sdkdir)
    local gxx = _tool(sdkdir, target.triple, "g++")
    local ar = _tool(sdkdir, target.triple, "ar")
    for _, name in ipairs({"libstdc++.a", "libsupc++.a"}) do
        local archivefile = os.iorunv(gxx, {"-print-file-name=" .. name}):trim()
        assert(archivefile ~= name and os.isfile(archivefile) and os.filesize(archivefile) > 0,
            "G++ cannot locate a non-empty %s archive: %s", name, archivefile)
        local members = os.iorunv(ar, {"t", archivefile}):trim()
        assert(members ~= "", "C++ runtime archive has no readable members: %s", archivefile)
    end
end

local function _check_qemu(target, sdkdir)
    local qemu = path.join(sdkdir, "bin", target.qemu_system)
    assert(os.isfile(qemu), "required QEMU system emulator is missing: %s", qemu)
    local version = os.iorunv(qemu, {"--version"})
    assert(version:find("QEMU emulator version " .. toolchain_config.qemu_version(), 1, true),
        "QEMU version mismatch: expected %s", toolchain_config.qemu_version())
    local machines = os.iorunv(qemu, {"-machine", "help"})
    assert(machines and machines:trim() ~= "", "QEMU machine list is empty: %s", qemu)
    local displays = os.iorunv(qemu, {"-display", "help"})
    assert(displays:find("none", 1, true), "QEMU is missing the headless display backend: %s", qemu)
    assert(displays:find("sdl", 1, true), "QEMU is missing the SDL display backend: %s", qemu)
end

local function _consumer_smoke(target, sdkdir, workdir)
    local fixture = path.join(os.projectdir(), "tests", "consumer")
    local builddir = path.join(workdir, "consumer-build")
    local envs = {
        SYSTOOLCHAIN_SDKDIR = sdkdir,
        SYSTOOLCHAIN_TRIPLE = target.triple
    }
    os.vrunv("xmake", {
        "f", "-c", "-y", "-P", fixture,
        "-p", "cross", "-a", target.arch, "-m", "release",
        "--target_os=none", "-o", builddir
    }, {envs = envs})
    os.vrunv("xmake", {"-y", "-P", fixture, "-b", "systoolchain-smoke"}, {envs = envs})
end

function verify(opt)
    opt = opt or {}
    local target = toolchain_config.resolve(opt.arch)
    local sdkdir = path.absolute(assert(opt.sdkdir, "verify requires sdkdir"))
    assert(os.isdir(sdkdir), "toolchain SDK directory does not exist: %s", sdkdir)
    verify_metadata({arch = target.arch, sdkdir = sdkdir})

    for _, name in ipairs(_REQUIRED_TOOLS) do
        local program = _tool(sdkdir, target.triple, name)
        assert(os.isfile(program), "required tool is missing: %s", program)
    end
    local actual = os.iorunv(_tool(sdkdir, target.triple, "gcc"), {"-dumpmachine"}):trim()
    assert(actual == target.triple, "compiler target mismatch: expected %s, got %s", target.triple, actual)
    local gcc_version = os.iorunv(_tool(sdkdir, target.triple, "gcc"), {"-dumpfullversion"}):trim()
    assert(gcc_version == toolchain_config.gcc_version(),
        "GCC version mismatch: expected %s, got %s", toolchain_config.gcc_version(), gcc_version)
    local ld_version = os.iorunv(_tool(sdkdir, target.triple, "ld"), {"--version"})
    assert(ld_version:find(toolchain_config.binutils_version(), 1, true),
        "Binutils version mismatch: expected %s in linker version output",
        toolchain_config.binutils_version())
    local libgcc = os.iorunv(_tool(sdkdir, target.triple, "gcc"), {"-print-libgcc-file-name"}):trim()
    assert(os.isfile(libgcc), "GCC cannot locate libgcc: %s", libgcc)
    _check_cxx_runtime_archives(target, sdkdir)
    _check_qemu(target, sdkdir)
    _check_links(sdkdir, opt.allow_absolute_symlinks)

    local workdir = os.tmpfile({ramdisk = false}) .. ".systoolchain-verify"
    os.tryrm(workdir)
    os.mkdir(workdir)
    _direct_smoke(target, sdkdir, workdir)
    if not opt.skip_consumer then
        _consumer_smoke(target, sdkdir, workdir)
    end
    os.tryrm(workdir)
    print("[verify] %s passed (%s)", target.arch, target.triple)
    return true
end

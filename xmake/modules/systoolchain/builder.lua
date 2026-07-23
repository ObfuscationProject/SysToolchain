import("lib.detect.find_tool")

import("systoolchain.config", {alias = "toolchain_config"})
import("systoolchain.source", {alias = "toolchain_source"})

local function _jobs(value)
    value = value or os.getenv("SYSTOOLCHAIN_JOBS") or math.min(os.default_njob(), 8)
    value = tonumber(value)
    assert(value and value >= 1 and value == math.floor(value),
        "jobs must be a positive integer")
    return value
end

local function _make_build(make, targets, jobs, curdir, envs)
    local function run(parallelism)
        local argv = {"-j" .. parallelism}
        table.join2(argv, targets)
        return os.execv(make.program, argv, {curdir = curdir, envs = envs, try = true})
    end

    local code = run(jobs)
    if code ~= 0 and jobs > 1 then
        cprint("${yellow}[build] GNU Make failed with -j%d; retrying unfinished work with -j1${clear}", jobs)
        code = run(1)
    end
    assert(code == 0, "GNU Make failed in %s", curdir)
end

local function _ninja_build(ninja, targets, jobs, curdir, envs)
    local function run(parallelism)
        local argv = {"-j" .. parallelism}
        table.join2(argv, targets)
        return os.execv(ninja.program, argv, {curdir = curdir, envs = envs, try = true})
    end

    local code = run(jobs)
    if code ~= 0 and jobs > 1 then
        cprint("${yellow}[build] Ninja failed with -j%d; retrying unfinished work with -j1${clear}", jobs)
        code = run(1)
    end
    assert(code == 0, "Ninja failed in %s", curdir)
end

local function _prepend_path(envs, directory)
    local entries = {directory}
    local current = os.getenv("PATH")
    if current and current ~= "" then
        table.join2(entries, path.splitenv(current))
    end
    envs.PATH = path.joinenv(entries)
end

local function _remove_tree(directory)
    if os.exists(directory) or os.islink(directory) then
        -- Do not let recursive cleanup follow QEMU build-tree links back into
        -- the checksum-verified source cache.
        os.vrunv("rm", {"-rf", directory})
    end
end

local function _require_host_tools()
    assert(os.host() == "linux" or os.host() == "macosx",
        "SysToolchain source builds support Linux and macOS hosts")
    local make = find_tool("gmake") or find_tool("make")
    local m4 = find_tool("m4")
    local ninja = find_tool("ninja")
    local python = find_tool("python3")
    local pkg_config = find_tool("pkg-config") or find_tool("pkgconf")
    assert(make, "GNU Make is required to build SysToolchain")
    assert(m4, "GNU m4 is required to build SysToolchain")
    assert(ninja, "Ninja is required to build the SysToolchain QEMU emulator")
    assert(python, "Python 3 is required to build the SysToolchain QEMU emulator")
    assert(pkg_config, "pkg-config is required to build the SysToolchain QEMU emulator")
    local make_version = os.iorunv(make.program, {"--version"})
    assert(make_version and make_version:find("GNU Make", 1, true),
        "%s is not GNU Make", make.program)
    for _, module in ipairs({"glib-2.0", "pixman-1", "sdl2"}) do
        local code = os.execv(pkg_config.program, {"--exists", module}, {try = true})
        assert(code == 0, "%s development files are required to build QEMU", module)
    end
    return {make = make, ninja = ninja, python = python, pkg_config = pkg_config}
end

local function _link_prerequisites(sources)
    for _, name in ipairs({"gmp", "mpfr", "mpc", "isl"}) do
        local link = path.join(sources.gcc, name)
        os.tryrm(link)
        os.ln(sources[name], link)
    end

    local dtc_link = path.join(sources.qemu, "subprojects", "dtc")
    os.tryrm(dtc_link)
    os.ln(sources.dtc, dtc_link)
end

local function _copy_licenses(sources, prefix)
    local license_root = path.join(prefix, "share", "licenses", "systoolchain")
    for _, name in ipairs(toolchain_config.source_names()) do
        local destination = path.join(license_root, name)
        os.mkdir(destination)
        local licensefiles = os.files(path.join(sources[name], "COPYING*"))
        table.join2(licensefiles, os.files(path.join(sources[name], "LICENSE*")))
        table.join2(licensefiles, os.files(path.join(sources[name], "GPL")))
        table.join2(licensefiles, os.files(path.join(sources[name], "BSD-2-Clause")))
        table.join2(licensefiles, os.files(path.join(sources[name], "README.license")))
        assert(#licensefiles > 0, "no top-level license file found for %s", name)
        for _, licensefile in ipairs(licensefiles) do
            os.cp(licensefile, path.join(destination, path.filename(licensefile)))
        end
    end
    local project_license = path.join(os.projectdir(), "LICENSE")
    assert(os.isfile(project_license), "SysToolchain LICENSE is missing: %s", project_license)
    os.cp(project_license, path.join(license_root, "SysToolchain-LICENSE"))
end

local function _manifest_path(prefix)
    return path.join(prefix, "share", "systoolchain", "manifest.txt")
end

local function _reusable_install(target, prefix, expected_manifest)
    local manifest = _manifest_path(prefix)
    if not os.isfile(manifest) or io.readfile(manifest) ~= expected_manifest then
        return false
    end
    for _, tool in ipairs({"gcc", "g++", "ld", "ar", "objcopy"}) do
        if not os.isfile(path.join(prefix, "bin", target.triple .. "-" .. tool)) then
            return false
        end
    end
    if not os.isfile(path.join(prefix, "bin", target.qemu_system)) or
       not os.isdir(path.join(prefix, "share", "qemu")) then
        return false
    end
    for _, library in ipairs({
        path.join(prefix, "lib", "gcc", target.triple, toolchain_config.gcc_version(), "libgcc.a"),
        path.join(prefix, target.triple, "lib", "libstdc++.a"),
        path.join(prefix, target.triple, "lib", "libsupc++.a")
    }) do
        if not os.isfile(library) or os.filesize(library) == 0 then
            return false
        end
    end
    local license_root = path.join(prefix, "share", "licenses", "systoolchain")
    if not os.isfile(path.join(license_root, "SysToolchain-LICENSE")) then
        return false
    end
    for _, name in ipairs(toolchain_config.source_names()) do
        if #os.files(path.join(license_root, name, "*")) == 0 then
            return false
        end
    end
    return true
end

function default_prefix(arch)
    local target = toolchain_config.resolve(arch)
    return path.join(os.projectdir(), "build", "toolchains", target.triple)
end

function build(opt)
    opt = opt or {}
    local target = toolchain_config.resolve(opt.arch)
    local prefix = path.absolute(opt.prefix or default_prefix(target.arch))
    local build_root = path.absolute(opt.build_dir or os.getenv("SYSTOOLCHAIN_BUILD_CACHE") or
        path.join(os.projectdir(), "build", "work"))
    local source_root = path.absolute(opt.source_dir or os.getenv("SYSTOOLCHAIN_SOURCE_CACHE") or
        path.join(os.projectdir(), "build", "sources"))
    local jobs = _jobs(opt.jobs)
    local expected_manifest = toolchain_config.manifest(target)
    local manifest_path = _manifest_path(prefix)

    if not opt.force and _reusable_install(target, prefix, expected_manifest) then
        print("[build] %s is already installed at %s", target.triple, prefix)
        return {arch = target.arch, triple = target.triple, prefix = prefix, reused = true}
    end

    assert(#prefix > 1 and prefix ~= "/" and not prefix:match("^%a:[/\\]?$"),
        "refusing to use an unsafe installation prefix: %s", prefix)
    local host_tools = _require_host_tools()
    local sources = toolchain_source.prepare({cache_dir = source_root, mirror = opt.source_mirror})
    _link_prerequisites(sources)

    local target_build_root = path.join(build_root, target.triple)
    local binutils_build = path.join(target_build_root, "binutils")
    local gcc_build = path.join(target_build_root, "gcc")
    local qemu_build = path.join(target_build_root, "qemu")
    _remove_tree(target_build_root)
    _remove_tree(prefix)
    os.mkdir(binutils_build)
    os.mkdir(gcc_build)
    os.mkdir(qemu_build)
    os.mkdir(prefix)

    local envs = {
        CFLAGS = "-O2",
        CXXFLAGS = "-O2",
        CFLAGS_FOR_BUILD = "-O2",
        CXXFLAGS_FOR_BUILD = "-O2",
        CFLAGS_FOR_TARGET = "-O2",
        CXXFLAGS_FOR_TARGET = "-O2",
        CPPFLAGS = "",
        LDFLAGS = "",
        LIBS = "",
        MAKEINFO = "true"
    }
    local host_cc = opt.host_cc or os.getenv("SYSTOOLCHAIN_HOST_CC") or os.getenv("CC")
    local host_cxx = opt.host_cxx or os.getenv("SYSTOOLCHAIN_HOST_CXX") or os.getenv("CXX")
    if host_cc and host_cc ~= "" then
        envs.CC = host_cc
        envs.CC_FOR_BUILD = host_cc
    end
    if host_cxx and host_cxx ~= "" then
        envs.CXX = host_cxx
        envs.CXX_FOR_BUILD = host_cxx
    end

    print("[build] configuring Binutils %s for %s", toolchain_config.binutils_version(), target.triple)
    os.vrunv(path.join(sources.binutils, "configure"), {
        "--target=" .. target.triple,
        "--prefix=" .. prefix,
        "--with-sysroot",
        "--disable-nls",
        "--disable-werror",
        "--disable-gdb",
        "--disable-sim"
    }, {curdir = binutils_build, envs = envs})
    _make_build(host_tools.make, {}, jobs, binutils_build, envs)
    os.vrunv(host_tools.make.program, {"install"}, {curdir = binutils_build, envs = envs})

    _prepend_path(envs, path.join(prefix, "bin"))
    print("[build] configuring GCC %s for %s", toolchain_config.gcc_version(), target.triple)
    os.vrunv(path.join(sources.gcc, "configure"), {
        "--target=" .. target.triple,
        "--prefix=" .. prefix,
        "--disable-nls",
        "--enable-languages=c,c++",
        "--without-headers",
        "--disable-hosted-libstdcxx",
        "--disable-libssp",
        "--disable-libquadmath",
        "--disable-libgomp",
        "--disable-libstdcxx-pch",
        "--disable-multilib"
    }, {curdir = gcc_build, envs = envs})
    _make_build(host_tools.make, {
        "all-gcc",
        "all-target-libgcc",
        "all-target-libstdc++-v3"
    }, jobs, gcc_build, envs)
    os.vrunv(host_tools.make.program, {
        "install-gcc",
        "install-target-libgcc",
        "install-target-libstdc++-v3"
    }, {curdir = gcc_build, envs = envs})

    print("[build] configuring QEMU %s for %s-softmmu",
        toolchain_config.qemu_version(), target.qemu_target)
    os.vrunv(path.join(sources.qemu, "configure"), {
        "--target-list=" .. target.qemu_target .. "-softmmu",
        "--prefix=" .. prefix,
        "--python=" .. host_tools.python.program,
        "--ninja=" .. host_tools.ninja.program,
        "--disable-docs",
        "--disable-werror",
        "--disable-user",
        "--disable-linux-user",
        "--disable-bsd-user",
        "--disable-tools",
        "--disable-guest-agent",
        "--disable-rust",
        "--disable-slirp",
        "--disable-vnc",
        "--disable-gtk",
        "--enable-sdl",
        "--disable-sdl-image",
        "--disable-curses",
        "--disable-opengl",
        "--disable-dbus-display",
        "--disable-spice",
        "--disable-usb-redir",
        "--disable-virglrenderer",
        "--disable-modules",
        "--disable-plugins",
        "--disable-download",
        "--enable-pixman",
        "--enable-fdt=internal",
        "--enable-strip",
        "-Dprefer_static=true"
    }, {curdir = qemu_build, envs = envs})
    _ninja_build(host_tools.ninja, {target.qemu_system}, jobs, qemu_build, envs)
    os.vrunv(host_tools.ninja.program, {"install"}, {curdir = qemu_build, envs = envs})

    -- GCC discovers its builtin and C++ headers from paths relative to its own
    -- executable. Do not recreate the old project-local absolute include links.
    _copy_licenses(sources, prefix)
    os.mkdir(path.directory(manifest_path))
    io.writefile(manifest_path, expected_manifest)
    print("[build] installed %s at %s", target.triple, prefix)
    return {arch = target.arch, triple = target.triple, prefix = prefix, reused = false}
end

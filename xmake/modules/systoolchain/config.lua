local _PROJECT_VERSION = "0.1.0"
local _GCC_VERSION = "14.2.0"
local _BINUTILS_VERSION = "2.42"
local _QEMU_VERSION = "10.2.0"
local _DTC_VERSION = "1.6.1"

local _CANONICAL_ARCHES = {
    "i386",
    "x86_64",
    "aarch64",
    "arm32",
    "rv64",
    "rv32",
    "loongarch64",
    "mips",
    "mips64",
    "ppc"
}

local _TARGETS = {
    i386 = {
        triple = "i386-elf", aliases = {"x86"},
        qemu_target = "i386", qemu_system = "qemu-system-i386"
    },
    x86_64 = {
        triple = "x86_64-elf", aliases = {"x64", "amd64"},
        qemu_target = "x86_64", qemu_system = "qemu-system-x86_64"
    },
    aarch64 = {
        triple = "aarch64-elf", aliases = {"arm64"},
        qemu_target = "aarch64", qemu_system = "qemu-system-aarch64"
    },
    arm32 = {
        triple = "arm-none-eabi", aliases = {"arm"},
        qemu_target = "arm", qemu_system = "qemu-system-arm"
    },
    rv64 = {
        triple = "riscv64-elf", aliases = {"riscv64"},
        qemu_target = "riscv64", qemu_system = "qemu-system-riscv64"
    },
    rv32 = {
        triple = "riscv32-elf", aliases = {"riscv32"},
        qemu_target = "riscv32", qemu_system = "qemu-system-riscv32"
    },
    loongarch64 = {
        triple = "loongarch64-elf", aliases = {"loong64"},
        qemu_target = "loongarch64", qemu_system = "qemu-system-loongarch64"
    },
    mips = {
        triple = "mips-elf", aliases = {},
        qemu_target = "mips", qemu_system = "qemu-system-mips"
    },
    mips64 = {
        triple = "mips64-elf", aliases = {},
        qemu_target = "mips64", qemu_system = "qemu-system-mips64"
    },
    ppc = {
        triple = "powerpc-eabi", aliases = {"powerpc"},
        qemu_target = "ppc", qemu_system = "qemu-system-ppc"
    }
}

local _SOURCES = {
    gcc = {
        version = _GCC_VERSION,
        filename = "gcc-14.2.0.tar.xz",
        directory = "gcc-14.2.0",
        marker = "gcc/BASE-VER",
        sha256 = "a7b39bc69cbf9e25826c5a60ab26477001f7c08d85cec04bc0e29cabed6f3cc9",
        urls = {
            "https://ftp.gnu.org/gnu/gcc/gcc-14.2.0/gcc-14.2.0.tar.xz",
            "https://mirrors.kernel.org/gnu/gcc/gcc-14.2.0/gcc-14.2.0.tar.xz"
        }
    },
    binutils = {
        version = _BINUTILS_VERSION,
        filename = "binutils-2.42.tar.xz",
        directory = "binutils-2.42",
        marker = "configure",
        sha256 = "f6e4d41fd5fc778b06b7891457b3620da5ecea1006c6a4a41ae998109f85a800",
        urls = {
            "https://ftp.gnu.org/gnu/binutils/binutils-2.42.tar.xz",
            "https://mirrors.kernel.org/gnu/binutils/binutils-2.42.tar.xz"
        }
    },
    gmp = {
        version = "6.2.1",
        filename = "gmp-6.2.1.tar.bz2",
        directory = "gmp-6.2.1",
        marker = "gmp-h.in",
        sha256 = "eae9326beb4158c386e39a356818031bd28f3124cf915f8c5b1dc4c7a36b4d7c",
        urls = {"https://gcc.gnu.org/pub/gcc/infrastructure/gmp-6.2.1.tar.bz2"}
    },
    mpfr = {
        version = "4.1.0",
        filename = "mpfr-4.1.0.tar.bz2",
        directory = "mpfr-4.1.0",
        marker = "src/mpfr.h",
        sha256 = "feced2d430dd5a97805fa289fed3fc8ff2b094c02d05287fd6133e7f1f0ec926",
        urls = {"https://gcc.gnu.org/pub/gcc/infrastructure/mpfr-4.1.0.tar.bz2"}
    },
    mpc = {
        version = "1.2.1",
        filename = "mpc-1.2.1.tar.gz",
        directory = "mpc-1.2.1",
        marker = "src/mpc.h",
        sha256 = "17503d2c395dfcf106b622dc142683c1199431d095367c6aacba6eec30340459",
        urls = {"https://gcc.gnu.org/pub/gcc/infrastructure/mpc-1.2.1.tar.gz"}
    },
    isl = {
        version = "0.24",
        filename = "isl-0.24.tar.bz2",
        directory = "isl-0.24",
        marker = "include/isl",
        sha256 = "fcf78dd9656c10eb8cf9fbd5f59a0b6b01386205fe1934b3b287a0a1898145c0",
        urls = {"https://gcc.gnu.org/pub/gcc/infrastructure/isl-0.24.tar.bz2"}
    },
    qemu = {
        version = _QEMU_VERSION,
        filename = "qemu-10.2.0.tar.xz",
        directory = "qemu-10.2.0",
        marker = "scripts/meson-buildoptions.sh",
        sha256 = "9e30ad1b8b9f7b4463001582d1ab297f39cfccea5d08540c0ca6d6672785883a",
        urls = {"https://download.qemu.org/qemu-10.2.0.tar.xz"}
    },
    dtc = {
        version = _DTC_VERSION,
        filename = "dtc-1.6.1.tar.xz",
        directory = "dtc-1.6.1",
        marker = "libfdt/meson.build",
        sha256 = "65cec529893659a49a89740bb362f507a3b94fc8cd791e76a8d6a2b6f3203473",
        urls = {"https://www.kernel.org/pub/software/utils/dtc/dtc-1.6.1.tar.xz"}
    }
}

local _SOURCE_ORDER = {"gcc", "binutils", "gmp", "mpfr", "mpc", "isl", "dtc", "qemu"}

local function _copy_array(values)
    local result = {}
    for _, value in ipairs(values) do
        table.insert(result, value)
    end
    return result
end

local function _copy_source(source)
    return {
        version = source.version,
        filename = source.filename,
        directory = source.directory,
        marker = source.marker,
        sha256 = source.sha256,
        urls = _copy_array(source.urls)
    }
end

function project_version()
    return _PROJECT_VERSION
end

function gcc_version()
    return _GCC_VERSION
end

function binutils_version()
    return _BINUTILS_VERSION
end

function qemu_version()
    return _QEMU_VERSION
end

function dtc_version()
    return _DTC_VERSION
end

function canonical_arches()
    return _copy_array(_CANONICAL_ARCHES)
end

function source_names()
    return _copy_array(_SOURCE_ORDER)
end

function source(name)
    local value = _SOURCES[name]
    assert(value, "unknown SysToolchain source component: %s", tostring(name))
    return _copy_source(value)
end

function resolve(arch)
    arch = (arch or "x86_64"):lower()
    for _, canonical in ipairs(_CANONICAL_ARCHES) do
        local target = _TARGETS[canonical]
        if arch == canonical then
            return {
                arch = canonical,
                triple = target.triple,
                aliases = _copy_array(target.aliases),
                qemu_target = target.qemu_target,
                qemu_system = target.qemu_system
            }
        end
        for _, alias in ipairs(target.aliases) do
            if arch == alias then
                return {
                    arch = canonical,
                    triple = target.triple,
                    aliases = _copy_array(target.aliases),
                    qemu_target = target.qemu_target,
                    qemu_system = target.qemu_system
                }
            end
        end
    end
    raise("unsupported architecture '%s'; expected one of: %s",
          arch, table.concat(_CANONICAL_ARCHES, ", "))
end

function aliases(arch)
    return resolve(arch).aliases
end

function normalize_host_arch(host_arch)
    host_arch = (host_arch or os.arch()):lower()
    if host_arch == "x64" or host_arch == "amd64" then
        return "x86_64"
    elseif host_arch == "arm64" then
        return "aarch64"
    end
    return host_arch
end

function normalize_host(host)
    host = (host or os.host()):lower()
    if host == "macosx" then
        return "macos"
    end
    return host
end

function asset_name(arch, host, host_arch)
    local target = type(arch) == "table" and arch or resolve(arch)
    return string.format("systoolchain-%s-%s-%s-%s.tar.xz",
        _PROJECT_VERSION, normalize_host(host), normalize_host_arch(host_arch), target.triple)
end

function manifest(arch, host, host_arch)
    local target = type(arch) == "table" and arch or resolve(arch)
    return table.concat({
        "format=1",
        "systoolchain=" .. _PROJECT_VERSION,
        "target_arch=" .. target.arch,
        "target=" .. target.triple,
        "host=" .. normalize_host(host),
        "host_arch=" .. normalize_host_arch(host_arch),
        "gcc=" .. _GCC_VERSION,
        "binutils=" .. _BINUTILS_VERSION,
        "qemu=" .. _QEMU_VERSION,
        "dtc=" .. _DTC_VERSION,
        "qemu_target=" .. target.qemu_target .. "-softmmu",
        "qemu_system=" .. target.qemu_system,
        "languages=c,c++",
        "multilib=false",
        ""
    }, "\n")
end

function validate()
    local seen_triples = {}
    local seen_qemu_targets = {}
    local seen_qemu_systems = {}
    local seen_names = {}
    for _, arch in ipairs(_CANONICAL_ARCHES) do
        local target = resolve(arch)
        assert(not seen_triples[target.triple],
            "canonical target triple collision: %s and %s both use %s",
            arch, seen_triples[target.triple] or "<unknown>", target.triple)
        seen_triples[target.triple] = arch
        assert(not seen_qemu_targets[target.qemu_target],
            "QEMU target collision: %s", target.qemu_target)
        assert(not seen_qemu_systems[target.qemu_system],
            "QEMU system executable collision: %s", target.qemu_system)
        seen_qemu_targets[target.qemu_target] = arch
        seen_qemu_systems[target.qemu_system] = arch
        seen_names[arch] = target.triple
        for _, alias in ipairs(target.aliases) do
            assert(not seen_names[alias], "architecture alias collision: %s", alias)
            seen_names[alias] = target.triple
            local alias_target = resolve(alias)
            assert(alias_target.arch == arch and alias_target.triple == target.triple,
                "architecture alias %s does not resolve to %s", alias, arch)
        end
        local expected_asset = string.format(
            "systoolchain-%s-linux-x86_64-%s.tar.xz", _PROJECT_VERSION, target.triple)
        assert(asset_name(arch, "linux", "x86_64") == expected_asset,
            "unexpected release asset name for %s", arch)
    end
    assert(#_CANONICAL_ARCHES == 10, "expected exactly ten canonical targets")

    local seen_files = {}
    for _, name in ipairs(_SOURCE_ORDER) do
        local component = source(name)
        assert(#component.sha256 == 64 and component.sha256:match("^%x+$"),
            "invalid SHA-256 for %s", name)
        assert(not seen_files[component.filename], "duplicate source filename: %s", component.filename)
        assert(#component.urls > 0, "source component has no URL: %s", name)
        seen_files[component.filename] = true
    end
    return true
end

set_project("systoolchain-consumer")
set_version("0.1.0")

local sdkdir = os.getenv("SYSTOOLCHAIN_SDKDIR") or ""
local triple = os.getenv("SYSTOOLCHAIN_TRIPLE") or "unknown-elf"

toolchain("systoolchain-fixture")
    set_kind("standalone")
    set_sdkdir(sdkdir)
    set_toolset("cc", triple .. "-gcc")
    set_toolset("cxx", triple .. "-g++")
    set_toolset("as", triple .. "-gcc")
    set_toolset("ld", triple .. "-gcc")
    set_toolset("ar", triple .. "-ar")
    set_toolset("ranlib", triple .. "-ranlib")
    set_toolset("strip", triple .. "-strip")
    set_toolset("objcopy", triple .. "-objcopy")
toolchain_end()

target("systoolchain-smoke")
    set_kind("binary")
    set_filename("systoolchain-smoke.elf")
    set_toolchains("systoolchain-fixture")
    add_files("src/start.c", "src/smoke.cpp")
    add_cxflags(
        "-ffreestanding",
        "-fno-builtin",
        "-fno-stack-protector",
        "-ffunction-sections",
        "-fdata-sections",
        {force = true})
    add_cxxflags("-fno-exceptions", "-fno-rtti", {force = true})
    add_ldflags(
        "-nostdlib",
        "-static",
        "-Wl,-e,_start",
        "-Wl,--gc-sections",
        {force = true})

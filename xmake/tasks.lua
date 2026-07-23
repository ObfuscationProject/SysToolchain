task("build-toolchain")
    set_menu {
        usage = "xmake build-toolchain --arch=ARCH [--prefix=DIR]",
        description = "Build one freestanding GCC/Binutils toolchain from checksum-pinned sources",
        options = {
            {"a", "arch", "kv", "x86_64", "Target architecture"},
            {"j", "jobs", "kv", nil, "Parallel GNU Make jobs"},
            {nil, "prefix", "kv", nil, "Installation prefix (replaced on a fresh build)"},
            {nil, "source-dir", "kv", nil, "Source archive/extraction cache"},
            {nil, "build-dir", "kv", nil, "Out-of-tree build cache"},
            {nil, "source-mirror", "kv", nil, "Offline directory containing all pinned archives"},
            {nil, "force", "k", nil, "Rebuild even if the installed manifest matches"}
        }
    }
    on_run(function ()
        import("core.base.option")
        import("systoolchain.builder", {alias = "toolchain_builder"})
        local result = toolchain_builder.build({
            arch = option.get("arch"),
            jobs = option.get("jobs"),
            prefix = option.get("prefix"),
            source_dir = option.get("source-dir"),
            build_dir = option.get("build-dir"),
            source_mirror = option.get("source-mirror"),
            force = option.get("force")
        })
        print("[ok] %s: %s", result.triple, result.prefix)
    end)
task_end()

task("verify-toolchain")
    set_menu {
        usage = "xmake verify-toolchain --arch=ARCH --sdkdir=DIR",
        description = "Validate tools, target identity, relocation, C/C++ compilation and linking",
        options = {
            {"a", "arch", "kv", "x86_64", "Target architecture"},
            {nil, "sdkdir", "kv", nil, "Installed toolchain root"},
            {nil, "skip-consumer", "k", nil, "Skip the xmake consumer fixture"},
            {nil, "allow-absolute-symlinks", "k", nil, "Allow legacy non-relocatable include links"}
        }
    }
    on_run(function ()
        import("core.base.option")
        import("systoolchain.builder", {alias = "toolchain_builder"})
        import("systoolchain.verifier", {alias = "toolchain_verifier"})
        local arch = option.get("arch")
        toolchain_verifier.verify({
            arch = arch,
            sdkdir = option.get("sdkdir") or toolchain_builder.default_prefix(arch),
            skip_consumer = option.get("skip-consumer"),
            allow_absolute_symlinks = option.get("allow-absolute-symlinks")
        })
    end)
task_end()

task("package-toolchain")
    set_menu {
        usage = "xmake package-toolchain --arch=ARCH --sdkdir=DIR [--output-dir=DIR]",
        description = "Verify and create a relocatable release archive plus SHA-256 file",
        options = {
            {"a", "arch", "kv", "x86_64", "Target architecture"},
            {nil, "sdkdir", "kv", nil, "Installed toolchain root"},
            {nil, "output-dir", "kv", nil, "Release artifact directory"},
            {nil, "skip-verify", "k", nil, "Skip pre/post compiler smokes (metadata is always checked)"}
        }
    }
    on_run(function ()
        import("core.base.option")
        import("systoolchain.builder", {alias = "toolchain_builder"})
        import("systoolchain.packager", {alias = "toolchain_packager"})
        local arch = option.get("arch")
        toolchain_packager.package({
            arch = arch,
            sdkdir = option.get("sdkdir") or toolchain_builder.default_prefix(arch),
            output_dir = option.get("output-dir"),
            skip_verify = option.get("skip-verify")
        })
    end)
task_end()

task("test-matrix")
    set_menu {
        usage = "xmake test-matrix",
        description = "Check all target mappings, aliases, release names and pinned source metadata"
    }
    on_run(function ()
        import("systoolchain.config", {alias = "toolchain_config"})
        toolchain_config.validate()
        for _, arch in ipairs(toolchain_config.canonical_arches()) do
            local target = toolchain_config.resolve(arch)
            print("[matrix] %-13s %-20s %-24s %s", arch, target.triple,
                target.qemu_system, toolchain_config.asset_name(arch, "linux", "x86_64"))
            for _, alias in ipairs(target.aliases) do
                local alias_target = toolchain_config.resolve(alias)
                assert(alias_target.arch == arch and alias_target.triple == target.triple and
                       alias_target.qemu_target == target.qemu_target and
                       alias_target.qemu_system == target.qemu_system)
            end
        end
        print("[ok] target matrix and pinned source metadata")
    end)
task_end()

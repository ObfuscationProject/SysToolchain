import("utils.archive")

import("systoolchain.config", {alias = "toolchain_config"})
import("systoolchain.verifier", {alias = "toolchain_verifier"})

function package(opt)
    opt = opt or {}
    local target = toolchain_config.resolve(opt.arch)
    local sdkdir = path.absolute(assert(opt.sdkdir, "package requires sdkdir"))
    local output_dir = path.absolute(opt.output_dir or path.join(os.projectdir(), "build", "release"))
    assert(os.isdir(sdkdir), "toolchain SDK directory does not exist: %s", sdkdir)
    -- A release archive must always carry exact provenance and license data,
    -- even when the caller opts out of the more expensive compiler smokes.
    toolchain_verifier.verify_metadata({arch = target.arch, sdkdir = sdkdir})

    if not opt.skip_verify then
        toolchain_verifier.verify({arch = target.arch, sdkdir = sdkdir})
    end

    local archive_name = toolchain_config.asset_name(target, opt.host, opt.host_arch)
    local archivefile = path.join(output_dir, archive_name)
    local checksumfile = archivefile .. ".sha256"
    os.mkdir(output_dir)
    os.tryrm(archivefile)
    os.tryrm(checksumfile)
    print("[package] creating %s", archivefile)
    archive.archive(archivefile, ".", {curdir = sdkdir, recurse = true, compress = "best"})

    local checksum = hash.sha256(archivefile)
    io.writefile(checksumfile, string.format("%s  %s\n", checksum, path.filename(archivefile)))

    if not opt.skip_verify then
        local extraction = os.tmpfile({ramdisk = false}) .. ".systoolchain-package"
        os.tryrm(extraction)
        os.mkdir(extraction)
        archive.extract(archivefile, extraction)
        toolchain_verifier.verify({arch = target.arch, sdkdir = extraction})
        os.tryrm(extraction)
    end
    print("[package] wrote %s", archivefile)
    print("[package] wrote %s", checksumfile)
    return {archive = archivefile, checksum = checksumfile, sha256 = checksum}
end

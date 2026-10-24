# SysToolchain plan

SysToolchain is the most finished component of the project: pinned sources,
SHA-256 verification, relocation checks and a release workflow. The items below
are what the kernel and OS plans need from it, in dependency order.

## 1. Publish the 0.1.0 release archives

`.github/workflows/release.yml` builds and uploads all ten archives when the tag
`v0.1.0` is pushed, but no release exists yet. Until it does, every consumer
resolves `systoolchain 0.1.0` with `build_from_source = true` and CI compiles
GCC and QEMU from source (now cached per architecture, but still a cold build per
cache miss).

- Push the immutable tag `v0.1.0` from the commit that matches the package
  recipe in ObfuscationRepo. Confirm all ten `*.tar.xz` and `.sha256` assets.
- Then switch ObfuscationKernel and ObfuscationOS to the default download path
  (`build_from_source = false`) and keep the source build as the documented
  fallback.

## 2. 0.2.0: hosted musl toolchains for the userland (needed by OS `feat/musl-primary`)

The freestanding `*-elf` compilers build the kernel and okcrt. A musl userland
needs, per architecture, a GCC configured for `<arch>-linux-musl` against the
pinned musl 1.2.5 sysroot, plus binutils that can produce PIC shared objects.

- Add a second toolchain family `<arch>-linux-musl` with the same reproducible
  builder: GCC 14.2 + Binutils 2.42, musl 1.2.5 headers/crt/libc, no glibc.
- Resolve the known blockers recorded in ObfuscationOS
  `docs/plans/contracts/`: MIPS PIC runtime (`DT_TEXTREL`), MIPS64 n64 linker,
  PPC secure-PLT runtime, LoongArch atomics.
- Release as `systoolchain 0.2.0`; the `*-elf` family is unchanged.

## 3. QEMU re-probes on 10.2.0

The LoongArch branch-to-NX probe recorded a recursive emulator fault on QEMU
8.2.2 (Kernel `docs/VALIDATION.md`). Re-run the kernel architecture probes on the
pinned 10.2.0 and record the result in the evidence repository.

## 4. Later

- macOS host release archives (source build is already supported).
- Package `e2fsprogs 1.47.2` host tools alongside QEMU so the OS can drop its
  Linux-kernel-image dependency for journalled ext4 images (OS worktree
  `fix/mkfs-e2fsprogs`).

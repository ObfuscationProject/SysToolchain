# SysToolchain

SysToolchain is the reproducible, relocatable GCC/Binutils and QEMU build for
ObfuscationOS and ObfuscationKernel. The repository contains the complete build
orchestration, verification, packaging, and release automation. All project-owned
build logic is Lua executed by xmake; there are no project shell scripts.

The current SysToolchain release is **0.1.0** and pins:

- GCC 14.2.0
- Binutils 2.42
- GMP 6.2.1
- MPFR 4.1.0
- MPC 1.2.1
- ISL 0.24
- DTC 1.6.1
- QEMU 10.2.0

Every upstream archive is verified against a SHA-256 value stored in
`xmake/modules/systoolchain/config.lua` before it is extracted. No downstream
patches are currently applied.

## Targets

One independent toolchain is built for each canonical target. Aliases resolve to
the same target and release artifact.

| Canonical arch | Target triple | QEMU executable | Accepted aliases |
| --- | --- | --- | --- |
| `i386` | `i386-elf` | `qemu-system-i386` | `x86` |
| `x86_64` | `x86_64-elf` | `qemu-system-x86_64` | `x64`, `amd64` |
| `aarch64` | `aarch64-elf` | `qemu-system-aarch64` | `arm64` |
| `arm32` | `arm-none-eabi` | `qemu-system-arm` | `arm` |
| `rv64` | `riscv64-elf` | `qemu-system-riscv64` | `riscv64` |
| `rv32` | `riscv32-elf` | `qemu-system-riscv32` | `riscv32` |
| `loongarch64` | `loongarch64-elf` | `qemu-system-loongarch64` | `loong64` |
| `mips` | `mips-elf` | `qemu-system-mips` | — |
| `mips64` | `mips64-elf` | `qemu-system-mips64` | — |
| `ppc` | `powerpc-eabi` | `qemu-system-ppc` | `powerpc` |

These are bare-metal/freestanding toolchains. They intentionally do not contain
a hosted C library such as glibc or newlib.

## Requirements

Source builds are supported on Linux and macOS hosts and require:

- xmake 3.0.9 or newer
- a host C and C++ compiler
- GNU Make
- GNU m4
- Ninja, pkg-config, and Python 3 with venv support
- GLib, Pixman, and SDL2 development files
- a tar implementation and xz support for release packaging

On Ubuntu/Debian:

```console
sudo apt-get install \
    build-essential m4 texinfo xz-utils ninja-build pkg-config python3-venv \
    libglib2.0-dev libpixman-1-dev libsdl2-dev
```

## Build

Build one target into the default `build/toolchains/<triple>` directory:

```console
xmake build-toolchain --arch=x86_64 --jobs=8
```

Choose an explicit installation prefix and cache directories:

```console
xmake build-toolchain \
    --arch=rv64 \
    --prefix=/opt/systoolchain/riscv64-elf \
    --source-dir=$HOME/.cache/systoolchain/sources \
    --build-dir=$HOME/.cache/systoolchain/build \
    --jobs=8
```

The equivalent cache environment variables are:

- `SYSTOOLCHAIN_SOURCE_CACHE`
- `SYSTOOLCHAIN_BUILD_CACHE`
- `SYSTOOLCHAIN_JOBS`
- `SYSTOOLCHAIN_HOST_CC` and `SYSTOOLCHAIN_HOST_CXX`

When no job count is supplied, SysToolchain caps the local default at eight
parallel GNU Make/Ninja jobs. An explicit `--jobs`/`SYSTOOLCHAIN_JOBS` value is
honored; if a parallel build fails, the builder retries unfinished work once
with `-j1` before reporting the failure. This makes source installs resilient to
transient host compiler/resource failures without hiding reproducible ones.

For a fully offline build, put all eight archives listed below in one directory and
pass `--source-mirror=DIR`, or set `SYSTOOLCHAIN_SOURCE_MIRROR`. The same pinned
checksums are enforced for a mirror.

```text
gcc-14.2.0.tar.xz
binutils-2.42.tar.xz
gmp-6.2.1.tar.bz2
mpfr-4.1.0.tar.bz2
mpc-1.2.1.tar.gz
isl-0.24.tar.bz2
dtc-1.6.1.tar.xz
qemu-10.2.0.tar.xz
```

`--force` discards a matching installed toolchain and rebuilds it. A fresh build
replaces the selected prefix, so the prefix must be dedicated to SysToolchain.

## What the build does

The Lua builder performs out-of-tree builds in this order:

1. Download, SHA-256 verify, and extract all pinned sources.
2. Link the pinned GMP, MPFR, MPC, and ISL source trees into the GCC source tree,
   and the pinned DTC source into QEMU's local Meson subprojects directory.
3. Configure and install Binutils with a sysroot and without NLS, GDB, or the
   simulator.
4. Configure GCC for C and C++ without target headers, hosted libstdc++, SSP,
   Quadmath, OpenMP, precompiled libstdc++ headers, or multilib.
5. Build and install `gcc`, target `libgcc`, and freestanding target `libstdc++`.
6. Build the matching QEMU system emulator with TCG, Pixman, SDL, and the
   target's normal upstream machine/device set.
7. Install component license texts and a machine-readable build manifest.

The upstream `configure`, GNU Make, and Ninja programs are invoked directly with
`os.vrunv` from Lua. They remain upstream build tools, not SysToolchain scripts.

## Verify

Run the complete smoke suite against an installed target:

```console
xmake verify-toolchain \
    --arch=x86_64 \
    --sdkdir=build/toolchains/x86_64-elf
```

Verification checks all compiler/binutils programs, `-dumpmachine`, `libgcc`,
the matching package-owned QEMU version/machine/display capabilities, symlink
relocation safety, C and C++ compilation, static archive creation, freestanding
linking, `objdump`, `objcopy`, and the xmake consumer fixture under
`tests/consumer`.

The verifier rejects every absolute symlink. The
`--allow-absolute-symlinks` switch exists only to diagnose old project-local
toolchains and must never be used for a release.

Validate target mappings and all source metadata without downloading or building:

```console
xmake test-matrix
```

## Package and release assets

Create a verified relocatable archive and checksum:

```console
xmake package-toolchain \
    --arch=x86_64 \
    --sdkdir=build/toolchains/x86_64-elf \
    --output-dir=build/release
```

For a Linux x86_64 host the outputs are:

```text
systoolchain-0.1.0-linux-x86_64-x86_64-elf.tar.xz
systoolchain-0.1.0-linux-x86_64-x86_64-elf.tar.xz.sha256
```

The archive root directly contains `bin/`, `lib/`, `libexec/`, `share/`, and the
target directory; it does not add another wrapper directory. Packaging verifies
the installed tree, creates the archive, extracts it at a different path, and
verifies the relocated copy again.

Pushing the immutable stable tag `v0.1.0` runs
`.github/workflows/release.yml`. Ten Ubuntu 22.04 jobs independently build and
verify the target matrix, then a release job uploads every archive and `.sha256`
file to GitHub Release `v0.1.0`. Ubuntu 22.04 is deliberately fixed so released
host executables do not accidentally acquire a newer `ubuntu-latest` glibc
baseline.

## Relocation contract

GCC natively discovers builtin and C++ headers relative to its executable. The
old ObfuscationOS/ObfuscationKernel build scripts created a flattened top-level
`include/` tree with absolute symlinks into the build machine. SysToolchain never
creates that tree. Consumers must use the compiler's native layout and must not
add package-cache paths to reproduce it.

QEMU is configured as a relocatable installation and discovers firmware/data
under the package's `share/qemu` directory. Consumers obtain its absolute path
from the resolved package; machine, CPU, device, disk, and display arguments
remain project-owned configuration.

Release artifacts are host-specific as well as target-specific: a compiler built
for Linux x86_64 cannot run on macOS or another host architecture. The host and
target are therefore both part of every asset name.

## Package consumption

The `systoolchain` package in ObfuscationRepo provides two installation paths:

- download the matching GitHub Release archive (the default);
- build locally from this repository's tagged Lua/xmake source with the package's
  source-build configuration enabled.

Projects should select it as an xmake package toolchain rather than copying its
installation into a project-local `toolchains/` directory. See ObfuscationRepo's
package recipe for the exact `add_repositories`, `add_requires`, and
`set_toolchains` declarations.

## Source integrity

| Component | SHA-256 |
| --- | --- |
| GCC 14.2.0 | `a7b39bc69cbf9e25826c5a60ab26477001f7c08d85cec04bc0e29cabed6f3cc9` |
| Binutils 2.42 | `f6e4d41fd5fc778b06b7891457b3620da5ecea1006c6a4a41ae998109f85a800` |
| GMP 6.2.1 | `eae9326beb4158c386e39a356818031bd28f3124cf915f8c5b1dc4c7a36b4d7c` |
| MPFR 4.1.0 | `feced2d430dd5a97805fa289fed3fc8ff2b094c02d05287fd6133e7f1f0ec926` |
| MPC 1.2.1 | `17503d2c395dfcf106b622dc142683c1199431d095367c6aacba6eec30340459` |
| ISL 0.24 | `fcf78dd9656c10eb8cf9fbd5f59a0b6b01386205fe1934b3b287a0a1898145c0` |
| DTC 1.6.1 | `65cec529893659a49a89740bb362f507a3b94fc8cd791e76a8d6a2b6f3203473` |
| QEMU 10.2.0 | `9e30ad1b8b9f7b4463001582d1ab297f39cfccea5d08540c0ca6d6672785883a` |

## Licensing

SysToolchain's own Lua code is MIT licensed. Built archives contain GCC,
Binutils, DTC, QEMU, their target runtime/data files, and prerequisite code under
their respective upstream licenses. The builder copies available upstream
top-level license files into `share/licenses/systoolchain/`. The exact
corresponding source URLs, versions, hashes, and complete build instructions are
retained in this repository.

# Native rsync for Haiku OS (x86_64)

A natively-compiled **rsync 3.5.1** client packaged as an installable Haiku
`.hpkg` for **x86_64**.

- **Package:** `rsync-3.5.1-1-x86_64.hpkg` (≈390 KB)
- **SHA256:** `33bdf1641cdbaa2760422c5d1b0e8f7592b7f4bf7f45a90115a259768b540f42`
- **Install:** `pkgman install rsync-3.5.1-1-x86_64.hpkg`
- **After install:** `rsync` resolves to `/boot/system/bin/rsync`

---

## 1. What this is

rsync is the standard tool for efficient incremental file transfer. Upstream
rsync does not build cleanly on Haiku without platform fixes. This project
produces a fully native build (compiled with Haiku's own toolchain, no
cross-compiler) and wraps it in a proper Haiku package with correct metadata.

### Enabled features

| Area | Details |
|------|---------|
| Checksums | `xxh128`, `xxh3`, `xxh64` (xxhash), `md5`, `md4`, `sha1`, `none` |
| Compression | `zstd`, `lz4`, `zlibx`, `zlib` |
| Crypto | openssl (daemon auth: sha512/sha256/sha1/md5/md4) |
| Attributes | extended attributes (xattrs) |
| Network | IPv6, daemon (`rsync://`) and SSH transports |
| Extras | 64-bit files/inums/timestamps, symlinks, hardlinks, atimes, batch, inplace, append |

Ships the `rsync` binary, the `rsync-ssl` helper script, and man pages
(`rsync.1`, `rsync-ssl.1`, `rsyncd.conf.5`).

---

## 2. Target environment

- **OS:** Haiku R1~beta6, hrev59866, x86_64 (lab VM at `192.0.0.136`)
- **Toolchain (native on Haiku):** gcc 13.3.0, make, autoconf/automake, `jam`, `package`
- **Source:** rsync 3.5.1 (latest upstream release at time of build)

Because Haiku ships a complete native toolchain (compiler + autotools + the
`package` tool), the whole build and package happens **on the Haiku machine
itself** — no cross-compilation required.

---

## 3. Haiku-specific patches

Three platform fixes are required (adapted from the older HaikuPorts
`rsync-3.2.7` recipe and retargeted to 3.5.1). See `src/rsync-3.5.1.patchset`.

### 3.1 Library linkage (`configure.ac`)

Several functions rsync needs are **not** in Haiku's `libroot` and must be
linked from companion libraries:

```diff
 AC_SEARCH_LIBS(inet_ntop, resolv)
+AC_SEARCH_LIBS(socket, network)   # sockets      -> libnetwork.so
+AC_SEARCH_LIBS(getpass, bsd)      # getpass      -> libbsd.so
+AC_SEARCH_LIBS(getxattr, gnu)     # xattrs       -> libgnu.so
```

### 3.2 Extended-attribute backend (`configure.ac`)

rsync's configure has no `*haiku*` case for xattrs. Haiku implements the Linux
xattr API, so we add a case that selects it:

```diff
+    *haiku*)
+	AC_MSG_RESULT(Using Linux xattrs)
+	AC_DEFINE(HAVE_LINUX_XATTRS, 1, [True if you have Linux xattrs (or equivalent)])
+	AC_DEFINE(SUPPORT_XATTRS, 1)
+	AC_DEFINE(NO_DEVICE_XATTRS, 1, [True if device files do not support xattrs])
+	;;
```

`NO_DEVICE_XATTRS` reflects that Haiku device files don't carry xattrs.

### 3.3 Device-node macros (`rsync.h`)

Haiku has no `makedev()`/`major()`/`minor()` (no device nodes in the
filesystem sense). These are stubbed out:

```diff
-#define MAKEDEV(devmajor,devminor) makedev(devmajor,devminor)
+#define MAKEDEV(devmajor,devminor) ((dev_t)0)
+#define major(dev) (0)
+#define minor(dev) (0)
```

> Note: the upstream 3.2.7 patchset also patched `testsuite/hands.test` for
> hardlinks. In 3.5.1 the testsuite moved to Python (`hands_test.py`), so that
> patch no longer applies and isn't needed for the shipped binary.

---

## 4. Dependencies

rsync bundles `popt`, `zlib`, `xxhash`, `blake2` in-tree, so external
dependencies are minimal. The build links against system libraries available
in the standard HaikuPorts repository:

**Build-time (`*_devel` packages):**
`zlib_devel`, `zstd_devel`, `xxhash_devel`, `lz4_devel`, plus the already-present `openssl3_devel`.

**Runtime (declared in the package):**
`lib:libcrypto>=3`, `lib:liblz4>=1`, `lib:libxxhash`, `lib:libzstd>=1`, `lib:libz>=1`,
and `haiku>=r1~beta5` (covers `libroot`, `libnetwork`, `libbsd`, `libgnu`).

> **Note on openssl:** the box has `openssl3` (3.5.9). `openssl_devel` (1.1.1w)
> conflicts with `openssl3_devel`, so the build uses the installed openssl3.

---

## 5. Build process

Everything runs on the Haiku machine. The scripted version is
`build_haiku_rsync.sh` (in this repo); the essential steps:

```sh
# 1. Extract source
tar xzf rsync-3.5.1.tar.gz && cd rsync-3.5.1

# 2. Apply Haiku patches
patch -p1 < rsync-3.5.1.patchset

# 3. Regenerate configure from the patched configure.ac
aclocal && autoconf

# 4. Configure
./configure --prefix=/boot/system \
  --bindir=/boot/system/bin \
  --disable-iconv --disable-iconv-open \
  --disable-locale \
  --enable-xattr-support \
  --with-included-zlib=no \
  --disable-idn

# 5. Build
make -j$(nproc)

# 6. Install to a staging root
make install DESTDIR=/tmp/rsync-destroot
```

### Configure flags rationale

| Flag | Why |
|------|-----|
| `--enable-xattr-support` | Turn on xattr copying (needs the Haiku patch above) |
| `--with-included-zlib=no` | Use system zlib instead of the bundled copy |
| `--disable-iconv`, `--disable-iconv-open` | Matches HaikuPorts; avoids iconv charset issues |
| `--disable-locale` | Matches HaikuPorts |
| `--disable-idn` | `idn2.h` not present on the box (no effect on file transfer) |

A quirk worth knowing: after `autoconf`, `make` may trip over stale
`config.h.in` / `configure.sh` timestamps. Fix by `touch`ing those files (or
`make reconfigure`) before building.

---

## 6. Packaging

The binary is stripped (debug copy kept separately), then a `.PackageInfo` is
written and the `.hpkg` is produced with Haiku's `package create`.

Key `.PackageInfo` fields:

```
name            rsync
version         3.5.1-1
architecture    x86_64
provides {
    rsync = 3.5.1-1 compat >= 3
    cmd:rsync = 3.5.1-1
    cmd:rsync_ssl = 3.5.1-1      # underscores, not hyphens
}
requires {
    haiku >= r1~beta5
    lib:libcrypto >= 3
    lib:liblz4 >= 1
    lib:libxxhash
    lib:libzstd >= 1
    lib:libz >= 1
}
```

Files are staged with paths **relative to `/boot/system`** (`bin/rsync`,
`documentation/man/man1/...`), which is the Haiku package convention.
Note the man pages live under `documentation/man` — Haiku's `man` (mandoc)
reads **only** that tree, never `share/man`. The recipe gets this for free:
`runConfigure` passes `--mandir=$manDir` by default. The hand-build flow
configures with upstream defaults instead, so `build_haiku_rsync.sh`
re-roots `share/man` → `documentation/man` while staging (the original
hand-built package shipped `share/man`, making `man rsync` fail — fixed
2026-10-14).

### Packaging gotchas learned

- Resolvable names **cannot contain hyphens** → use `cmd:rsync_ssl`, not `cmd:rsync-ssl`.
- The `license` string must be a **recognized identifier** (`"GNU GPL v3"`),
  otherwise `package create` fails with *"License '…' isn't contained in package"*.

---

## 7. Verification

All tests ran on the lab machine against a Linux reference daemon (rsync
3.2.7) to prove real-world client behavior.

### Local operations
- Basic `-a` copy, recursive diff → identical ✔
- Man pages render: `man rsync`, `man rsyncd.conf` from
  `/boot/system/documentation/man` ✔ (mandoc prints a benign "outdated
  mandoc.db" note until the system index is refreshed — same as `man dig`)
- zstd compression + xxh128 checksum → identical ✔
- Symlink and permission preservation ✔
- xattr round-trip (via the new Haiku xattr backend) ✔

### Delta algorithm (the core of rsync)
- **Local, mid-file change:** 5 MB file, 100-byte change in the middle → sent
  only **71 bytes**. ✔
- **Over the network:** pulled from a Linux daemon; a **300-byte mid-file
  change to a 3 MB file transferred only 3,456 bytes** (matched 2,996,544). ✔
- **No-change re-sync:** 0 bytes transferred (20 bytes protocol overhead). ✔
- **Integrity:** MD5 of source (Linux) and destination (Haiku) matched exactly
  after every transfer. ✔

### Installed package
- `pkgman install` succeeded; `rsync` → `/boot/system/bin/rsync`. ✔
- `rsync --version` → 3.5.1, protocol 33. ✔
- Re-ran the network delta test using the **installed** binary → correct. ✔

> One red herring during testing: `@ERROR: setgroups failed` came from a
> misconfigured throwaway Linux daemon, **not** the Haiku client — it reproduced
> identically with the Linux rsync client. Resolved by simplifying the daemon
> config.

---

## 8. Repo layout

```
haiku-rsync/
├── rsync-3.5.1-1-x86_64.hpkg      # the deliverable (hand-built package)
├── src/
│   ├── rsync-3.5.1.tar.gz         # upstream source
│   ├── rsync-3.5.1.patchset       # Haiku platform patches (applied by the build)
│   └── rsync-3.2.7.patchset       # upstream HaikuPorts patch (reference only, not applied)
├── haikuports/                    # official HaikuPorts recipe (see section 11)
│   └── net-misc/rsync/
│       ├── rsync-3.5.1.recipe
│       └── patches/rsync-3.5.1.patchset
├── build_haiku_rsync.sh           # scripted build + package (runs on Haiku)
├── test_filter.sh                 # the filtered test-suite invocation
└── README.md                      # this document
```

---

## 9. Reproducing the build from scratch

1. Copy `src/rsync-3.5.1.tar.gz` and `src/rsync-3.5.1.patchset` to the Haiku
   machine.
2. Install build deps:
   `pkgman install zlib_devel zstd_devel xxhash_devel lz4_devel`
   (openssl3_devel is already present on the reference box).
3. Run `build_haiku_rsync.sh` (it extracts, patches, configures, builds,
   stages, and creates the `.hpkg` in `/boot/home/out/`).
4. Retrieve `/boot/home/out/rsync-3.5.1-1-x86_64.hpkg`.

---

## 10. Scope notes

- **x86_64 only**, as requested. No x86_gcc2 / secondary-arch build.
- **Client-focused.** The daemon mode works (it's compiled in) but the primary
  goal and testing was the client side.
- **iconv/locale/IDN disabled** — this does not affect normal file transfer; it
  only skips optional charset-name conversion and localized messages.
- Delivered two ways: a ready-to-install `.hpkg` **and** an official-format
  HaikuPorts recipe (section 11).

---

## 11. Official HaikuPorts recipe

`haikuports/net-misc/rsync/` holds a recipe in the canonical HaikuPorts layout,
validated end-to-end with the real `haikuporter` build tool (v1.5.3):

```
haikuports/
├── FormatVersions                 # RecipeFormatVersion=1 (tree requirement)
└── net-misc/rsync/
    ├── rsync-3.5.1.recipe
    └── patches/rsync-3.5.1.patchset
```

### Recipe contents
- **SOURCE_URI / CHECKSUM_SHA256** — upstream `download.samba.org`, checksum
  `c55f9c9d...` (verified).
- **PATCHES** — the same Haiku platform patch as section 3, in git-`patchset`
  format (`patches/rsync-3.5.1.patchset`), verified to apply cleanly with
  `patch -p1` to pristine source.
- **BUILD()** — `aclocal && autoconf`, then `runConfigure` with the flags from
  section 5, then `make reconfigure` + `make` (the `reconfigure` step is the
  correct fix for the `autoconf` timestamp issue noted in section 5).
- **INSTALL()** — `make install`.
- **TEST()** — runs `runtests.py` with an `--exclude` list of 16 tests that
  cannot pass on Haiku (all environmental, detailed below), after building the
  required helper programs.
- **`defineDebugInfoPackage`** — splits a `rsync_debuginfo` package, matching
  HaikuPorts convention.
- **PROVIDES/REQUIRES/BUILD_REQUIRES** — correct `lib:` provides resolved
  against the real packages (see section 4).

### Validation performed
| Check | Result |
|-------|--------|
| `haikuporter --lint rsync` | clean — no policy errors |
| `haikuporter -y rsync` (full chroot build) | **exit 0** — produced `rsync-3.5.1-1-x86_64.hpkg` + `rsync_debuginfo-3.5.1-1-x86_64.hpkg` with correct metadata |
| `haikuporter -y --test rsync` (TEST phase) | see test notes below |

The full build exercised the recipe's `runConfigure`, `make reconfigure`, and
the debuginfo split under haikuporter's chroot, producing a valid, correctly
packaged pair of `.hpkg` files.

### The 16 excluded tests (environmental, not rsync bugs)
The upstream suite cannot run green on Haiku because the target environment
lacks a few features. Excluded in `TEST()`:

| Cause | Tests |
|-------|-------|
| **Hard links unsupported** on the test filesystem (`os.link`/`ln`/`--link-dest` → `EPERM`) | `hands`, `hardlinks-deep`, `link-dest-pathroot`, `link-dest-relative-basis`, `operator-path-link-dest`, `relative`, `variety`, `variety-symlink-traversal`, `itemize`, `batch-only-remove-source-regression`, `rrsync-root-relative-paths`, `alt-dest-deep` |
| **No `nobody` user** (daemon default uid) | `daemon-config`, `chdir-symlink-race` |
| **umask/permission model** differs in the daemon path | `chmod-option` |
| **No device nodes** (`MAKEDEV` stubbed out) | `devices` |

With these excluded, the rest of the suite passes cleanly — re-verified
2026-10-14 via `haikuporter -y --test rsync`: **224 passed / 0 failed /
120 skipped, exit 0**. That run also fixed a TEST() gap: the three 3.5.x
security regression tests `rename-mixed-parent-escape-poc`,
`rename-mixed-parent-symlink-race` and `symlink-mknod-fakesuper-symlink-race`
need the `t_rename_secure` / `t_symlink_secure` helper programs, which
TEST() now builds (without them they abort with `FileNotFoundError`); all
three now pass on Haiku.

### Notes for upstreaming
- The recipe declares `ARCHITECTURES="all !x86_gcc2"` + `SECONDARY_ARCHITECTURES="x86"`
  (matching the existing rsync recipe); the platform patches are
  architecture-independent, but only **x86_64** was built and tested here.
- `cmd:python3` is a `BUILD_PREREQUIRES` (testsuite only) — the runtime package
  has **no** Python dependency.
- Before official submission you'd set a real `packager` identity and run
  `haikuporter -S` (strict policy) to confirm zero warnings.

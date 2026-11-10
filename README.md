# zp

Source-based package manager written in Zig.

[![Zig](https://img.shields.io/badge/Zig-0.17-orange)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

Fetch. Build. Install. From source; no prebuilt binaries.
<img width="633" height="723" alt="Image" src="https://github.com/user-attachments/assets/8c19a91d-dfe1-4f06-aff9-68ed180a0369" />

> **Selected as a reference implementation in the [XERJ Corpus Hub](https://hub.xerj.org/contributors/nevvixsz) for AI coding agents**, recognized for clean architecture and robust Zig implementation.

---

## Overview

`zp` fetches package source tarballs, auto-detects build systems, compiles and installs software. Inspired by CRUX/KISS Linux ports and Void `xbps-src`.

**Key characteristics**:
- Single static binary
- File tracking for clean package removal

---

## Features

- **Source-based installation**: complete `fetch → unpack → build → install` pipeline
- **File tracking**: tracks installed files for proper removal
- **Parallel downloads**: multiple packages download simultaneously

---

## How It Works

### Installation Flow

```
zp add <pkg>
   │
   ├─ 1. Lookup <pkg> in $HOME/.local/zp/mirrors/zp-repo/pkgs/<pkg>/<pkg>.zon
   ├─ 2. Download source tarball → $HOME/.local/zp/install/
   ├─ 3. Check sha256 hash
   ├─ 4. Extract → $HOME/.local/zp/build/<pkg> (tar --strip-components=1)
   ├─ 5. Compile the package
   ├─ 6. Copy staged files → system root (/)
   └─ 7. Write file list → /var/zp/installed/<pkg>.list
```

### Package Database

**Location**: `/var/zp/mirrors/zp-repo/pkgs/`  
**Format**: `<name.zon> <BuildFile> <update.json (for packages not from GitHub)>`

---

## Filesystem Layout

```
/var/zp/
├── build/           # Extracted source code (one dir per package)
├── install/         # Downloaded tarballs (cache)
├── pkg/             # Staging directory (make install DESTDIR)
├── installed/       # File lists for installed packages
│   ├── htop.list
│   └── curl.list
└── mirrors/         # Recipe trees
```

---

## Requirements

- **Tools**: `git`, `curl`, `tar` (for all packages)

---

## Installation

```bash
# Clone repository
git clone https://github.com/understratum/zp.git
cd zp

# Build
zig build

# Install binary (optional)
sudo cp zig-out/bin/zp /usr/local/bin/ # or /usr/bin/

# Sync package database
sudo zp sync
```

---

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `zp sync` | Update recipe trees and regenerate database |
| `zp add <pkg>` | Download, build, and install package |
| `zp remove <pkg>` | Remove installed package |
| `zp search <pkg>` | Search for package in database |
| `zp list` | List installed packages |
| `zp update [pkg]` | Update specific package or all packages |
| `zp version` | Show version information |
| `zp help` | Show help message |
| `zp clean` | Clear cache |

### Examples

```bash
# Sync database
sudo zp sync

# Search for package
zp search htop

# Install package
zp add htop

# List installed packages
zp list

# Remove package
sudo zp remove htop

# Update specific package
zp update htop

# Update all installed packages
zp update

# Clear cache (tar files)
zp clean
```

---

## Project Structure

```
zp/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── parser.zig
│   ├── types.zig
│   ├── libs/      // zsys and ConfigLib
│   └── actions/
│       ├── sync.zig
│       ├── add.zig
│       ├── remove.zig
│       ├── search.zig
│       ├── list.zig
│       ├── update.zig
│       ├── version.zig
│       └── help.zig
├── LICENSE
└── README.md
```

---

## Build

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseSafe
```
---

## Configuration

zp reads `/etc/zp/config.zon` (ZON format). Absent file = built-in
defaults; empty file = defaults with a warning; syntactically broken
file = hard error (zp refuses to guess).

```zig
.{
    // Work zone — zp's scratch space. Absolute.
    .root       = "/", // $HOME default

    // install prefix - where files actually land. Absolute.

    // Sub-paths are RELATIVE segments, joined as {root}/{sub}
    // Never absolute, never with a leading or trailing "/"
    .build_dir  = ".local/zp/build",
    .pkg_dir    = ".local/zp/pkg",
    .cache_dir  = ".local/zp/install",
    .mirror_dir = "/var/zp/mirrors", // only absolute path
    .db_dir     = "/var/zp/installed", // only absolute path
    .jobs       = 5 // nproc jobs
}
```

An absolute sub-path breaks this by construction (you get
`/var/zp//var/zp/build`). zp validates sub-paths on load and rejects
leading `/`

## BuildFile contract

A `BuildFile` is a POSIX `sh` script. zp runs it **without root**, with
`cwd` set to the package source dir, and the following variables
exported. Recipes must not contain paths, must not `cd`, and must not
call `nproc` — everything comes from the environment:

| Variable | Meaning |
|---|---|
| `ZP_SRC_DIR` | source tree; **already the cwd** |
| `ZP_DESTDIR` | staging prefix for `make install` / `cmake --install` |
| `ZP_BUILD_DIR` | work build root |
| `ZP_PKG_DIR` | work pkg root |
| `ZP_CACHE_DIR` | downloaded tarballs |
| `ZP_MIRROR_DIR` | cloned repos |
| `ZP_DB_DIR` | installed database |
| `ZP_JOBS` | parallelism (use instead of `$(nproc)`) |

A typical autotools recipe:

```sh
#!/bin/sh
set -eu
./configure --prefix=/usr
make -j"$ZP_JOBS"
make DESTDIR="$ZP_DESTDIR" install
```

### Privilege model

Build, fetch, extract and stage run **unprivileged**. Only the final
copy into root and the database write happen through the
privileged `zp __copy` chrootpoint (invoked via `sudo`). A
compromised or buggy `BuildFile` therefore cannot touch the live
system - it can only poison its own staging tree, which is discarded.
zp refuses to build as root outright (`geteuid() == 0` → error).

Because `BuildFile` is arbitrary code, anything it produces is treated
as hostile by construction: `__copy` walks the staging tree by fd,
never follows symlinks (`O_NOFOLLOW`), copies file content (never
hardlinks), recreates symlinks via `readlink`+`symlinkat`, and records
every path into the database atomically in the same pass.

---

## Contributing

Issues and pull requests are welcome. This is a learning project, so expect some rough edges.

---

## License

MIT © [understratum](https://github.com/understratum)

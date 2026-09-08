# zp

Source-based package manager written in Zig.

[![Zig](https://img.shields.io/badge/Zig-0.16-orange)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

Fetch. Build. Install. From source — no prebuilt binaries.
<img width="633" height="723" alt="Image" src="https://github.com/user-attachments/assets/8c19a91d-dfe1-4f06-aff9-68ed180a0369" />

---

## Overview

`zp` fetches package source tarballs, auto-detects build systems, compiles and installs software. Inspired by CRUX/KISS Linux ports and Void `xbps-src`.

**Key characteristics:**
- Single static binary, no runtime dependencies
- Package database from 3 upstream sources (Void, CRUX, KISS)
- Automatic build system detection (autotools, cmake, meson, make)
- File tracking for clean uninstallation

---

## Features

- **Source-based installation** — complete `fetch → unpack → build → install` pipeline
- **Build system auto-detection**:
  - `configure` (autotools)
  - `CMakeLists.txt` (cmake)
  - `meson.build` (meson)
  - `setup.py` (python)
  - `cargo build` (rust)
  - `build.zig` (zig)
  - `Makefile` / `makefile` / `GNUmakefile` (make)
- **Multi-source package database** — aggregates recipes from Void, CRUX, and KISS Linux
- **Deterministic deduplication** — one name = one package, priority: `void > crux > kiss`
- **File tracking** — tracks installed files for proper removal
- **Parallel downloads** — multiple packages download simultaneously

---

## How It Works

### Installation Flow

```
zp add <pkg>
   │
   ├─ 1. Lookup <pkg> in /var/zp/mirrors/zp.packages
   ├─ 2. Download source tarball → /var/zp/install/
   ├─ 3. Extract → /var/zp/build/<pkg> (tar --strip-components=1)
   ├─ 4. Detect build system and compile:
   │      • autotools: ./configure --prefix=/usr && make && make install DESTDIR=/var/zp/pkg
   │      • cmake:     cmake -B _zb -DCMAKE_INSTALL_PREFIX=/usr && cmake --build _zb && cmake --install _zb
   │      • meson:     meson setup _zb --prefix=/usr && meson compile -C _zb && meson install -C _zb
   │      • make:      make && make install DESTDIR=/var/zp/pkg
   ├─ 5. Copy staged files → system root (/)
   └─ 6. Write file list → /var/zp/installed/<pkg>.list
```

### Package Database

**Location:** `/var/zp/mirrors/zp.packages`  
**Format:** `<name> <version> <url>` (space-separated, one package per line)

**Generation:** `gen.sh` script (created by `zp init`)
1. Clones/updates recipe trees from Void, CRUX, KISS
2. Parses recipe formats:
   - Void: `template` files
   - CRUX: `Pkgfile`
   - KISS: `sources`
3. Normalizes download URLs
4. Deduplicates by name (first source wins)

**Example entry:**
```
htop 3.5.3 https://github.com/htop-dev/htop/releases/download/3.5.3/htop-3.5.3.tar.xz
```

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
└── mirrors/         # Recipe trees + gen.sh + zp.packages
```

---

## Requirements

- **Zig 0.16** (compiler)
- **Build tools:** `git`, `curl`, `tar`, `cargo` (for rust pkgs), `python` (for python pkgs)
- **C toolchain:** `gcc`, `make` (for building packages)

---

## Installation

```bash
# Clone repository
git clone https://github.com/nevvixsz/zp.git
cd zp

# Build
zig build

# Install binary (optional)
sudo cp zig-out/bin/zp /usr/local/bin/

# Initialize zp directories
sudo zp init

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

### Examples

```bash
# Sync database
sudo zp sync

# Search for package
zp search htop

# Install package
sudo zp add htop

# List installed packages
zp list

# Remove package
sudo zp remove htop

# Update specific package
sudo zp update htop

# Update all installed packages
sudo zp update
```

---

## Project Structure

```
zp/
├── build.zig          # Build configuration
├── build.zig.zon      # Package manifest
├── src/
│   ├── main.zig       # Entry point, argument parsing
│   ├── parser.zig     # Database parsing, file operations
│   ├── types.zig      # Type definitions, constants
│   └── actions/
│       ├── sync.zig   # zp sync
│       ├── add.zig    # zp add
│       ├── remove.zig # zp remove
│       ├── search.zig # zp search
│       ├── list.zig   # zp list
│       ├── update.zig # zp update
│       ├── version.zig
│       └── help.zig
├── LICENSE
└── README.md
```

---

## Development

### Build

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseSafe
```
---

## Known Limitations

- **No dependency resolution** - packages must be installed manually in correct order
- **No rollback** - failed builds leave partial state
- **Single-threaded builds** - `make -j` parallelism only within package
- **Requires root** - installation writes to system directories

---

## Contributing

Issues and pull requests welcome. This is a learning project — expect rough edges.

**Workflow:**
1. Fork repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -m "feat: description"`
4. Push to fork: `git push origin feature/my-feature`
5. Create pull request to `understrata/zp`

---


## License

MIT © [nevvixsz](https://github.com/understrata)

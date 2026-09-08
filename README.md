# zp

Source-based package manager written in Zig.

[![Zig](https://img.shields.io/badge/Zig-0.16-orange)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

Fetch. Build. Install. From source; no prebuilt binaries.
<img width="633" height="723" alt="Image" src="https://github.com/user-attachments/assets/8c19a91d-dfe1-4f06-aff9-68ed180a0369" />

---

## Overview

`zp` fetches package source tarballs, auto-detects build systems, compiles and installs software. Inspired by CRUX/KISS Linux ports and Void `xbps-src`.

**Key characteristics**:
- Single static binary
- Void's package database
- Automatic build system detection (autotools, cmake, meson, make)
- File tracking for clean package removal

---

## Features

- **Source-based installation**: complete `fetch → unpack → build → install` pipeline
- **Build system auto-detection**:
  - `configure` (autotools)
  - `CMakeLists.txt` (cmake)
  - `meson.build` (meson)
  - `setup.py` (python)
  - `cargo build` (rust)
  - `build.zig` (zig)
  - `Makefile` / `makefile` / `GNUmakefile` (make)
- **File tracking**: tracks installed files for proper removal
- **Parallel downloads**: multiple packages download simultaneously

---

## How It Works

### Installation Flow

```
zp add <pkg>
   │
   ├─ 1. Lookup <pkg> in /var/zp/mirrors/zp.packages
   ├─ 2. Download source tarball → /var/zp/install/
   ├─ 3. Extract → /var/zp/build/<pkg> (tar --strip-components=1)
   ├─ 4. Detect the build system and then compile the package
   ├─ 5. Copy staged files → system root (/)
   └─ 6. Write file list → /var/zp/installed/<pkg>.list
```

### Package Database

**Location**: `/var/zp/mirrors/zp.packages`  
**Format**: `<name> <version> <url>` (space-separated, one package per line)
**Example entry**:
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
└── mirrors/         # Recipe trees + zp.packages
```

---

## Requirements

- **Tools**: `git`, `curl`, `tar`
- **C**: `gcc`, `make` (for building packages)
- **Zig**: `zig` 0.16.0 (for zig packages and `zp` itself)
- **Rust**: `cargo` (for rust packages)
- **Python**: `python` (for python packages)

---

## Installation

```bash
# Clone repository
git clone https://github.com/understratum/zp.git
cd zp

# Build
zig build

# Install binary (optional)
sudo cp zig-out/bin/zp /usr/local/bin/

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
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── parser.zig
│   ├── types.zig
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

## Known Limitations

- **No dependency resolution**: packages must be installed manually in correct order
- **No rollback**: failed builds leave partial state
- **Requires root**: installation writes to system directories

---

## Contributing

Issues and pull requests are welcome. This is a learning project, so expect some rough edges.

---

## License

MIT © [understratum](https://github.com/understratum)

# Disk Audit

**A single-file macOS disk cleanup tool for developers.** No installs, no dependencies, no flags — just run it.

Disk Audit scans 15 categories of reclaimable space (Xcode, Docker, node\_modules, package caches, browser caches, build artifacts, and more), classifies each as **SAFE** or **CAUTION**, and lets you interactively clean up what you choose.

```
    ╔══════════════════════════════════════════════════════════════╗
    ║       ██████╗ ██╗███████╗██╗  ██╗                            ║
    ║       ██╔══██╗██║██╔════╝██║ ██╔╝                            ║
    ║       ██║  ██║██║███████╗█████╔╝                             ║
    ║       ██║  ██║██║╚════██║██╔═██╗                             ║
    ║       ██████╔╝██║███████║██║  ██╗                            ║
    ║       ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝                            ║
    ║                 A U D I T                                    ║
    ╚══════════════════════════════════════════════════════════════╝
```

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/benbreaksin/macos-disk-audit/main/disk-audit.sh -o disk-audit.sh
chmod +x disk-audit.sh
./disk-audit.sh
```

Or clone and run:

```bash
git clone https://github.com/benbreaksin/macos-disk-audit.git
cd disk-audit
./disk-audit.sh
```

> **Requirements:** macOS, Bash 3.2+ (ships with macOS). No other dependencies.

---

## What It Scans

| # | Category | Safety | What It Finds |
|---|----------|--------|---------------|
| 1 | Trash | SAFE | `~/.Trash/` |
| 2 | System & App Temp Files | SAFE | `/tmp`, `/private/var/folders`, `$TMPDIR` |
| 3 | OS-Generated Junk | SAFE | `.DS_Store`, `._*` resource fork files |
| 4 | Logs & Crash Reports | SAFE | `~/Library/Logs/`, `/cores/` |
| 5 | Xcode Caches & Data | SAFE | DerivedData, Device Support, CoreSimulator, Archives |
| 6 | Build Artifacts | SAFE | `build/`, `dist/`, `.next/`, `.nuxt/`, `target/`, `coverage/`, etc. |
| 7 | Dependency Directories | SAFE | `node_modules/`, `__pycache__/`, `.venv/`, `vendor/`, `Pods/`, `.gradle/` |
| 8 | Compiled & Generated Files | SAFE | `*.pyc`, `*.o`, `*.dSYM` bundles |
| 9 | Package Manager Caches | SAFE | Homebrew, npm, pnpm, Yarn, pip, Cargo, CocoaPods, Go modules, gem |
| 10 | IDE & Editor Junk | SAFE | `.idea/` directories, `*.swp`, `*.swo`, `*~` files |
| 11 | Browser Caches | SAFE | Chrome, Safari, Firefox, Arc |
| 12 | Docker | CAUTION | Docker VM disk image, images, containers, volumes |
| 13 | Forgotten Databases | CAUTION | `*.sqlite`, `*.db` files in project directories |
| 14 | Old Downloads & Installers | CAUTION | Files 90+ days old, `.dmg`, `.pkg`, `.iso` in `~/Downloads/` |
| 15 | Miscellaneous App Caches | SAFE | Spotify, Slack, Discord caches |

**SAFE** = Regenerable caches and temp files. Delete without worry.
**CAUTION** = May contain data you care about. Review before deleting.

---

## Features

- **Zero configuration** — run it, get results. No flags, no config files.
- **Smart detection** — validates build directories by checking for project markers (`package.json`, `Cargo.toml`, `Podfile`, etc.) before flagging them. Won't misidentify random `build/` folders.
- **Safety classification** — every finding is labeled SAFE or CAUTION so you know what's risk-free.
- **Interactive cleanup** — choose to clean all SAFE items, or pick specific categories one at a time. Every deletion requires confirmation.
- **Top N view** — see the 20 largest items across all categories at a glance.
- **Category drill-down** — explore any category to see individual paths and sizes.
- **Report export** — save a plain-text report to your Desktop.
- **Re-scan** — clean something, then re-scan to verify the space was reclaimed.
- **Progress bar** — real-time scan progress so you know it's working.

---

## Usage

Just run it:

```bash
./disk-audit.sh
```

After the scan completes, you'll see a sorted results table and an interactive menu:

```
  ═══ What would you like to do? ═══

  [1] View detailed breakdown by category
  [2] View top 20 largest items
  [3] Clean up SAFE items (interactive)
  [4] Clean up specific category
  [5] Export report to file
  [6] Re-scan
  [q] Quit
```

### Cleanup Modes

**Option 3 — Clean SAFE items:** Walks through every SAFE category sorted by size. You confirm each one individually with `y/N`.

**Option 4 — Clean specific category:** Pick one category from the list, review it, and decide whether to clean it.

Nothing is ever deleted without an explicit `y` confirmation.

---

## How It Works

1. Scans your home directory and system paths using `find` and `du`
2. Categorizes findings into 15 buckets with safety ratings
3. Stores results in temporary files (auto-cleaned on exit)
4. Presents an interactive TUI for exploration and cleanup
5. Cleanup uses the appropriate tool for each category (e.g., `brew cleanup`, `npm cache clean`, `xcrun simctl delete unavailable`) rather than raw `rm` where possible

---

## FAQ

**Will it delete anything without asking?**
No. Every deletion requires you to type `y` and press Enter.

**Does it need sudo?**
No. It runs as your user and scans what your user has access to. Some system temp directories may show reduced sizes without sudo, but it works fine without it.

**Will it break my projects?**
SAFE items are all caches, temp files, and build artifacts that are regenerated automatically when you next build or install. CAUTION items (databases, downloads, Docker) are flagged precisely because they *could* contain important data.

**How long does the scan take?**
Typically 10–30 seconds depending on how many projects and files are on your drive.

**Does it work on Linux?**
No. It's purpose-built for macOS (uses macOS-specific paths like `~/Library/`, Homebrew conventions, Xcode paths, etc.).

---

## License

MIT License — do whatever you want with it.

```
MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

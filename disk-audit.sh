#!/usr/bin/env bash
# disk-audit.sh — macOS Disk Audit & Cleanup Tool
# Scans the full drive, categorizes developer/system waste,
# reports what's safe to delete, sorted by space used.
# Fully interactive — no flags needed.

# No set -e: scanning commands often return non-zero (permission denied, etc.)
# We handle errors explicitly per-command.

# ─── Constants ────────────────────────────────────────────────────
VERSION="1.0.0"
TOTAL_CATEGORIES=15
HOME_DIR="$HOME"
RESULTS_FILE=""
ITEMS_FILE=""
FREED_TOTAL_KB=0

# ─── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Utility Functions ────────────────────────────────────────────

human_readable() {
    local kb="${1:-0}"
    kb="${kb:-0}"
    if [ "$kb" -ge 1073741824 ] 2>/dev/null; then
        printf "%.1f TB" "$(echo "scale=1; $kb / 1073741824" | bc)"
    elif [ "$kb" -ge 1048576 ]; then
        printf "%.1f GB" "$(echo "scale=1; $kb / 1048576" | bc)"
    elif [ "$kb" -ge 1024 ]; then
        printf "%.1f MB" "$(echo "scale=1; $kb / 1024" | bc)"
    else
        printf "%d KB" "$kb"
    fi
}

du_safe() {
    local result
    result=$(du -sk "$1" 2>/dev/null | cut -f1)
    if [ -z "$result" ]; then
        echo "0"
    else
        echo "$result"
    fi
}

count_files() {
    find "$1" -type f 2>/dev/null | wc -l | tr -d ' '
}

count_items() {
    local dir="$1"
    ls -1A "$dir" 2>/dev/null | wc -l | tr -d ' '
}

dir_exists() {
    [ -d "$1" ]
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Add a finding to the results file
# Format: SAFETY|CATEGORY|SIZE_KB|FILE_COUNT|PATH|CLEANUP_CMD
add_finding() {
    local safety="$1" category="$2" size_kb="${3:-0}" count="${4:-0}" path="$5" cleanup="$6"
    size_kb="${size_kb:-0}"
    [ "$size_kb" -gt 0 ] 2>/dev/null && \
        echo "${safety}|${category}|${size_kb}|${count}|${path}|${cleanup}" >> "$RESULTS_FILE"
    return 0
}

# Add individual item for top-N listing
# Format: SAFETY|CATEGORY|SIZE_KB|PATH
add_item() {
    local safety="$1" category="$2" size_kb="${3:-0}" path="$4"
    size_kb="${size_kb:-0}"
    [ "$size_kb" -gt 0 ] 2>/dev/null && \
        echo "${safety}|${category}|${size_kb}|${path}" >> "$ITEMS_FILE"
    return 0
}

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local label="$3"
    local width=30
    local filled=$((current * width / total))
    local empty=$((width - filled))
    local bar=""
    local i=0
    while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i + 1)); done
    i=0
    while [ $i -lt $empty ]; do bar="${bar}░"; i=$((i + 1)); done
    printf "\r  ${CYAN}[${bar}]${RESET} ${WHITE}%-45s${RESET} ${DIM}(%d/%d)${RESET}" "$label" "$current" "$total"
}

clear_line() {
    printf "\r%-80s\r" ""
}

safety_color() {
    case "$1" in
        SAFE)    echo -n "$GREEN" ;;
        CAUTION) echo -n "$YELLOW" ;;
        DANGER)  echo -n "$RED" ;;
        *)       echo -n "$RESET" ;;
    esac
}

# ─── Welcome Screen ──────────────────────────────────────────────

print_welcome() {
    clear
    echo ""
    printf "${CYAN}"
    cat << 'BANNER'
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║       ██████╗ ██╗███████╗██╗  ██╗                            ║
    ║       ██╔══██╗██║██╔════╝██║ ██╔╝                            ║
    ║       ██║  ██║██║███████╗█████╔╝                             ║
    ║       ██║  ██║██║╚════██║██╔═██╗                             ║
    ║       ██████╔╝██║███████║██║  ██╗                            ║
    ║       ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝                            ║
    ║                 A U D I T                                    ║
    ║                                                              ║
    ║       macOS Disk Audit & Cleanup Tool  v1.0.0                ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
BANNER
    printf "${RESET}"
    echo ""

    # Disk overview
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1)
    local disk_total disk_used disk_avail disk_pct
    disk_total=$(echo "$disk_info" | awk '{print $2}')
    disk_used=$(echo "$disk_info" | awk '{print $3}')
    disk_avail=$(echo "$disk_info" | awk '{print $4}')
    disk_pct=$(echo "$disk_info" | awk '{print $5}')

    printf "  ${WHITE}Host:${RESET}  %s\n" "$(hostname)"
    printf "  ${WHITE}Date:${RESET}  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf "  ${WHITE}Disk:${RESET}  %s total  |  %s used (%s)  |  %s available\n" \
        "$disk_total" "$disk_used" "$disk_pct" "$disk_avail"
    echo ""
    printf "  ${DIM}Scanning your system for reclaimable space...${RESET}\n"
    echo ""
}

# ─── Scan Functions ───────────────────────────────────────────────

scan_trash() {
    progress_bar 1 $TOTAL_CATEGORIES "Trash"
    local trash_dir="$HOME_DIR/.Trash"
    if dir_exists "$trash_dir"; then
        local size_kb
        size_kb=$(du_safe "$trash_dir")
        local count
        count=$(count_items "$trash_dir")
        add_finding "SAFE" "Trash" "$size_kb" "$count" "$trash_dir/" "rm -rf $trash_dir/*"
        add_item "SAFE" "Trash" "$size_kb" "$trash_dir/"
    fi
}

scan_system_temp() {
    progress_bar 2 $TOTAL_CATEGORIES "System & App Temp Files"
    local total_kb=0
    local total_count=0

    # /tmp
    if dir_exists "/tmp"; then
        local sz
        sz=$(du_safe "/tmp")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "System Temp" "$sz" "/tmp/"
    fi

    # /private/var/folders (user temp)
    if dir_exists "/private/var/folders"; then
        local sz
        sz=$(du_safe "/private/var/folders")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "System Temp" "$sz" "/private/var/folders/"
    fi

    # TMPDIR
    if [ -n "${TMPDIR:-}" ] && dir_exists "$TMPDIR"; then
        local sz
        sz=$(du_safe "$TMPDIR")
        # avoid double-counting if TMPDIR is under /private/var/folders
        case "$TMPDIR" in
            /private/var/folders*) ;;
            *) total_kb=$((total_kb + sz))
               add_item "SAFE" "System Temp" "$sz" "$TMPDIR" ;;
        esac
    fi

    total_count=$(find /tmp -type f 2>/dev/null | wc -l | tr -d ' ')
    total_count="${total_count:-0}"
    add_finding "SAFE" "System & App Temp Files" "$total_kb" "$total_count" "/tmp, /private/var/folders" "rm -rf /tmp/* (requires sudo)"
}

scan_os_junk() {
    progress_bar 3 $TOTAL_CATEGORIES "OS-Generated Junk (.DS_Store, etc.)"
    local total_kb=0
    local total_count=0

    # .DS_Store files
    local ds_count ds_kb
    ds_count=$(find "$HOME_DIR" -maxdepth 6 -name ".DS_Store" -type f 2>/dev/null | wc -l | tr -d ' ')
    # Estimate: each .DS_Store is ~6-12KB
    ds_kb=$((ds_count * 8))
    total_kb=$((total_kb + ds_kb))
    total_count=$((total_count + ds_count))

    # ._ resource fork files
    local rf_result
    rf_result=$(find "$HOME_DIR" -maxdepth 6 -name "._*" -type f 2>/dev/null | head -5000 | wc -l | tr -d ' ')
    local rf_kb=$((rf_result * 4))
    total_kb=$((total_kb + rf_kb))
    total_count=$((total_count + rf_result))

    add_finding "SAFE" "OS-Generated Junk" "$total_kb" "$total_count" "~/ (.DS_Store, ._* files)" "find ~ -name '.DS_Store' -delete && find ~ -name '._*' -delete"
    add_item "SAFE" "OS-Generated Junk" "$total_kb" "~/ (.DS_Store, ._* files)"
}

scan_logs() {
    progress_bar 4 $TOTAL_CATEGORIES "Logs & Crash Reports"
    local total_kb=0
    local total_count=0

    # ~/Library/Logs
    if dir_exists "$HOME_DIR/Library/Logs"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Logs")
        total_kb=$((total_kb + sz))
        local c
        c=$(count_files "$HOME_DIR/Library/Logs")
        total_count=$((total_count + c))
        add_item "SAFE" "Logs & Crash Reports" "$sz" "~/Library/Logs/"
    fi

    # /cores (core dumps)
    if dir_exists "/cores"; then
        local sz
        sz=$(du -sk /cores 2>/dev/null | cut -f1 || echo "0")
        if [ "$sz" -gt 0 ] 2>/dev/null; then
            total_kb=$((total_kb + sz))
            add_item "SAFE" "Logs & Crash Reports" "$sz" "/cores/"
        fi
    fi

    add_finding "SAFE" "Logs & Crash Reports" "$total_kb" "$total_count" "~/Library/Logs/, /cores/" "rm -rf ~/Library/Logs/* /cores/*"
}

scan_xcode() {
    progress_bar 5 $TOTAL_CATEGORIES "Xcode Caches & Data"
    local total_kb=0
    local total_count=0
    local xcode_base="$HOME_DIR/Library/Developer"

    # DerivedData
    if dir_exists "$xcode_base/Xcode/DerivedData"; then
        local sz
        sz=$(du_safe "$xcode_base/Xcode/DerivedData")
        local c
        c=$(count_items "$xcode_base/Xcode/DerivedData")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + c))
        add_finding "SAFE" "Xcode DerivedData" "$sz" "$c" "~/Library/Developer/Xcode/DerivedData/" "rm -rf ~/Library/Developer/Xcode/DerivedData/*"
        add_item "SAFE" "Xcode DerivedData" "$sz" "~/Library/Developer/Xcode/DerivedData/"
    fi

    # iOS DeviceSupport
    if dir_exists "$xcode_base/Xcode/iOS DeviceSupport"; then
        local sz
        sz=$(du_safe "$xcode_base/Xcode/iOS DeviceSupport")
        local c
        c=$(count_items "$xcode_base/Xcode/iOS DeviceSupport")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + c))
        add_finding "SAFE" "Xcode Device Support" "$sz" "$c" "~/Library/Developer/Xcode/iOS DeviceSupport/" "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/*"
        add_item "SAFE" "Xcode Device Support" "$sz" "~/Library/Developer/Xcode/iOS DeviceSupport/"
    fi

    # CoreSimulator
    if dir_exists "$xcode_base/CoreSimulator"; then
        local sz
        sz=$(du_safe "$xcode_base/CoreSimulator")
        total_kb=$((total_kb + sz))
        add_finding "SAFE" "Xcode Simulators" "$sz" "—" "~/Library/Developer/CoreSimulator/" "xcrun simctl delete unavailable"
        add_item "SAFE" "Xcode Simulators" "$sz" "~/Library/Developer/CoreSimulator/"
    fi

    # Xcode caches
    if dir_exists "$HOME_DIR/Library/Caches/com.apple.dt.Xcode"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/com.apple.dt.Xcode")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Xcode Caches" "$sz" "~/Library/Caches/com.apple.dt.Xcode/"
    fi

    # Archives (CAUTION)
    if dir_exists "$xcode_base/Xcode/Archives"; then
        local sz
        sz=$(du_safe "$xcode_base/Xcode/Archives")
        local c
        c=$(count_items "$xcode_base/Xcode/Archives")
        if [ "$sz" -gt 0 ] 2>/dev/null; then
            add_finding "CAUTION" "Xcode Archives" "$sz" "$c" "~/Library/Developer/Xcode/Archives/" "rm -rf ~/Library/Developer/Xcode/Archives/*"
            add_item "CAUTION" "Xcode Archives" "$sz" "~/Library/Developer/Xcode/Archives/"
        fi
    fi
}

scan_build_artifacts() {
    progress_bar 6 $TOTAL_CATEGORIES "Build Artifacts"
    local total_kb=0
    local total_count=0

    # Project markers that validate a build directory
    # We look for build dirs only where a recognized project file exists nearby
    local build_dirs
    build_dirs=$(find "$HOME_DIR" -maxdepth 6 -type d \
        \( -name ".Trash" -o -name "Library" -o -name ".npm" -o -name ".cargo" \
           -o -name ".rustup" -o -name "node_modules" -o -name ".git" \) -prune \
        -o -type d \( \
            -name "build" -o -name "dist" -o -name ".next" -o -name ".nuxt" \
            -o -name ".output" -o -name ".svelte-kit" -o -name ".parcel-cache" \
            -o -name ".turbo" -o -name ".webpack" -o -name "coverage" \
            -o -name ".nyc_output" \
        \) -print 2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local parent
        parent=$(dirname "$dir")
        local dirname
        dirname=$(basename "$dir")

        # Validate: for generic names, require a project marker
        local valid=false
        case "$dirname" in
            build)
                [ -f "$parent/package.json" ] || [ -f "$parent/Makefile" ] || \
                [ -f "$parent/CMakeLists.txt" ] || [ -f "$parent/build.gradle" ] || \
                [ -f "$parent/build.gradle.kts" ] || [ -f "$parent/meson.build" ] && valid=true
                ;;
            dist)
                [ -f "$parent/package.json" ] || [ -f "$parent/setup.py" ] || \
                [ -f "$parent/pyproject.toml" ] && valid=true
                ;;
            .next|.nuxt|.output|.svelte-kit|.parcel-cache|.turbo|.webpack)
                valid=true ;;
            coverage|.nyc_output)
                [ -f "$parent/package.json" ] && valid=true ;;
        esac

        if [ "$valid" = true ]; then
            local sz
            sz=$(du_safe "$dir")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "SAFE" "Build Artifacts" "$sz" "$dir/"
        fi
    done <<< "$build_dirs"

    # Also check target/ dirs (Rust/Java)
    local target_dirs
    target_dirs=$(find "$HOME_DIR" -maxdepth 5 -type d -name "target" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local parent
        parent=$(dirname "$dir")
        if [ -f "$parent/Cargo.toml" ] || [ -f "$parent/pom.xml" ]; then
            local sz
            sz=$(du_safe "$dir")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "SAFE" "Build Artifacts" "$sz" "$dir/"
        fi
    done <<< "$target_dirs"

    add_finding "SAFE" "Build Artifacts" "$total_kb" "$total_count" "Various project build directories" "Delete individual build dirs"
}

scan_dependencies() {
    progress_bar 7 $TOTAL_CATEGORIES "Dependency Directories"
    local total_kb=0
    local total_count=0

    # node_modules (top-level only, prune to avoid descending)
    local nm_dirs
    nm_dirs=$(find "$HOME_DIR" -maxdepth 6 -type d -name "node_modules" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" \) \
        -prune 2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local sz
        sz=$(du_safe "$dir")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + 1))
        add_item "SAFE" "Dependencies" "$sz" "$dir/"
    done <<< "$nm_dirs"

    # __pycache__
    local pyc_dirs
    pyc_dirs=$(find "$HOME_DIR" -maxdepth 6 -type d -name "__pycache__" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local sz
        sz=$(du_safe "$dir")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + 1))
    done <<< "$pyc_dirs"

    # .venv / venv
    local venv_dirs
    venv_dirs=$(find "$HOME_DIR" -maxdepth 5 -type d \( -name ".venv" -o -name "venv" \) \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        # Verify it's a Python venv
        if [ -f "$dir/pyvenv.cfg" ] || [ -f "$dir/bin/python" ]; then
            local sz
            sz=$(du_safe "$dir")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "SAFE" "Dependencies" "$sz" "$dir/"
        fi
    done <<< "$venv_dirs"

    # vendor/ (PHP Composer or Ruby Bundler)
    local vendor_dirs
    vendor_dirs=$(find "$HOME_DIR" -maxdepth 5 -type d -name "vendor" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local parent
        parent=$(dirname "$dir")
        if [ -f "$parent/composer.json" ] || [ -f "$parent/Gemfile" ]; then
            local sz
            sz=$(du_safe "$dir")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "SAFE" "Dependencies" "$sz" "$dir/"
        fi
    done <<< "$vendor_dirs"

    # Pods/
    local pods_dirs
    pods_dirs=$(find "$HOME_DIR" -maxdepth 5 -type d -name "Pods" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local parent
        parent=$(dirname "$dir")
        if [ -f "$parent/Podfile" ]; then
            local sz
            sz=$(du_safe "$dir")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "SAFE" "Dependencies" "$sz" "$dir/"
        fi
    done <<< "$pods_dirs"

    # .gradle in project dirs
    local gradle_dirs
    gradle_dirs=$(find "$HOME_DIR" -maxdepth 5 -type d -name ".gradle" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local parent
        parent=$(dirname "$dir")
        if [ -f "$parent/build.gradle" ] || [ -f "$parent/build.gradle.kts" ]; then
            local sz
            sz=$(du_safe "$dir")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "SAFE" "Dependencies" "$sz" "$dir/"
        fi
    done <<< "$gradle_dirs"

    add_finding "SAFE" "Dependency Directories" "$total_kb" "$total_count" "node_modules, __pycache__, .venv, Pods, etc." "Delete individual dependency dirs"
}

scan_compiled_files() {
    progress_bar 8 $TOTAL_CATEGORIES "Compiled & Generated Files"
    local total_kb=0
    local total_count=0

    # .pyc files (measure actual sizes)
    local pyc_kb=0
    local pyc_count=0
    local pyc_result
    pyc_result=$(find "$HOME_DIR" -maxdepth 6 -name "*.pyc" -type f \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        -print0 2>/dev/null | xargs -0 du -sk 2>/dev/null | awk '{s+=$1; c++} END {printf "%d %d", s+0, c+0}')
    pyc_kb=$(echo "$pyc_result" | awk '{print $1}')
    pyc_count=$(echo "$pyc_result" | awk '{print $2}')
    pyc_kb="${pyc_kb:-0}"
    pyc_count="${pyc_count:-0}"
    total_kb=$((total_kb + pyc_kb))
    total_count=$((total_count + pyc_count))

    # .o object files (measure actual sizes)
    local o_kb=0
    local o_count=0
    local o_result
    o_result=$(find "$HOME_DIR" -maxdepth 6 -name "*.o" -type f -size +1k \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null | head -5000 | tr '\n' '\0' | xargs -0 du -sk 2>/dev/null | awk '{s+=$1; c++} END {printf "%d %d", s+0, c+0}')
    o_kb=$(echo "$o_result" | awk '{print $1}')
    o_count=$(echo "$o_result" | awk '{print $2}')
    o_kb="${o_kb:-0}"
    o_count="${o_count:-0}"
    total_kb=$((total_kb + o_kb))
    total_count=$((total_count + o_count))

    # .dSYM bundles (debug symbols, can be huge)
    local dsym_dirs
    dsym_dirs=$(find "$HOME_DIR" -maxdepth 6 -name "*.dSYM" -type d \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local sz
        sz=$(du_safe "$dir")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + 1))
        add_item "SAFE" "Compiled Files" "$sz" "$dir"
    done <<< "$dsym_dirs"

    add_finding "SAFE" "Compiled & Generated Files" "$total_kb" "$total_count" "*.pyc, *.o, *.dSYM, etc." "find ~ -name '*.pyc' -delete"
}

scan_package_caches() {
    progress_bar 9 $TOTAL_CATEGORIES "Package Manager Caches"
    local total_kb=0
    local total_count=0

    # Homebrew
    if cmd_exists brew; then
        local brew_cache
        brew_cache=$(brew --cache 2>/dev/null || echo "$HOME_DIR/Library/Caches/Homebrew")
        if dir_exists "$brew_cache"; then
            local sz
            sz=$(du_safe "$brew_cache")
            local c
            c=$(count_files "$brew_cache")
            total_kb=$((total_kb + sz))
            total_count=$((total_count + c))
            add_finding "SAFE" "Homebrew Cache" "$sz" "$c" "$brew_cache" "brew cleanup --prune=all"
            add_item "SAFE" "Package Caches" "$sz" "$brew_cache/"
        fi
    fi

    # npm
    if dir_exists "$HOME_DIR/.npm"; then
        local sz
        sz=$(du_safe "$HOME_DIR/.npm")
        local c
        c=$(count_files "$HOME_DIR/.npm")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + c))
        add_finding "SAFE" "npm Cache" "$sz" "$c" "~/.npm/" "npm cache clean --force"
        add_item "SAFE" "Package Caches" "$sz" "~/.npm/"
    fi

    # pnpm
    local pnpm_store="$HOME_DIR/Library/pnpm/store"
    if dir_exists "$pnpm_store"; then
        local sz
        sz=$(du_safe "$pnpm_store")
        total_kb=$((total_kb + sz))
        add_finding "SAFE" "pnpm Store" "$sz" "—" "$pnpm_store/" "pnpm store prune"
        add_item "SAFE" "Package Caches" "$sz" "$pnpm_store/"
    fi

    # Yarn
    if dir_exists "$HOME_DIR/.yarn/cache"; then
        local sz
        sz=$(du_safe "$HOME_DIR/.yarn/cache")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Package Caches" "$sz" "~/.yarn/cache/"
    fi
    if dir_exists "$HOME_DIR/Library/Caches/Yarn"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/Yarn")
        total_kb=$((total_kb + sz))
        add_finding "SAFE" "Yarn Cache" "$sz" "—" "~/Library/Caches/Yarn/" "yarn cache clean"
        add_item "SAFE" "Package Caches" "$sz" "~/Library/Caches/Yarn/"
    fi

    # pip
    if dir_exists "$HOME_DIR/Library/Caches/pip"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/pip")
        local c
        c=$(count_files "$HOME_DIR/Library/Caches/pip")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + c))
        add_finding "SAFE" "pip Cache" "$sz" "$c" "~/Library/Caches/pip/" "pip cache purge"
        add_item "SAFE" "Package Caches" "$sz" "~/Library/Caches/pip/"
    fi

    # Cargo
    if dir_exists "$HOME_DIR/.cargo/registry"; then
        local sz
        sz=$(du_safe "$HOME_DIR/.cargo/registry")
        total_kb=$((total_kb + sz))
        add_finding "SAFE" "Cargo Registry Cache" "$sz" "—" "~/.cargo/registry/" "cargo cache --autoclean"
        add_item "SAFE" "Package Caches" "$sz" "~/.cargo/registry/"
    fi
    if dir_exists "$HOME_DIR/.cargo/git"; then
        local sz
        sz=$(du_safe "$HOME_DIR/.cargo/git")
        total_kb=$((total_kb + sz))
    fi

    # CocoaPods
    if dir_exists "$HOME_DIR/Library/Caches/CocoaPods"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/CocoaPods")
        total_kb=$((total_kb + sz))
        add_finding "SAFE" "CocoaPods Cache" "$sz" "—" "~/Library/Caches/CocoaPods/" "pod cache clean --all"
        add_item "SAFE" "Package Caches" "$sz" "~/Library/Caches/CocoaPods/"
    fi

    # Go modules
    if dir_exists "$HOME_DIR/go/pkg/mod"; then
        local sz
        sz=$(du_safe "$HOME_DIR/go/pkg/mod")
        total_kb=$((total_kb + sz))
        add_finding "SAFE" "Go Module Cache" "$sz" "—" "~/go/pkg/mod/" "go clean -modcache"
        add_item "SAFE" "Package Caches" "$sz" "~/go/pkg/mod/"
    fi

    # gem
    if dir_exists "$HOME_DIR/.gem"; then
        local sz
        sz=$(du_safe "$HOME_DIR/.gem")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Package Caches" "$sz" "~/.gem/"
    fi
}

scan_ide_junk() {
    progress_bar 10 $TOTAL_CATEGORIES "IDE & Editor Junk"
    local total_kb=0
    local total_count=0

    # .idea directories (JetBrains)
    local idea_dirs
    idea_dirs=$(find "$HOME_DIR" -maxdepth 5 -type d -name ".idea" \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null || true)

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        local sz
        sz=$(du_safe "$dir")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + 1))
        add_item "SAFE" "IDE Junk" "$sz" "$dir/"
    done <<< "$idea_dirs"

    # Vim swap files
    local swp_count
    swp_count=$(find "$HOME_DIR" -maxdepth 6 \( -name "*.swp" -o -name "*.swo" -o -name "*~" \) -type f \
        \( -not -path "*/.Trash/*" -not -path "*/Library/*" -not -path "*/node_modules/*" \) \
        2>/dev/null | wc -l | tr -d ' ')
    total_count=$((total_count + swp_count))
    total_kb=$((total_kb + swp_count * 16))

    add_finding "SAFE" "IDE & Editor Junk" "$total_kb" "$total_count" ".idea/, *.swp, *~ files" "Delete individual IDE directories"
}

scan_browser_caches() {
    progress_bar 11 $TOTAL_CATEGORIES "Browser Caches"
    local total_kb=0

    # Chrome
    if dir_exists "$HOME_DIR/Library/Caches/Google/Chrome"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/Google/Chrome")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Browser Caches" "$sz" "~/Library/Caches/Google/Chrome/"
    fi

    # Safari
    if dir_exists "$HOME_DIR/Library/Caches/com.apple.Safari"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/com.apple.Safari")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Browser Caches" "$sz" "~/Library/Caches/com.apple.Safari/"
    fi

    # Firefox
    if dir_exists "$HOME_DIR/Library/Caches/Firefox"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/Firefox")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Browser Caches" "$sz" "~/Library/Caches/Firefox/"
    fi
    if dir_exists "$HOME_DIR/Library/Caches/org.mozilla.firefox"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/org.mozilla.firefox")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Browser Caches" "$sz" "~/Library/Caches/org.mozilla.firefox/"
    fi

    # Arc
    if dir_exists "$HOME_DIR/Library/Caches/company.thebrowser.Browser"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/company.thebrowser.Browser")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "Browser Caches" "$sz" "~/Library/Caches/company.thebrowser.Browser/"
    fi

    add_finding "SAFE" "Browser Caches" "$total_kb" "—" "Chrome, Safari, Firefox, Arc caches" "Clear from browser settings or delete cache dirs"
}

scan_docker() {
    progress_bar 12 $TOTAL_CATEGORIES "Docker"
    local total_kb=0

    if ! cmd_exists docker; then
        return
    fi

    # Check if Docker daemon is running
    if docker info >/dev/null 2>&1; then
        # Parse docker system df
        local df_output
        df_output=$(docker system df 2>/dev/null || true)

        if [ -n "$df_output" ]; then
            # Get reclaimable from each line
            local images_line containers_line volumes_line cache_line
            images_line=$(echo "$df_output" | grep "^Images" || true)
            containers_line=$(echo "$df_output" | grep "^Containers" || true)
            volumes_line=$(echo "$df_output" | grep "^Local Volumes" || true)
            cache_line=$(echo "$df_output" | grep "^Build Cache" || true)

            # Store raw docker system df output for detailed view
            add_finding "CAUTION" "Docker Images & Containers" "0" "—" "docker system df" "docker system prune -a"

            # Check Docker VM disk image size
            local docker_vm="$HOME_DIR/Library/Containers/com.docker.docker/Data"
            if dir_exists "$docker_vm"; then
                local sz
                sz=$(du_safe "$docker_vm")
                total_kb=$((total_kb + sz))
                add_finding "CAUTION" "Docker VM Disk" "$sz" "1" "$docker_vm" "docker system prune -a --volumes"
                add_item "CAUTION" "Docker" "$sz" "Docker VM Disk Image"
            fi
        fi
    else
        # Docker not running, check for disk image
        local docker_vm="$HOME_DIR/Library/Containers/com.docker.docker/Data"
        if dir_exists "$docker_vm"; then
            local sz
            sz=$(du_safe "$docker_vm")
            total_kb=$((total_kb + sz))
            add_finding "CAUTION" "Docker VM Disk (daemon stopped)" "$sz" "1" "$docker_vm" "Start Docker & run: docker system prune -a"
            add_item "CAUTION" "Docker" "$sz" "Docker VM Disk Image (daemon not running)"
        fi
    fi
}

scan_databases() {
    progress_bar 13 $TOTAL_CATEGORIES "Forgotten Databases"
    local total_kb=0
    local total_count=0

    # Search for database files in project directories only
    local db_files
    db_files=$(find "$HOME_DIR" -maxdepth 6 -type f \
        \( -name "*.sqlite" -o -name "*.sqlite3" -o -name "*.db" -o -name "*.sqlite-wal" -o -name "*.sqlite-journal" \) \
        \( -not -path "*/Library/*" -not -path "*/.Trash/*" -not -path "*/node_modules/*" \
           -not -path "*/.git/*" -not -path "*/.venv/*" -not -path "*/venv/*" \) \
        2>/dev/null || true)

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local sz
        sz=$(du -sk "$f" 2>/dev/null | cut -f1 || echo "0")
        if [ "$sz" -gt 10 ] 2>/dev/null; then
            total_kb=$((total_kb + sz))
            total_count=$((total_count + 1))
            add_item "CAUTION" "Forgotten Databases" "$sz" "$f"
        fi
    done <<< "$db_files"

    add_finding "CAUTION" "Forgotten Databases" "$total_kb" "$total_count" "*.sqlite, *.db in project dirs" "Review and delete individually"
}

scan_downloads() {
    progress_bar 14 $TOTAL_CATEGORIES "Old Downloads & Installers"
    local total_kb=0
    local total_count=0
    local downloads="$HOME_DIR/Downloads"

    if ! dir_exists "$downloads"; then
        return
    fi

    # Old files (90+ days)
    local old_files
    old_files=$(find "$downloads" -maxdepth 2 -type f -mtime +90 2>/dev/null || true)

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local sz
        sz=$(du -sk "$f" 2>/dev/null | cut -f1 || echo "0")
        total_kb=$((total_kb + sz))
        total_count=$((total_count + 1))
    done <<< "$old_files"

    # Installer files (.dmg, .pkg)
    local installers
    installers=$(find "$downloads" -maxdepth 2 -type f \
        \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" \) \
        2>/dev/null || true)

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local sz
        sz=$(du -sk "$f" 2>/dev/null | cut -f1 || echo "0")
        if [ "$sz" -gt 1024 ] 2>/dev/null; then
            add_item "CAUTION" "Old Downloads" "$sz" "$f"
        fi
    done <<< "$installers"

    add_finding "CAUTION" "Old Downloads & Installers" "$total_kb" "$total_count" "~/Downloads/ (90+ days, .dmg, .pkg)" "Review and delete individually"
}

scan_misc_caches() {
    progress_bar 15 $TOTAL_CATEGORIES "Miscellaneous App Caches"
    local total_kb=0

    # Spotify cache
    if dir_exists "$HOME_DIR/Library/Caches/com.spotify.client"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/com.spotify.client")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "App Caches" "$sz" "~/Library/Caches/com.spotify.client/"
    fi

    # Slack cache
    if dir_exists "$HOME_DIR/Library/Caches/com.tinyspeck.slackmacgap"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/com.tinyspeck.slackmacgap")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "App Caches" "$sz" "~/Library/Caches/com.tinyspeck.slackmacgap/"
    fi

    # Discord cache
    if dir_exists "$HOME_DIR/Library/Caches/com.hnc.Discord"; then
        local sz
        sz=$(du_safe "$HOME_DIR/Library/Caches/com.hnc.Discord")
        total_kb=$((total_kb + sz))
        add_item "SAFE" "App Caches" "$sz" "~/Library/Caches/com.hnc.Discord/"
    fi

    add_finding "SAFE" "Miscellaneous App Caches" "$total_kb" "—" "Spotify, Slack, Discord caches" "Delete individual app cache dirs"
}

# ─── Report & Menu Functions ─────────────────────────────────────

print_report() {
    echo ""
    echo ""
    printf "  ${WHITE}${BOLD}═══════════════════════════════════════════════════════════════${RESET}\n"
    printf "  ${WHITE}${BOLD}                    SCAN RESULTS                              ${RESET}\n"
    printf "  ${WHITE}${BOLD}═══════════════════════════════════════════════════════════════${RESET}\n"
    echo ""

    # Sort results by size (descending)
    local sorted
    sorted=$(sort -t'|' -k3 -rn "$RESULTS_FILE" 2>/dev/null || true)

    local grand_safe_kb=0
    local grand_caution_kb=0
    local line_num=0

    printf "  ${DIM}%-4s %-8s %-35s %12s %8s${RESET}\n" "#" "SAFETY" "CATEGORY" "SIZE" "ITEMS"
    printf "  ${DIM}────────────────────────────────────────────────────────────────────${RESET}\n"

    while IFS='|' read -r safety category size_kb count path cleanup; do
        [ -z "$safety" ] && continue
        line_num=$((line_num + 1))

        local size_hr
        size_hr=$(human_readable "$size_kb")

        local color
        color=$(safety_color "$safety")

        printf "  ${WHITE}%-4s${RESET} ${color}%-8s${RESET} %-35s ${WHITE}%12s${RESET} %8s\n" \
            "$line_num" "[$safety]" "$category" "$size_hr" "$count"

        case "$safety" in
            SAFE)    grand_safe_kb=$((grand_safe_kb + size_kb)) ;;
            CAUTION) grand_caution_kb=$((grand_caution_kb + size_kb)) ;;
        esac
    done <<< "$sorted"

    echo ""
    printf "  ${DIM}────────────────────────────────────────────────────────────────────${RESET}\n"
    local safe_hr caution_hr total_hr
    safe_hr=$(human_readable "$grand_safe_kb")
    caution_hr=$(human_readable "$grand_caution_kb")
    total_hr=$(human_readable "$((grand_safe_kb + grand_caution_kb))")

    printf "  ${GREEN}${BOLD}  SAFE to recover:       %s${RESET}\n" "$safe_hr"
    printf "  ${YELLOW}${BOLD}  CAUTION (review first): %s${RESET}\n" "$caution_hr"
    printf "  ${WHITE}${BOLD}  TOTAL reclaimable:     %s${RESET}\n" "$total_hr"
    echo ""
}

print_top_items() {
    local count=${1:-20}
    echo ""
    printf "  ${WHITE}${BOLD}═══ TOP %d LARGEST ITEMS ═══${RESET}\n" "$count"
    echo ""

    local sorted
    sorted=$(sort -t'|' -k3 -rn "$ITEMS_FILE" 2>/dev/null | head -"$count" || true)

    local i=0
    while IFS='|' read -r safety category size_kb path; do
        [ -z "$safety" ] && continue
        i=$((i + 1))
        local size_hr
        size_hr=$(human_readable "$size_kb")
        local color
        color=$(safety_color "$safety")

        printf "  ${WHITE}%3d.${RESET}  %12s  ${color}[%-7s]${RESET}  %s\n" \
            "$i" "$size_hr" "$safety" "$path"
    done <<< "$sorted"
    echo ""
}

print_category_detail() {
    echo ""
    printf "  ${WHITE}${BOLD}═══ CATEGORIES ═══${RESET}\n"
    echo ""

    # Get unique categories
    local cats
    cats=$(cut -d'|' -f2 "$RESULTS_FILE" 2>/dev/null | sort -u || true)

    local i=0
    local cat_list=""
    while IFS= read -r cat <&3; do
        [ -z "$cat" ] && continue
        i=$((i + 1))
        cat_list="${cat_list}${i}|${cat}
"
        # Get total for this category
        local cat_total=0
        local cat_safety=""
        while IFS='|' read -r safety category size_kb count path cleanup; do
            if [ "$category" = "$cat" ]; then
                cat_total=$((cat_total + size_kb))
                cat_safety="$safety"
            fi
        done < "$RESULTS_FILE"

        local size_hr
        size_hr=$(human_readable "$cat_total")
        local color
        color=$(safety_color "$cat_safety")

        printf "  ${WHITE}[%2d]${RESET} ${color}%-8s${RESET} %-35s %12s\n" "$i" "[$cat_safety]" "$cat" "$size_hr"
    done 3<<< "$cats"

    echo ""
    printf "  ${CYAN}Enter category number for details (or 'b' to go back): ${RESET}"
    read -r choice </dev/tty

    if [ "$choice" = "b" ] || [ "$choice" = "B" ]; then
        return
    fi

    # Find the selected category
    local selected_cat
    selected_cat=$(echo "$cat_list" | grep "^${choice}|" | cut -d'|' -f2 || true)

    if [ -z "$selected_cat" ]; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        sleep 1
        return
    fi

    echo ""
    printf "  ${WHITE}${BOLD}── Details: %s ──${RESET}\n" "$selected_cat"
    echo ""

    # Show items for this category
    local cat_items
    cat_items=$(grep "|${selected_cat}|" "$ITEMS_FILE" 2>/dev/null | sort -t'|' -k3 -rn || true)

    if [ -z "$cat_items" ]; then
        # Show from results file instead
        while IFS='|' read -r safety category size_kb count path cleanup; do
            if [ "$category" = "$selected_cat" ]; then
                local size_hr
                size_hr=$(human_readable "$size_kb")
                printf "  %12s  %s\n" "$size_hr" "$path"
                if [ -n "$cleanup" ]; then
                    printf "  ${DIM}             Cleanup: %s${RESET}\n" "$cleanup"
                fi
            fi
        done < "$RESULTS_FILE"
    else
        while IFS='|' read -r safety category size_kb path; do
            [ -z "$safety" ] && continue
            local size_hr
            size_hr=$(human_readable "$size_kb")
            local color
            color=$(safety_color "$safety")
            printf "  %12s  ${color}[%-7s]${RESET}  %s\n" "$size_hr" "$safety" "$path"
        done <<< "$cat_items"
    fi

    echo ""
    printf "  ${DIM}Press Enter to continue...${RESET}"
    read -r </dev/tty
}

execute_cleanup_for_category() {
    local category="$1"
    case "$category" in
        "Trash")
            rm -rf -- "$HOME_DIR/.Trash/"* 2>/dev/null || true
            ;;
        "Homebrew Cache")
            brew cleanup --prune=all 2>/dev/null || true
            ;;
        "npm Cache")
            npm cache clean --force 2>/dev/null || true
            ;;
        "pnpm Store")
            pnpm store prune 2>/dev/null || true
            ;;
        "pip Cache")
            pip cache purge 2>/dev/null || true
            ;;
        "Yarn Cache")
            yarn cache clean 2>/dev/null || true
            ;;
        "CocoaPods Cache")
            pod cache clean --all 2>/dev/null || true
            ;;
        "Go Module Cache")
            go clean -modcache 2>/dev/null || true
            ;;
        "Xcode DerivedData")
            rm -rf -- "$HOME_DIR/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
            ;;
        "Xcode Device Support")
            rm -rf -- "$HOME_DIR/Library/Developer/Xcode/iOS DeviceSupport/"* 2>/dev/null || true
            ;;
        "Xcode Simulators")
            xcrun simctl delete unavailable 2>/dev/null || true
            ;;
        "Logs & Crash Reports")
            rm -rf -- "$HOME_DIR/Library/Logs/"* 2>/dev/null || true
            rm -rf -- /cores/* 2>/dev/null || true
            ;;
        "OS-Generated Junk")
            find "$HOME_DIR" -maxdepth 6 -name ".DS_Store" -type f -delete 2>/dev/null || true
            find "$HOME_DIR" -maxdepth 6 -name "._*" -type f -delete 2>/dev/null || true
            ;;
        "Browser Caches")
            rm -rf -- "$HOME_DIR/Library/Caches/Google/Chrome/"* 2>/dev/null || true
            rm -rf -- "$HOME_DIR/Library/Caches/com.apple.Safari/"* 2>/dev/null || true
            rm -rf -- "$HOME_DIR/Library/Caches/Firefox/"* 2>/dev/null || true
            rm -rf -- "$HOME_DIR/Library/Caches/org.mozilla.firefox/"* 2>/dev/null || true
            rm -rf -- "$HOME_DIR/Library/Caches/company.thebrowser.Browser/"* 2>/dev/null || true
            ;;
        "IDE & Editor Junk")
            find "$HOME_DIR" -maxdepth 6 -name "*.swp" -type f -delete 2>/dev/null || true
            find "$HOME_DIR" -maxdepth 6 -name "*.swo" -type f -delete 2>/dev/null || true
            ;;
        "Compiled & Generated Files")
            find "$HOME_DIR" -maxdepth 6 -name "*.pyc" -type f -delete 2>/dev/null || true
            find "$HOME_DIR" -maxdepth 6 -name "*.pyo" -type f -delete 2>/dev/null || true
            ;;
        "Docker"*|"Docker VM"*)
            if docker info >/dev/null 2>&1; then
                docker system prune -a --volumes -f 2>/dev/null || true
            else
                printf "\n  ${YELLOW}Docker daemon not running. Start Docker Desktop first.${RESET}\n"
            fi
            ;;
        *)
            printf "\n  ${YELLOW}No automatic cleanup available for '%s'. Review manually.${RESET}\n" "$category"
            ;;
    esac
}

perform_cleanup() {
    local mode="$1"  # "safe" or "specific"
    echo ""
    printf "  ${WHITE}${BOLD}═══ CLEANUP MODE ═══${RESET}\n"
    echo ""
    printf "  ${YELLOW}${BOLD}WARNING: This will permanently delete files!${RESET}\n"
    printf "  ${DIM}You will be asked to confirm each category.${RESET}\n"
    echo ""

    local sorted
    sorted=$(sort -t'|' -k3 -rn "$RESULTS_FILE" 2>/dev/null || true)

    local freed_kb=0

    while IFS='|' read -r safety category size_kb count path cleanup <&3; do
        [ -z "$safety" ] && continue
        [ "$size_kb" -eq 0 ] 2>/dev/null && continue

        # In safe mode, skip CAUTION items
        if [ "$mode" = "safe" ] && [ "$safety" = "CAUTION" ]; then
            continue
        fi

        local size_hr
        size_hr=$(human_readable "$size_kb")
        local color
        color=$(safety_color "$safety")

        echo ""
        printf "  ${color}[%s]${RESET} ${WHITE}%s${RESET} — %s\n" "$safety" "$category" "$size_hr"
        printf "  ${DIM}  Path: %s${RESET}\n" "$path"
        printf "  ${DIM}  Command: %s${RESET}\n" "$cleanup"

        if [ "$safety" = "CAUTION" ]; then
            printf "  ${YELLOW}⚠  This may contain important data. Review before deleting.${RESET}\n"
        fi

        printf "  ${CYAN}Delete? [y/N]: ${RESET}"
        read -r confirm </dev/tty

        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            printf "  ${DIM}Cleaning up...${RESET}"

            # Execute the cleanup
            execute_cleanup_for_category "$category"

            freed_kb=$((freed_kb + size_kb))
            local freed_hr
            freed_hr=$(human_readable "$freed_kb")
            printf "\r  ${GREEN}✓ Done!${RESET} ${DIM}(Total freed so far: %s)${RESET}\n" "$freed_hr"
        else
            printf "  ${DIM}Skipped.${RESET}\n"
        fi
    done 3<<< "$sorted"

    echo ""
    local freed_hr
    freed_hr=$(human_readable "$freed_kb")
    printf "  ${GREEN}${BOLD}═══ Cleanup complete! Total freed: %s ═══${RESET}\n" "$freed_hr"
    echo ""
    printf "  ${DIM}Press Enter to continue...${RESET}"
    read -r </dev/tty
}

cleanup_specific() {
    echo ""
    printf "  ${WHITE}${BOLD}═══ SELECT CATEGORY TO CLEAN ═══${RESET}\n"
    echo ""

    local sorted
    sorted=$(sort -t'|' -k3 -rn "$RESULTS_FILE" 2>/dev/null || true)

    local i=0
    local line_data=""

    while IFS='|' read -r safety category size_kb count path cleanup <&3; do
        [ -z "$safety" ] && continue
        [ "$size_kb" -eq 0 ] 2>/dev/null && continue
        i=$((i + 1))

        local size_hr
        size_hr=$(human_readable "$size_kb")
        local color
        color=$(safety_color "$safety")

        printf "  ${WHITE}[%2d]${RESET} ${color}%-8s${RESET} %-35s %12s\n" "$i" "[$safety]" "$category" "$size_hr"
        line_data="${line_data}${i}|${safety}|${category}|${size_kb}|${count}|${path}|${cleanup}
"
    done 3<<< "$sorted"

    echo ""
    printf "  ${CYAN}Enter number to clean (or 'b' to go back): ${RESET}"
    read -r choice </dev/tty

    if [ "$choice" = "b" ] || [ "$choice" = "B" ]; then
        return
    fi

    local selected
    selected=$(echo "$line_data" | grep "^${choice}|" || true)

    if [ -z "$selected" ]; then
        printf "  ${RED}Invalid selection.${RESET}\n"
        sleep 1
        return
    fi

    local sel_safety sel_category sel_size sel_count sel_path sel_cleanup
    sel_safety=$(echo "$selected" | cut -d'|' -f2)
    sel_category=$(echo "$selected" | cut -d'|' -f3)
    sel_size=$(echo "$selected" | cut -d'|' -f4)
    sel_count=$(echo "$selected" | cut -d'|' -f5)
    sel_path=$(echo "$selected" | cut -d'|' -f6)
    sel_cleanup=$(echo "$selected" | cut -d'|' -f7)

    local size_hr
    size_hr=$(human_readable "$sel_size")

    echo ""
    printf "  ${WHITE}%s${RESET} — %s\n" "$sel_category" "$size_hr"
    printf "  ${DIM}Path: %s${RESET}\n" "$sel_path"

    if [ "$sel_safety" = "CAUTION" ]; then
        printf "  ${YELLOW}⚠  CAUTION: This may contain important data!${RESET}\n"
    fi

    printf "  ${CYAN}Confirm delete? [y/N]: ${RESET}"
    read -r confirm </dev/tty

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        printf "  ${DIM}Cleaning up...${RESET}"

        execute_cleanup_for_category "$sel_category"

        printf "\r  ${GREEN}✓ Done! Freed approximately %s${RESET}\n" "$size_hr"
    else
        printf "  ${DIM}Cancelled.${RESET}\n"
    fi

    echo ""
    printf "  ${DIM}Press Enter to continue...${RESET}"
    read -r </dev/tty
}

export_report() {
    local report_file="$HOME_DIR/Desktop/disk-audit-report-$(date '+%Y%m%d-%H%M%S').txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "  macOS Disk Audit Report"
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Host: $(hostname)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        local sorted
        sorted=$(sort -t'|' -k3 -rn "$RESULTS_FILE" 2>/dev/null || true)

        printf "%-4s %-8s %-35s %12s %8s\n" "#" "SAFETY" "CATEGORY" "SIZE" "ITEMS"
        echo "────────────────────────────────────────────────────────────────────"

        local i=0
        local grand_safe_kb=0
        local grand_caution_kb=0

        while IFS='|' read -r safety category size_kb count path cleanup; do
            [ -z "$safety" ] && continue
            i=$((i + 1))
            local size_hr
            size_hr=$(human_readable "$size_kb")
            printf "%-4s %-8s %-35s %12s %8s\n" "$i" "[$safety]" "$category" "$size_hr" "$count"
            printf "     Path: %s\n" "$path"
            printf "     Cleanup: %s\n" "$cleanup"
            echo ""

            case "$safety" in
                SAFE)    grand_safe_kb=$((grand_safe_kb + size_kb)) ;;
                CAUTION) grand_caution_kb=$((grand_caution_kb + size_kb)) ;;
            esac
        done <<< "$sorted"

        echo "────────────────────────────────────────────────────────────────────"
        echo "SAFE to recover:        $(human_readable "$grand_safe_kb")"
        echo "CAUTION (review first): $(human_readable "$grand_caution_kb")"
        echo "TOTAL reclaimable:      $(human_readable "$((grand_safe_kb + grand_caution_kb))")"
        echo ""

        echo ""
        echo "═══ TOP 20 LARGEST ITEMS ═══"
        echo ""

        local item_sorted
        item_sorted=$(sort -t'|' -k3 -rn "$ITEMS_FILE" 2>/dev/null | head -20 || true)

        i=0
        while IFS='|' read -r safety category size_kb path; do
            [ -z "$safety" ] && continue
            i=$((i + 1))
            local size_hr
            size_hr=$(human_readable "$size_kb")
            printf "%3d.  %12s  [%-7s]  %s\n" "$i" "$size_hr" "$safety" "$path"
        done <<< "$item_sorted"

    } > "$report_file"

    printf "  ${GREEN}✓ Report exported to: %s${RESET}\n" "$report_file"
    echo ""
    printf "  ${DIM}Press Enter to continue...${RESET}"
    read -r </dev/tty
}

# ─── Main Menu ────────────────────────────────────────────────────

main_menu() {
    while true; do
        echo ""
        printf "  ${WHITE}${BOLD}═══ What would you like to do? ═══${RESET}\n"
        echo ""
        printf "  ${WHITE}[1]${RESET} View detailed breakdown by category\n"
        printf "  ${WHITE}[2]${RESET} View top 20 largest items\n"
        printf "  ${GREEN}[3]${RESET} Clean up SAFE items (interactive)\n"
        printf "  ${YELLOW}[4]${RESET} Clean up specific category\n"
        printf "  ${WHITE}[5]${RESET} Export report to file\n"
        printf "  ${WHITE}[6]${RESET} Re-scan\n"
        printf "  ${DIM}[q]${RESET} Quit\n"
        echo ""
        printf "  ${CYAN}Choose an option: ${RESET}"
        read -r choice </dev/tty

        case "$choice" in
            1) print_category_detail ;;
            2) print_top_items 20 ;;
            3) perform_cleanup "safe" ;;
            4) cleanup_specific ;;
            5) export_report ;;
            6) return 1 ;;  # Signal to re-scan
            q|Q) return 0 ;;
            *)
                printf "  ${RED}Invalid option. Try again.${RESET}\n"
                ;;
        esac

        # After showing top items, wait for keypress
        if [ "$choice" = "2" ]; then
            printf "  ${DIM}Press Enter to continue...${RESET}"
            read -r </dev/tty
        fi
    done
}

# ─── Run All Scans ────────────────────────────────────────────────

run_all_scans() {
    # Create temp files
    RESULTS_FILE=$(mktemp /tmp/disk-audit-results.XXXXXX)
    ITEMS_FILE=$(mktemp /tmp/disk-audit-items.XXXXXX)

    # Cleanup trap
    trap 'rm -f -- "$RESULTS_FILE" "$ITEMS_FILE"' EXIT

    scan_trash
    scan_system_temp
    scan_os_junk
    scan_logs
    scan_xcode
    scan_build_artifacts
    scan_dependencies
    scan_compiled_files
    scan_package_caches
    scan_ide_junk
    scan_browser_caches
    scan_docker
    scan_databases
    scan_downloads
    scan_misc_caches

    clear_line
    printf "\r  ${GREEN}✓ Scan complete!${RESET}                                              \n"
}

# ─── Main ─────────────────────────────────────────────────────────

main() {
    while true; do
        print_welcome
        run_all_scans
        print_report

        main_menu
        local result=$?
        if [ $result -eq 0 ]; then
            echo ""
            printf "  ${CYAN}Thanks for using Disk Audit! 👋${RESET}\n"
            echo ""
            break
        fi
        # result=1 means re-scan, loop again
        rm -f -- "$RESULTS_FILE" "$ITEMS_FILE"
    done
}

main

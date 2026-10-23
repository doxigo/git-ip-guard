#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Apply Git IP Guard to Existing Repos  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Parse flags. Accepts flags in any order before positional directories.
FORCE_UPDATE=false
ASSUME_YES=false
SCAN_ALL=false
RECURSIVE=false
# Default: only direct children of each search dir. Most people keep repos
# one level deep (e.g. ~/Sites/myapp). Use --recursive to descend further.
MAX_DEPTH=1

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<USAGE
Usage: $0 [OPTIONS] [DIRECTORIES...]

Options:
  --force, -f       Also replace hooks that aren't git-ip-guard's (husky,
                    pre-commit, your own). By default those are kept.
  --yes, -y         Auto-confirm interactive menu prompts (use sensible defaults).
  --all, -a         Scan the entire \$HOME for git repos. Pairs well with --force.
  --recursive, -r   Descend into nested directories (default: only direct
                    children of each search dir). Use this if your repos are
                    inside subfolders, e.g. ~/Sites/clients/*/repo.
  --depth N         Explicit max depth, in levels of repo nesting.
                    --depth 1 = direct children (the default).
                    --depth 2 = up to ~/Sites/sub/repo, etc.
                    Overrides --recursive.
  --help, -h        Show this help message.

Examples:
  $0                              # Interactive (depth 1)
  $0 -f -y                        # Non-interactive on the common dev dirs
  $0 -f ~/Sites                   # Direct children of ~/Sites only (fast)
  $0 -f --recursive ~/Sites       # All repos under ~/Sites, any depth
  $0 -f --depth 2 ~/Sites         # Up to two levels deep
  $0 --all --force                # Every repo under \$HOME (recursive)
  $0 -f -y ~/code ~/Sites         # Multiple specific dirs, no prompts
USAGE
            exit 0
            ;;
        --force|-f)
            FORCE_UPDATE=true; shift ;;
        --yes|-y)
            ASSUME_YES=true; shift ;;
        --all|-a)
            SCAN_ALL=true; shift ;;
        --recursive|-r)
            RECURSIVE=true; shift ;;
        --depth)
            shift
            if ! [[ "${1:-}" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}--depth requires a non-negative integer${NC}" >&2
                exit 1
            fi
            MAX_DEPTH="$1"; RECURSIVE=false; shift ;;
        --depth=*)
            MAX_DEPTH="${1#--depth=}"
            if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}--depth requires a non-negative integer${NC}" >&2
                exit 1
            fi
            RECURSIVE=false
            shift ;;
        --) shift; break ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
        *) break ;;
    esac
done

# --all and --recursive both mean "go as deep as needed".
{ [ "$SCAN_ALL" = "true" ] || [ "$RECURSIVE" = "true" ]; } && MAX_DEPTH=""

[ "$FORCE_UPDATE" = "true" ] && \
    echo -e "${YELLOW}Force mode: hooks from other tools will be replaced too${NC}"
[ "$ASSUME_YES" = "true" ] && \
    echo -e "${YELLOW}Auto-yes: interactive prompts will use sensible defaults${NC}"
{ [ "$FORCE_UPDATE" = "true" ] || [ "$ASSUME_YES" = "true" ] || [ "$SCAN_ALL" = "true" ]; } && echo ""

# Install the hook in one repo. Our own hooks (v2 or v3) are replaced; anyone else's
# (husky, pre-commit, a hand-written one) is skipped unless --force.
apply_to_repo() {
    local git_dir="$1"
    local repo_dir="${git_dir%/.git}"
    local hook target skipped_hooks=""

    mkdir -p "$git_dir/hooks"
    for hook in pre-push pre-merge-commit pre-rebase post-merge; do
        target="$git_dir/hooks/$hook"
        if [ -e "$target" ] && ! grep -qE 'git-ip-check|git-ip-guard' "$target" 2>/dev/null \
           && [ "$FORCE_UPDATE" != "true" ]; then
            skipped_hooks="$skipped_hooks $hook"
            continue
        fi
        cp "$HOOK_SRC" "$target" && chmod +x "$target" || {
            echo -e "  ${RED}❌ Failed to write $target${NC}"
            return 1
        }
    done
    # v2 copied the checker, library and a config into every repo; v3 keeps one central copy.
    rm -f "$git_dir/hooks/git-ip-check" "$git_dir/hooks/ip-common.sh" "$git_dir/hooks/ip-check-config.json"

    if [ -n "$skipped_hooks" ]; then
        echo -e "  ${YELLOW}⚠️  $repo_dir: kept its own${skipped_hooks} (use --force to replace)${NC}"
    else
        echo -e "  ${GREEN}✅ Applied to: $repo_dir${NC}"
    fi
    return 0
}

COMMON_DIRS=(
    "$HOME/Desktop"
    "$HOME/Documents"
    "$HOME/Developer"
    "$HOME/Projects"
    "$HOME/Sites"
    "$HOME/Work"
    "$HOME/dev"
    "$HOME/code"
    "$HOME/src"
    "$HOME/repos"
)

# Decide which directories to scan.
if [ "$SCAN_ALL" = "true" ]; then
    SEARCH_DIRS=("$HOME")
elif [ $# -gt 0 ]; then
    SEARCH_DIRS=("$@")
elif [ "$ASSUME_YES" = "true" ]; then
    # Non-interactive without --all and no dirs given: use the common set.
    SEARCH_DIRS=("${COMMON_DIRS[@]}")
else
    # Interactive menu.
    echo "Choose an option:"
    echo "1) Search common development directories"
    echo "2) Search from current directory"
    echo "3) Specify custom directory"
    echo "4) Search the entire \$HOME (slow, but catches everything)"
    echo "5) Exit"
    echo ""
    echo -n "Enter choice (1-5): "
    read -r choice < /dev/tty

    case $choice in
        1) SEARCH_DIRS=("${COMMON_DIRS[@]}") ;;
        2) SEARCH_DIRS=("$(pwd)") ;;
        3)
            echo -n "Enter directory path: "
            read -r custom_dir < /dev/tty
            if [ -d "$custom_dir" ]; then
                SEARCH_DIRS=("$custom_dir")
            else
                echo -e "${RED}Error: Directory not found${NC}"
                exit 1
            fi
            ;;
        4) SEARCH_DIRS=("$HOME") ;;
        5)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
fi

HOOK_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/git-ip-guard-hook"
[ -f "$HOOK_SRC" ] || { echo -e "${RED}Error: $HOOK_SRC not found. Run this from the git-ip-guard checkout.${NC}"; exit 1; }
[ -x "$HOME/.local/share/git-ip-guard/git-ip-check" ] || \
    echo -e "${YELLOW}Note: run ./scripts/install.sh too, or these hooks will skip the check.${NC}"

# Counter for processed repos
count=0
skipped=0

# Find and process repositories.
# We prune well-known noise dirs (Library caches, node_modules, virtualenvs,
# build/vendor folders) so a $HOME-wide scan finishes in seconds, not minutes.
PRUNE_NAMES=(
    node_modules .npm .yarn .pnpm-store .pnpm
    Library .Trash .cache .gradle .m2 .ivy2 .cargo .rustup
    .venv venv .virtualenvs .conda anaconda3 miniconda3
    .docker .colima .orbstack .vagrant .DocumentRevisions-V100
    .Spotlight-V100 .fseventsd .TemporaryItems
    target build dist out vendor third_party
    .next .nuxt .svelte-kit .turbo .parcel-cache .cache-loader
)
prune_args=()
for n in "${PRUNE_NAMES[@]}"; do
    prune_args+=( -name "$n" -o )
done
unset 'prune_args[${#prune_args[@]}-1]'   # drop trailing -o

echo ""
if [ -n "$MAX_DEPTH" ]; then
    echo "Searching for Git repositories (depth ≤ $MAX_DEPTH; pass --recursive to go deeper)..."
else
    echo "Searching for Git repositories (recursive)..."
fi
echo "(Press Ctrl-C to abort.)"
echo ""

# Heartbeat: print a dot every 2s while find is running so the user can see
# the script is alive even when nothing matches yet.
heartbeat() {
    local pid="$1"
    while kill -0 "$pid" 2>/dev/null; do
        sleep 2
        printf '.' >&2
    done
    printf '\n' >&2
}

for dir in "${SEARCH_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}Skipping non-existent directory: $dir${NC}"
        continue
    fi
    echo -e "${YELLOW}Searching in: $dir${NC}"

    tmp_list=$(mktemp -t gig-find.XXXXXX)
    depth_args=()
    # A repo's .git is one level *inside* the repo dir. So if the user said
    # --depth 1 (only direct children), find needs maxdepth 2 to reach .git.
    [ -n "$MAX_DEPTH" ] && depth_args=(-maxdepth $((MAX_DEPTH + 1)))
    # shellcheck disable=SC2086
    find "$dir" "${depth_args[@]}" \
        \( "${prune_args[@]}" \) -prune -o \
        -name .git -type d -print 2>/dev/null > "$tmp_list" &
    find_pid=$!
    heartbeat "$find_pid" &
    hb_pid=$!
    wait "$find_pid"
    kill "$hb_pid" 2>/dev/null
    wait "$hb_pid" 2>/dev/null

    found=$(wc -l < "$tmp_list" | tr -d ' ')
    echo -e "${BLUE}  Found $found repositories under $dir${NC}"

    while IFS= read -r git_dir; do
        [ -n "$git_dir" ] && [ -d "$git_dir" ] || continue
        if apply_to_repo "$git_dir"; then
            count=$((count + 1))
        else
            skipped=$((skipped + 1))
        fi
    done < "$tmp_list"
    rm -f "$tmp_list"
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Applied to $count repositories${NC}"
if [ $skipped -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Skipped $skipped repositories${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""
echo "To disable for a specific repo:"
echo "  git config ipcheck.disable true"

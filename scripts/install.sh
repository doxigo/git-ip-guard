#!/bin/bash

# Git IP Guard installer (also updates an existing install).
#   - Scripts go to ~/.local/share/git-ip-guard, the config to ~/.config/git-ip-guard.
#   - core.sshCommand points at git-ip-guard-ssh, so every SSH clone/fetch/pull/push is
#     checked before git connects. An existing core.sshCommand is kept and chained.
#   - The hook goes into git's template dir, so new clones and `git init` get it.
#     Use scripts/apply-to-existing-repos.sh for repos you already have.

set -u

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

INSTALL_HELPER=false
for arg in "$@"; do
    case $arg in
        --install-helper) INSTALL_HELPER=true ;;
        --help|-h)
            cat <<USAGE
Usage: $0 [--install-helper]
  --install-helper    Also link git-ip-check, git-ip-info and git-ip-control
                      into /usr/local/bin (asks for sudo if needed).
USAGE
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

for dep in jq curl git; do
    command -v "$dep" >/dev/null 2>&1 || {
        echo "${RED}Error: '$dep' is required but not installed.${NC}"
        echo "  macOS: brew install $dep    Debian/Ubuntu: sudo apt-get install $dep"
        exit 1
    }
done

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="$HOME/.local/share/git-ip-guard"
CONFIG="$HOME/.config/git-ip-guard/config.json"
DEFAULT_CONFIG="$PROJECT_DIR/config/ip-check-config.json"
HOOKS=(pre-push pre-merge-commit pre-rebase post-merge)
# v2 copied these into the template dir; they now live in $HOME_DIR.
LEGACY_TEMPLATE_FILES=(git-ip-check git-ip-info ip-common.sh ip-check-config.json)

is_ours() { grep -qE 'git-ip-check|git-ip-guard' "$1" 2>/dev/null; }

# 1. Scripts.
mkdir -p "$HOME_DIR/lib"
for tool in git-ip-check git-ip-info git-ip-control git-ip-guard-ssh; do
    cp "$PROJECT_DIR/scripts/$tool" "$HOME_DIR/$tool"
    chmod 755 "$HOME_DIR/$tool"
done
cp "$PROJECT_DIR/scripts/lib/ip-common.sh" "$HOME_DIR/lib/ip-common.sh"
cp "$PROJECT_DIR/hooks/git-ip-guard-hook" "$HOME_DIR/git-ip-guard-hook"
chmod 755 "$HOME_DIR/git-ip-guard-hook"
echo "${GREEN}✅ Installed scripts in $HOME_DIR${NC}"

# 2. Config: keep the user's values on top of the current defaults, so new fields appear.
TEMPLATE_DIR=$(git config --global --type=path --get init.templateDir 2>/dev/null) || TEMPLATE_DIR="$HOME/.git-templates"
existing=""
for candidate in "$CONFIG" "$TEMPLATE_DIR/hooks/ip-check-config.json"; do
    [ -f "$candidate" ] && { existing="$candidate"; break; }
done
mkdir -p "$(dirname "$CONFIG")"
if [ -n "$existing" ] && jq -e . "$existing" >/dev/null 2>&1; then
    merged=$(jq -s '.[0] * .[1] | .version = "3.0"' "$DEFAULT_CONFIG" "$existing") &&
        printf '%s\n' "$merged" > "$CONFIG"
    echo "${GREEN}✅ Kept your configuration from $existing${NC}"
else
    [ -n "$existing" ] && echo "${YELLOW}$existing was not valid JSON; installing the default config.${NC}"
    cp "$DEFAULT_CONFIG" "$CONFIG"
    echo "${GREEN}✅ Installed default configuration${NC}"
fi

# 3. Template hooks. Hooks that belong to something else are left alone.
mkdir -p "$TEMPLATE_DIR/hooks"
for hook in "${HOOKS[@]}"; do
    target="$TEMPLATE_DIR/hooks/$hook"
    if [ -e "$target" ] && ! is_ours "$target"; then
        echo "${YELLOW}Skipped $target: it isn't a git-ip-guard hook.${NC}"
        continue
    fi
    cp "$HOME_DIR/git-ip-guard-hook" "$target"
    chmod 755 "$target"
done
for f in "${LEGACY_TEMPLATE_FILES[@]}"; do rm -f "$TEMPLATE_DIR/hooks/$f"; done
git config --global init.templateDir "$TEMPLATE_DIR"
echo "${GREEN}✅ Installed hooks in $TEMPLATE_DIR/hooks (used by new clones)${NC}"

# 4. SSH: check before every connection, then hand over to whatever ran before.
WRAPPER="$HOME_DIR/git-ip-guard-ssh"
current=$(git config --global --get core.sshCommand 2>/dev/null)
case "$current" in
    *git-ip-guard-ssh*) ;;
    "") ;;
    *) git config --global ipguard.sshCommand "$current"
       echo "${BLUE}Your core.sshCommand ($current) still runs, after the check.${NC}" ;;
esac
git config --global core.sshCommand "'$WRAPPER'"
echo "${GREEN}✅ SSH remotes are checked before git connects${NC}"

# 5. Optional PATH links.
if [ "$INSTALL_HELPER" = true ]; then
    SUDO=""
    [ -w /usr/local/bin ] || SUDO="sudo"
    $SUDO mkdir -p /usr/local/bin
    for tool in git-ip-check git-ip-info git-ip-control; do
        $SUDO ln -sf "$HOME_DIR/$tool" "/usr/local/bin/$tool"
    done
    # v2 copied the library here.
    $SUDO rm -rf /usr/local/lib/git-ip-guard
    echo "${GREEN}✅ Linked git-ip-check, git-ip-info and git-ip-control into /usr/local/bin${NC}"
fi

# 6. Leftovers from v2's optional pull-protection scripts.
git config --global --unset alias.pull-guarded 2>/dev/null
if grep -qs 'git-pull-wrapper' "$HOME/.zshrc" "$HOME/.bashrc"; then
    echo ""
    echo "${YELLOW}Your shell rc file still wraps 'git pull' (added by v2's setup-fastforward-protection.sh).${NC}"
    echo "  The SSH check covers pulls now. Delete the '# Git IP Guard' git() function from ~/.zshrc or ~/.bashrc,"
    echo "  then: sudo rm /usr/local/bin/git-pull-wrapper"
fi
if [ "$(git config --global --get pull.ff)" = "false" ] && [ "$(git config --global --get merge.ff)" = "false" ]; then
    echo ""
    echo "${YELLOW}pull.ff and merge.ff are false globally (v2's setup-pull-protection.sh set them).${NC}"
    echo "  They're no longer needed. If you don't want a merge commit on every pull:"
    echo "  git config --global --unset pull.ff && git config --global --unset merge.ff"
fi

cat <<DONE

${GREEN}✅ Git IP Guard 3.0 installed${NC}
Config:  $CONFIG
For repos you already have, add the hook with:
  ${BLUE}./scripts/apply-to-existing-repos.sh${NC}

Bypass: IPCHECK_BYPASS=1 git push  ·  git-ip-control disable [--global|--repo] [--push|--pull]

${YELLOW}Note:${NC} this is a developer-side reminder, not a security control.
DONE

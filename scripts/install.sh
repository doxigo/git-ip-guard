#!/bin/bash

# Git IP Guard installer.
# Sets up hooks in ~/.git-templates so they're applied to new repos.
# Use scripts/apply-to-existing-repos.sh to retrofit existing repos.

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_HELPER=false
for arg in "$@"; do
    case $arg in
        --install-helper) INSTALL_HELPER=true ;;
        --help|-h)
            cat <<USAGE
Usage: $0 [options]
  --install-helper    Also install git-ip-check, git-ip-info, git-ip-control,
                      and the ip-common.sh library to /usr/local (requires sudo).
  --help, -h          Show this help message.
USAGE
            exit 0
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      Git IP Guard Installation         ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Hard requirements.
for dep in jq curl git; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo -e "${RED}Error: '$dep' is required but not installed.${NC}"
        case "$dep" in
            jq) echo "  macOS: brew install jq    Debian/Ubuntu: sudo apt-get install jq" ;;
            curl) echo "  macOS: brew install curl  Debian/Ubuntu: sudo apt-get install curl" ;;
        esac
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TEMPLATE_DIR="$HOME/.git-templates"
HOOKS_DIR="$TEMPLATE_DIR/hooks"

# System-wide install of helpers (optional).
if [ "$INSTALL_HELPER" = true ]; then
    echo -e "${YELLOW}Installing helpers system-wide...${NC}"
    SUDO=""
    [ "$EUID" -ne 0 ] && SUDO="sudo"

    $SUDO mkdir -p /usr/local/bin /usr/local/lib/git-ip-guard
    $SUDO cp "$PROJECT_DIR/scripts/lib/ip-common.sh" /usr/local/lib/git-ip-guard/ip-common.sh
    $SUDO chmod 644 /usr/local/lib/git-ip-guard/ip-common.sh
    for tool in git-ip-check git-ip-info git-ip-control; do
        if [ -f "$PROJECT_DIR/scripts/$tool" ]; then
            $SUDO cp "$PROJECT_DIR/scripts/$tool" /usr/local/bin/
            $SUDO chmod +x "/usr/local/bin/$tool"
            echo -e "${GREEN}✅ Installed /usr/local/bin/$tool${NC}"
        fi
    done
    echo ""
fi

# Back up an existing config if one exists.
UPDATE_MODE=false
BACKUP_TMP=""
if [ -d "$TEMPLATE_DIR" ]; then
    UPDATE_MODE=true
    echo -e "${YELLOW}Existing Git IP Guard installation detected${NC}"
    if [ -f "$HOOKS_DIR/ip-check-config.json" ]; then
        BACKUP_TMP=$(mktemp -t git-ip-guard-config.XXXXXX)
        cp "$HOOKS_DIR/ip-check-config.json" "$BACKUP_TMP"
        echo -e "${BLUE}Backed up existing configuration${NC}"
    fi
fi

# Reset the template dir cleanly.
rm -rf "$TEMPLATE_DIR"
mkdir -p "$HOOKS_DIR"

# Install hooks.
echo -e "${BLUE}Installing Git IP Guard hooks...${NC}"
declare -a HOOKS=(pre-push pre-merge-commit pre-rebase post-merge)
for hook in "${HOOKS[@]}"; do
    src="$PROJECT_DIR/hooks/$hook"
    if [ -f "$src" ]; then
        cp "$src" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo -e "${GREEN}✅ Installed $hook hook${NC}"
    else
        echo -e "${YELLOW}Warning: $hook not found in $src${NC}"
    fi
done

# Install the shared library + helpers locally so hooks can find them.
cp "$PROJECT_DIR/scripts/lib/ip-common.sh" "$HOOKS_DIR/ip-common.sh"
chmod 644 "$HOOKS_DIR/ip-common.sh"
echo -e "${GREEN}✅ Installed ip-common.sh helper library${NC}"

for tool in git-ip-check git-ip-info; do
    if [ -f "$PROJECT_DIR/scripts/$tool" ]; then
        cp "$PROJECT_DIR/scripts/$tool" "$HOOKS_DIR/$tool"
        chmod +x "$HOOKS_DIR/$tool"
    fi
done
echo -e "${GREEN}✅ Installed git-ip-check helper${NC}"

# Configuration handling: migrate older configs forward, otherwise install default.
DEFAULT_CONFIG="$PROJECT_DIR/config/ip-check-config.json"
if [ "$UPDATE_MODE" = "true" ] && [ -n "$BACKUP_TMP" ] && [ -s "$BACKUP_TMP" ]; then
    if jq -e . "$BACKUP_TMP" >/dev/null 2>&1; then
        BACKUP_VERSION=$(jq -r '.version // "1.0"' "$BACKUP_TMP")
        # Always merge the existing config on top of the latest defaults so new
        # fields (mode, region rules, version) appear automatically.
        jq -s '.[0] * .[1] | .version = "2.1"' "$DEFAULT_CONFIG" "$BACKUP_TMP" \
            > "$HOOKS_DIR/ip-check-config.json"
        echo -e "${GREEN}✅ Migrated configuration from v$BACKUP_VERSION to v2.1${NC}"
    else
        echo -e "${YELLOW}Existing configuration was invalid JSON; replacing with default.${NC}"
        cp "$DEFAULT_CONFIG" "$HOOKS_DIR/ip-check-config.json"
    fi
    rm -f "$BACKUP_TMP"
else
    cp "$DEFAULT_CONFIG" "$HOOKS_DIR/ip-check-config.json"
    echo -e "${GREEN}✅ Installed default configuration${NC}"
fi

# Wire the template into git.
git config --global init.templateDir "$TEMPLATE_DIR"

echo ""
echo -e "${GREEN}✅ Git IP Guard v2.1 installation complete${NC}"
echo ""
if [ "$UPDATE_MODE" = "true" ]; then
    echo -e "${BLUE}Updated from previous version. New repositories will pick up the hooks automatically.${NC}"
else
    echo -e "${BLUE}New repositories will pick up the hooks automatically.${NC}"
fi
echo "For existing repositories, run:"
echo -e "  ${BLUE}./scripts/apply-to-existing-repos.sh${NC}"
echo ""
echo -e "${BLUE}Bypass options:${NC}"
echo -e "  Single command:    ${BLUE}IPCHECK_BYPASS=1 git push${NC}"
echo -e "  This repository:   ${BLUE}git config ipcheck.disable true${NC}"
echo -e "  Globally:          ${BLUE}git config --global ipcheck.global.disable true${NC}"
echo -e "  Pulls only:        ${BLUE}git config --global ipcheck.pull.disable true${NC}"
echo -e "  Pushes only:       ${BLUE}git config --global ipcheck.push.disable true${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} this is a developer-side reminder, not a security control."
echo "      It can be bypassed with --no-verify or by editing local hooks."
echo "      For real enforcement, add server-side checks (CI, branch protection, server hooks)."

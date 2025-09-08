#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      Git IP Guard Installation         ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Parse command line arguments
INSTALL_HELPER=false

for arg in "$@"; do
    case $arg in
        --install-helper)
            INSTALL_HELPER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --install-helper    Also install git-ip-check helper to /usr/local/bin (requires sudo)"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     # Basic installation"
            echo "  $0 --install-helper    # Install with system-wide helper"
            exit 0
            ;;
    esac
done

# Install helper if requested
if [ "$INSTALL_HELPER" = true ]; then
    echo -e "${YELLOW}Installing git-ip-check helper...${NC}"
    
    # Check if git-ip-check exists
    if [ ! -f "scripts/git-ip-check" ]; then
        echo -e "${RED}Error: git-ip-check not found in scripts directory${NC}"
        exit 1
    fi
    
    # Check for sudo privileges
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}sudo privileges required to install helper to /usr/local/bin${NC}"
        sudo cp scripts/git-ip-check /usr/local/bin/
        sudo chmod +x /usr/local/bin/git-ip-check
    else
        cp scripts/git-ip-check /usr/local/bin/
        chmod +x /usr/local/bin/git-ip-check
    fi
    
    if [ -x "/usr/local/bin/git-ip-check" ]; then
        echo -e "${GREEN}✅ Helper installed to /usr/local/bin/git-ip-check${NC}"
    else
        echo -e "${RED}Failed to install helper${NC}"
    fi
    echo ""
fi

# Define directories
TEMPLATE_DIR="$HOME/.git-templates"
HOOKS_DIR="$TEMPLATE_DIR/hooks"

# Check for existing installation and backup config
UPDATE_MODE=false
if [ -d "$TEMPLATE_DIR" ]; then
    UPDATE_MODE=true
    echo -e "${YELLOW}Existing Git IP Guard installation detected${NC}"
    
    # Backup existing config if it exists
    if [ -f "$HOOKS_DIR/ip-check-config.json" ]; then
        cp "$HOOKS_DIR/ip-check-config.json" "/tmp/ip-check-config-backup.json"
        echo -e "${BLUE}Backed up existing configuration${NC}"
    fi
fi

# Clean existing setup
rm -rf $TEMPLATE_DIR

# Create directories
mkdir -p $HOOKS_DIR

# Copy hooks and configuration files
echo -e "${BLUE}Installing Git IP Guard hooks...${NC}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Copy pre-push hook
if [ -f "$PROJECT_DIR/hooks/pre-push" ]; then
    cp "$PROJECT_DIR/hooks/pre-push" "$HOOKS_DIR/pre-push"
    chmod +x "$HOOKS_DIR/pre-push"
    echo -e "${GREEN}✅ Installed pre-push hook${NC}"
else
    echo -e "${RED}Error: pre-push hook not found at $PROJECT_DIR/hooks/pre-push${NC}"
    exit 1
fi

# Copy pre-merge-commit hook for pull protection
if [ -f "$PROJECT_DIR/hooks/pre-merge-commit" ]; then
    cp "$PROJECT_DIR/hooks/pre-merge-commit" "$HOOKS_DIR/pre-merge-commit"
    chmod +x "$HOOKS_DIR/pre-merge-commit"
    echo -e "${GREEN}✅ Installed pre-merge-commit hook (pull protection)${NC}"
else
    echo -e "${YELLOW}Warning: pre-merge-commit hook not found, pull protection not available${NC}"
fi

# Copy pre-rebase hook for pull --rebase protection
if [ -f "$PROJECT_DIR/hooks/pre-rebase" ]; then
    cp "$PROJECT_DIR/hooks/pre-rebase" "$HOOKS_DIR/pre-rebase"
    chmod +x "$HOOKS_DIR/pre-rebase"
    echo -e "${GREEN}✅ Installed pre-rebase hook (rebase protection)${NC}"
else
    echo -e "${YELLOW}Warning: pre-rebase hook not found, rebase protection not available${NC}"
fi

# Copy post-merge hook for fast-forward pull detection
if [ -f "$PROJECT_DIR/hooks/post-merge" ]; then
    cp "$PROJECT_DIR/hooks/post-merge" "$HOOKS_DIR/post-merge"
    chmod +x "$HOOKS_DIR/post-merge"
    echo -e "${GREEN}✅ Installed post-merge hook (fast-forward detection)${NC}"
else
    echo -e "${YELLOW}Warning: post-merge hook not found, fast-forward detection not available${NC}"
fi

# Handle configuration file
if [ "$UPDATE_MODE" = "true" ] && [ -f "/tmp/ip-check-config-backup.json" ]; then
    # Check if backup config needs migration
    BACKUP_VERSION=$(cat "/tmp/ip-check-config-backup.json" | jq -r '.version // "1.0"' 2>/dev/null)
    if [ "$BACKUP_VERSION" = "1.0" ] || [ "$BACKUP_VERSION" = "null" ]; then
        echo -e "${YELLOW}Migrating configuration from v1.0 to v2.0...${NC}"
        # Create new config with old blocked countries but new structure
        OLD_BLOCKED=$(cat "/tmp/ip-check-config-backup.json" | jq -r '.blocked_countries[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        if [ -n "$OLD_BLOCKED" ]; then
            cat "$PROJECT_DIR/config/ip-check-config.json" | jq --arg blocked "$OLD_BLOCKED" '.blocked_countries = ($blocked | split(","))' > "$HOOKS_DIR/ip-check-config.json"
        else
            cp "$PROJECT_DIR/config/ip-check-config.json" "$HOOKS_DIR/ip-check-config.json"
        fi
        echo -e "${GREEN}✅ Configuration migrated to v2.0${NC}"
    else
        # Use backup as-is
        cp "/tmp/ip-check-config-backup.json" "$HOOKS_DIR/ip-check-config.json"
        echo -e "${GREEN}✅ Restored existing configuration${NC}"
    fi
    rm "/tmp/ip-check-config-backup.json"
else
    # Fresh installation - copy default config
    cp "$PROJECT_DIR/config/ip-check-config.json" "$HOOKS_DIR/ip-check-config.json"
    echo -e "${GREEN}✅ Installed default configuration${NC}"
fi

# Copy helper script if available
if [ -f "$PROJECT_DIR/scripts/git-ip-check" ]; then
    cp "$PROJECT_DIR/scripts/git-ip-check" "$HOOKS_DIR/git-ip-check"
    chmod +x "$HOOKS_DIR/git-ip-check"
    echo -e "${GREEN}✅ Installed git-ip-check helper${NC}"
fi

# Set the template directory
git config --global init.templateDir $TEMPLATE_DIR

echo -e "${GREEN}✅ Git IP Guard v2.0 installation complete!${NC}"
echo ""
if [ "$UPDATE_MODE" = "true" ]; then
    echo -e "${BLUE}Updated from previous version:${NC}"
else
    echo -e "${BLUE}What's been installed:${NC}"
fi
echo "  • Pre-push hook (blocks sanctioned countries on push)"
echo "  • Pre-merge-commit hook (blocks sanctioned countries on pull merge)"
echo "  • Pre-rebase hook (blocks sanctioned countries on pull rebase)"
echo "  • Post-merge hook (detects fast-forward pulls)"
echo "  • Enhanced configuration with pull/push controls"
echo "  • Global git template directory configured"

if [ -x "/usr/local/bin/git-ip-check" ]; then
    echo "  • System-wide git-ip-check helper available"
elif [ -f "$HOOKS_DIR/git-ip-check" ]; then
    echo "  • Local git-ip-check helper installed"
fi

echo ""
echo -e "${YELLOW}New in v2.0:${NC}"
echo "  • Pull protection (git pull/fetch with merge)"
echo "  • Global and operation-specific disable options"
echo "  • Seamless updates with config preservation"
echo ""
echo "All new repositories will automatically use this template."
echo ""
echo "For existing repositories, run:"
echo -e "  ${BLUE}git init${NC}  (inside the repository)"
echo -e "  ${BLUE}./scripts/apply-to-existing-repos.sh${NC}  (bulk update)"
echo ""
echo -e "${BLUE}Bypass options:${NC}"
echo "  Temporary bypass: ${BLUE}IPCHECK_BYPASS=1 git push${NC}"
echo "  Repo disable: ${BLUE}git config ipcheck.disable true${NC}"
echo "  Global disable: ${BLUE}git config --global ipcheck.global.disable true${NC}"
echo "  Disable pulls only: ${BLUE}git config --global ipcheck.pull.disable true${NC}"
echo "  Disable pushes only: ${BLUE}git config --global ipcheck.push.disable true${NC}"

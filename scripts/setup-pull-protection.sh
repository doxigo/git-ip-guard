#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Enhanced Pull Protection Setup      ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}Setting up comprehensive pull protection...${NC}"
echo ""

# Configure git to always create merge commits on pull
# This ensures the pre-merge-commit hook runs on every pull
echo -e "${BLUE}Configuring Git to create merge commits on pull...${NC}"

# Set global configuration
git config --global pull.ff false
git config --global merge.ff false

echo -e "${GREEN}✅ Global Git configuration updated:${NC}"
echo "  - pull.ff = false (always create merge commits on pull)"
echo "  - merge.ff = false (no fast-forward merges)"
echo ""

echo -e "${YELLOW}This ensures the pre-merge-commit hook runs on EVERY git pull operation.${NC}"
echo ""

# Ask user if they want to apply this to existing repositories
echo -e "${BLUE}Apply these settings to all existing repositories?${NC}"
echo "This will ensure pull protection works in ALL your repos."
echo ""
echo -n "Apply to existing repos? (y/N): "
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Applying settings to existing repositories...${NC}"
    
    # Find and update all git repositories
    REPOS_UPDATED=0
    
    # Search in common directories
    for search_dir in "$HOME/Desktop" "$HOME/Sites" "$HOME/dev" "$HOME/Projects" "$HOME/Work"; do
        if [ -d "$search_dir" ]; then
            echo -e "${YELLOW}Searching in: $search_dir${NC}"
            while IFS= read -r git_dir; do
                if [ -n "$git_dir" ] && [ -d "$git_dir" ]; then
                    repo_dir="${git_dir%/.git}"
                    cd "$repo_dir" || continue
                    
                    # Apply the configuration to this repository
                    git config pull.ff false
                    git config merge.ff false
                    
                    echo "  ✅ Updated: $repo_dir"
                    ((REPOS_UPDATED++))
                fi
            done < <(find "$search_dir" -name ".git" -type d -prune 2>/dev/null)
        fi
    done
    
    echo ""
    echo -e "${GREEN}✅ Updated $REPOS_UPDATED repositories${NC}"
else
    echo ""
    echo -e "${YELLOW}Skipped repository updates.${NC}"
    echo "You can manually apply these settings to specific repos with:"
    echo "  cd /path/to/repo"
    echo "  git config pull.ff false"
    echo "  git config merge.ff false"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Enhanced Pull Protection Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${BOLD}What this does:${NC}"
echo "• Every 'git pull' will now create a merge commit"
echo "• The pre-merge-commit hook will run on EVERY pull"
echo "• Pull protection will work consistently across all operations"
echo ""

echo -e "${BOLD}Impact on your workflow:${NC}"
echo "• git pull creates merge commits (cleaner history)"
echo "• All pulls are protected by IP location checking"
echo "• No change to push protection"
echo ""

echo -e "${BOLD}To test pull protection:${NC}"
echo "  cd /path/to/any/repo"
echo "  git pull origin main"
echo "  # You should see: ✅ Location verified: 🇳🇴 NO - Pull allowed"

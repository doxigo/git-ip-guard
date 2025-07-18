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

# Function to apply template to a repository
apply_to_repo() {
    local git_dir="$1"
    local repo_dir="${git_dir%/.git}"
    
    # Check if hook already exists
    if [ -f "$git_dir/hooks/pre-push" ]; then
        echo -e "  ${YELLOW}⚠️  Pre-push hook already exists in $repo_dir${NC}"
        echo -n "     Overwrite? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Apply the template
    cd "$repo_dir" && git init >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✅ Applied to: $repo_dir${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Failed to apply to: $repo_dir${NC}"
        return 1
    fi
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    # Interactive mode
    echo "Choose an option:"
    echo "1) Search common development directories"
    echo "2) Search from current directory"
    echo "3) Specify custom directory"
    echo "4) Exit"
    echo ""
    echo -n "Enter choice (1-4): "
    read -r choice
    
    case $choice in
        1)
            # Common directories
            SEARCH_DIRS=(
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
            ;;
        2)
            SEARCH_DIRS=("$(pwd)")
            ;;
        3)
            echo -n "Enter directory path: "
            read -r custom_dir
            if [ -d "$custom_dir" ]; then
                SEARCH_DIRS=("$custom_dir")
            else
                echo -e "${RED}Error: Directory not found${NC}"
                exit 1
            fi
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
else
    # Use provided directories
    SEARCH_DIRS=("$@")
fi

# Check if git templates are installed
if [ ! -d "$HOME/.git-templates/hooks" ]; then
    echo -e "${RED}Error: Git templates not found. Please run ./install.sh first.${NC}"
    exit 1
fi

# Counter for processed repos
count=0
skipped=0

# Find and process repositories
echo ""
echo "Searching for Git repositories..."
echo ""

for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}Searching in: $dir${NC}"
        while IFS= read -r git_dir; do
            if [ -n "$git_dir" ] && [ -d "$git_dir" ]; then
                if apply_to_repo "$git_dir"; then
                    ((count++))
                else
                    ((skipped++))
                fi
            fi
        done < <(find "$dir" -name ".git" -type d -prune 2>/dev/null | head -50)
    else
        echo -e "${YELLOW}Skipping non-existent directory: $dir${NC}"
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Applied to $count repositories${NC}"
if [ $skipped -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Skipped $skipped repositories${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Note: The Git IP Guard hook is now active in these repositories."
echo "To test, try: git push"
echo ""
echo "To disable for a specific repo:"
echo "  git config hooks.allowpush true"

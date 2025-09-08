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

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS] [DIRECTORIES...]"
    echo ""
    echo "Options:"
    echo "  --force, -f    Force update all hooks without prompting"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive mode"
    echo "  $0 --force            # Force update in interactive mode"
    echo "  $0 ~/Projects         # Apply to specific directory"
    echo "  $0 -f ~/Projects      # Force update specific directory"
    exit 0
fi

# Check for force flag
FORCE_UPDATE=false
if [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
    FORCE_UPDATE=true
    shift  # Remove the flag from arguments
    echo -e "${YELLOW}Force update mode: Will overwrite existing hooks${NC}"
    echo ""
fi

# Function to apply template to a repository
apply_to_repo() {
    local git_dir="$1"
    local repo_dir="${git_dir%/.git}"
    
    # Check if hook already exists
    if [ -f "$git_dir/hooks/pre-push" ] && [ "$FORCE_UPDATE" != "true" ]; then
        echo -e "  ${YELLOW}⚠️  Pre-push hook already exists in $repo_dir${NC}"
        echo -n "     Overwrite? (y/N): "
        read -r response < /dev/tty
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            return 1
        fi
    elif [ -f "$git_dir/hooks/pre-push" ] && [ "$FORCE_UPDATE" = "true" ]; then
        echo -e "  ${YELLOW}⟳ Updating existing hook in $repo_dir${NC}"
    fi
    
    # Create hooks directory if it doesn't exist
    mkdir -p "$git_dir/hooks"
    
    # Get the directory where this script is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(dirname "$script_dir")"
    
    # Copy the pre-push hook from hooks directory
    if cp "$project_dir/hooks/pre-push" "$git_dir/hooks/pre-push" 2>/dev/null; then
        chmod +x "$git_dir/hooks/pre-push"
    else
        echo -e "  ${RED}❌ Failed to copy pre-push hook to: $repo_dir${NC}"
        return 1
    fi
    
    # Copy the pre-merge-commit hook for pull protection
    if cp "$project_dir/hooks/pre-merge-commit" "$git_dir/hooks/pre-merge-commit" 2>/dev/null; then
        chmod +x "$git_dir/hooks/pre-merge-commit"
    else
        echo -e "  ${YELLOW}⚠️  Failed to copy pre-merge-commit hook (pull protection not available)${NC}"
    fi
    
    # Copy the pre-rebase hook for rebase protection
    if cp "$project_dir/hooks/pre-rebase" "$git_dir/hooks/pre-rebase" 2>/dev/null; then
        chmod +x "$git_dir/hooks/pre-rebase"
    else
        echo -e "  ${YELLOW}⚠️  Failed to copy pre-rebase hook (rebase protection not available)${NC}"
    fi
    
    # Copy the post-merge hook for fast-forward pull detection
    if cp "$project_dir/hooks/post-merge" "$git_dir/hooks/post-merge" 2>/dev/null; then
        chmod +x "$git_dir/hooks/post-merge"
    else
        echo -e "  ${YELLOW}⚠️  Failed to copy post-merge hook (fast-forward detection not available)${NC}"
    fi
    
    # Copy the config file from config directory
    if cp "$project_dir/config/ip-check-config.json" "$git_dir/hooks/ip-check-config.json" 2>/dev/null; then
        # Also copy the git-ip-check helper if it exists
        if [ -f "$project_dir/scripts/git-ip-check" ]; then
            cp "$project_dir/scripts/git-ip-check" "$git_dir/hooks/git-ip-check" 2>/dev/null
            chmod +x "$git_dir/hooks/git-ip-check" 2>/dev/null
        fi
        echo -e "  ${GREEN}✅ Applied to: $repo_dir (push + pull + rebase + fast-forward protection)${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Failed to copy config file to: $repo_dir${NC}"
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
    read -r choice < /dev/tty
    
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
            read -r custom_dir < /dev/tty
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

# Check if required files exist in the project directories
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"
if [ ! -f "$project_dir/hooks/pre-push" ] || [ ! -f "$project_dir/config/ip-check-config.json" ]; then
    echo -e "${RED}Error: Required files (hooks/pre-push, config/ip-check-config.json) not found.${NC}"
    echo -e "${RED}Please make sure you're running this script from the git-ip-guard directory.${NC}"
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
        done < <(find "$dir" -name ".git" -type d -prune 2>/dev/null)
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

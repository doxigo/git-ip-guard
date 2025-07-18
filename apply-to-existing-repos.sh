#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "Applying Git IP Guard to existing repositories..."

# Directories to search for git repositories
SEARCH_DIRS=(
    "$HOME/Desktop"
    "$HOME/Projects"
    "$HOME/Sites"
    "$HOME/Work"
    "$HOME/dev"
    "$HOME/Personal"
    "$HOME/code"
)

# Counter for processed repos
count=0

# Process each directory
for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}Searching in $dir...${NC}"
        while IFS= read -r repo; do
            if [ -n "$repo" ]; then
                echo "  Applying to: $repo"
                cp ~/.git-templates/hooks/pre-push "$repo/hooks/"
                cp ~/.git-templates/hooks/ip-check-config.json "$repo/hooks/"
                ((count++))
            fi
        done < <(find "$dir" -name ".git" -type d -prune 2>/dev/null)
    fi
done

echo -e "${GREEN}Done! Applied to $count repositories.${NC}"

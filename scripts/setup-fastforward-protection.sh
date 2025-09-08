#!/bin/bash

# Setup Fast-Forward Pull Protection
# This script configures Git to use the IP guard wrapper for all pull operations

set -e

echo "=========================================="
echo "  Setup Fast-Forward Pull Protection     "
echo "=========================================="
echo

# Get the absolute path to the git-pull-wrapper script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SCRIPT="$SCRIPT_DIR/git-pull-wrapper"

if [ ! -x "$WRAPPER_SCRIPT" ]; then
    echo "❌ Error: git-pull-wrapper not found at $WRAPPER_SCRIPT"
    echo "Please run this script from the git-ip-guard directory"
    exit 1
fi

echo "🔧 Setting up Git alias for pull protection..."

# Install the wrapper globally so it works in all repositories
if [ -x "/usr/local/bin/git-ip-check" ]; then
    # Copy the wrapper to system location
    echo "📦 Installing git-pull-wrapper system-wide..."
    sudo cp "$WRAPPER_SCRIPT" /usr/local/bin/git-pull-wrapper
    sudo chmod +x /usr/local/bin/git-pull-wrapper
    WRAPPER_PATH="/usr/local/bin/git-pull-wrapper"
else
    # Use the local path
    WRAPPER_PATH="$WRAPPER_SCRIPT"
fi

echo "⚙️  Configuring Git alias..."

# Create a global Git alias that uses our wrapper
git config --global alias.pull-guarded "!$WRAPPER_PATH"

echo
echo "✅ Fast-forward pull protection setup complete!"
echo
echo "Usage:"
echo "  git pull-guarded         # Pull with IP protection (all scenarios)"
echo "  git pull                 # Original pull (hooks only protect merge/rebase)"
echo
echo "To make all pulls use IP protection, you can also create an alias in your shell:"
echo "  echo 'alias git-pull-original=\"git pull\"' >> ~/.zshrc"
echo "  echo 'alias git=\"function _git() { if [[ \$1 == \"pull\" ]]; then shift; git pull-guarded \"\$@\"; else command git \"\$@\"; fi; }; _git\"' >> ~/.zshrc"
echo "  source ~/.zshrc"
echo
echo "Or for a repository-specific approach:"
echo "  git config alias.pull '!$WRAPPER_PATH'"
echo

read -p "Would you like to set up the global shell alias to intercept all 'git pull' commands? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔧 Setting up shell alias..."
    
    # Determine shell
    if [ -n "$ZSH_VERSION" ] || echo "$SHELL" | grep -q "zsh"; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ] || echo "$SHELL" | grep -q "bash"; then
        SHELL_RC="$HOME/.bashrc"
    else
        echo "⚠️  Could not determine shell type. Please manually add the alias to your shell configuration."
        exit 0
    fi
    
    # Add alias to shell configuration
    echo "# Git IP Guard - Intercept all git pull commands" >> "$SHELL_RC"
    echo "alias git-pull-original='command git pull'" >> "$SHELL_RC"
    echo "function git() {" >> "$SHELL_RC"
    echo "    if [[ \$1 == 'pull' ]]; then" >> "$SHELL_RC"
    echo "        shift" >> "$SHELL_RC"
    echo "        $WRAPPER_PATH \"\$@\"" >> "$SHELL_RC"
    echo "    else" >> "$SHELL_RC"
    echo "        command git \"\$@\"" >> "$SHELL_RC"
    echo "    fi" >> "$SHELL_RC"
    echo "}" >> "$SHELL_RC"
    echo "" >> "$SHELL_RC"
    
    echo "✅ Shell alias configured in $SHELL_RC"
    echo "🔄 Please run: source $SHELL_RC (or restart your terminal)"
    echo
    echo "After sourcing, ALL 'git pull' commands will use IP protection!"
    echo "To use the original git pull: git-pull-original"
fi

echo
echo "🎉 Setup complete!"

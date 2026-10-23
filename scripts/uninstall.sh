#!/bin/bash

# Removes Git IP Guard: restores core.sshCommand, takes its hooks out of the template
# dir and deletes ~/.local/share/git-ip-guard. Your config and other templates stay.

HOME_DIR="$HOME/.local/share/git-ip-guard"

case "$(git config --global --get core.sshCommand)" in
    *git-ip-guard-ssh*)
        if previous=$(git config --global --get ipguard.sshCommand); then
            git config --global core.sshCommand "$previous"
        else
            git config --global --unset core.sshCommand
        fi
        ;;
esac
git config --global --unset ipguard.sshCommand 2>/dev/null

if TEMPLATE_DIR=$(git config --global --type=path --get init.templateDir); then
    for hook in pre-push pre-merge-commit pre-rebase post-merge; do
        grep -qE 'git-ip-check|git-ip-guard' "$TEMPLATE_DIR/hooks/$hook" 2>/dev/null && rm -f "$TEMPLATE_DIR/hooks/$hook"
    done
    # Only if nothing else is left in it.
    rmdir "$TEMPLATE_DIR/hooks" "$TEMPLATE_DIR" 2>/dev/null
    [ -d "$TEMPLATE_DIR" ] || git config --global --unset init.templateDir
fi

for tool in git-ip-check git-ip-info git-ip-control; do
    link="/usr/local/bin/$tool"
    case "$(readlink "$link" 2>/dev/null)" in
        "$HOME_DIR"/*) if [ -w /usr/local/bin ]; then rm -f "$link"; else sudo rm -f "$link"; fi ;;
    esac
done

rm -rf "$HOME_DIR"

echo "Git IP Guard removed. Your config is still at ~/.config/git-ip-guard/config.json."
echo "Hooks already in repos now skip the check, except v2 ones with their own git-ip-check copy next to them."
echo "Delete them from each repo's .git/hooks if you like."

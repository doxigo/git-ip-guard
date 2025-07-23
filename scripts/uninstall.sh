#!/bin/bash

# Remove global git template configuration
git config --global --unset init.templateDir

# Remove the template directory
rm -rf "$HOME/.git-templates"

echo "Uninstallation complete. The IP guard has been removed."

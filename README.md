# Git IP Guard

A security tool that prevents git pushes from sanctioned countries and provides visual indicators in your terminal.

## Features

- 🛡️ Blocks git push operations from sanctioned countries
- 🚦 Visual indicator in terminal showing your location status
- 📍 Automatic IP location detection with background updates
- 🎨 Color-coded terminal prompts
- 🔧 Easy installation and uninstallation
- 📦 Works with both new and existing repositories
- 🧪 Includes test script to verify functionality without actual push

## Requirements

- macOS with Homebrew
- Git
- Bash/Zsh shell
- `jq` (JSON processor)
- `curl` (for IP detection)
- Starship prompt (optional, for visual indicators)

## Installation

### Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/git-ip-guard.git
   cd git-ip-guard
   ```

2. Install jq if not already installed:
   ```bash
   brew install jq
   ```

3. Run the installation script:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

4. For existing repositories, initialize them with the new template:
   ```bash
   cd /path/to/your/repo
   git init
   ```

### Installation Options

```bash
# Basic installation (git hooks only)
./install.sh

# Install with system-wide helper
./install.sh --install-helper

# Silent installation (no prompts)
./install.sh --silent

# Show help
./install.sh --help
```

### Set up IP Tracking Service

For automatic IP location tracking:

```bash
# Create the LaunchAgent
mkdir -p ~/Library/LaunchAgents
cp com.user.ipcheck.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.user.ipcheck.plist
```

### Configure Terminal Visual Indicator (Optional)

If you're using Starship, the visual indicator is already configured in your `~/.config/starship.toml`.
Your prompt will show your current country code.

## Uninstallation

To completely remove Git IP Guard:

```bash
chmod +x uninstall.sh
./uninstall.sh

# Also remove the LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.user.ipcheck.plist
rm ~/Library/LaunchAgents/com.user.ipcheck.plist
```

## Usage

Once installed:

1. The system will automatically track your IP location every 5 minutes
2. Git pushes will be blocked if you're in a sanctioned country
3. Your terminal prompt will show your location status

### Testing

To test the blocking functionality without needing a real remote:

```bash
./test-push.sh
```

To manually test with different locations:
1. Switch to a VPN location (try a sanctioned country like Russia)
2. Update the IP cache: `curl -s https://ipinfo.io > /tmp/git_ip_cache`
3. Run the test script again

## Sanctioned Countries/Regions

Git pushes are blocked from:
- 🇧🇾 Belarus (BY)
- 🇨🇺 Cuba (CU)
- 🇮🇷 Iran (IR)
- 🇰🇵 North Korea (KP)
- 🇷🇺 Russia (RU)
- 🇸🇾 Syria (SY)
- 🇺🇦 Specific regions of Ukraine:
  - Crimea
  - Donetsk Oblast
  - Luhansk Oblast

## Testing

Run the test script to verify your IP and check if pushes are allowed:

```bash
./test-push.sh
```

This will show your current location and whether git pushes would be allowed or blocked.

To test the bypass mechanisms:

```bash
./test-bypass.sh
```

This will verify that all three bypass methods (environment variable, repo config, and global disable) work correctly.

## How It Works

1. A LaunchAgent runs every 5 minutes to check your IP location using ipinfo.io
2. The location data is cached in `/tmp/git_ip_cache`
3. When you run `git push`, the pre-push hook checks this cache
4. It verifies if your country is in the sanctioned list
5. If not sanctioned, the push proceeds normally
6. If sanctioned, the push is rejected with an error message
7. Special handling for Ukraine to check specific regions
8. Your terminal prompt displays your location status (if configured)

## Disabling/Bypassing IP Checks

There are three ways to disable or bypass the IP check mechanism:

### 1. Temporary Bypass (Single Command)

For a one-time bypass, set the `SKIP_IP_CHECK` environment variable:

```bash
SKIP_IP_CHECK=1 git push origin main
```

This is useful when you need to push urgently or are experiencing false positives.

### 2. Repository-Specific Disable

To disable IP checks for a specific repository:

```bash
cd /path/to/your/repo
git config hooks.allowpush true
```

To re-enable:

```bash
git config --unset hooks.allowpush
```

### 3. Global Disable

To completely disable Git IP Guard globally:

```bash
# Remove the git template directory setting
git config --global --unset init.templateDir

# Delete the hook from the template directory
rm ~/.git-templates/hooks/pre-push

# For existing repositories, you'll need to manually remove the hook
# rm .git/hooks/pre-push
```

Note: After global disable, new repositories won't have the IP check, but existing repositories will still have the hook unless manually removed.

## Troubleshooting

### IP cache not found error

- Check if the LaunchAgent is running: `launchctl list | grep ipcheck`
- Manually update the cache: `curl -s https://ipinfo.io > /tmp/git_ip_cache`

### Visual indicator not showing

- Ensure Starship is properly configured
- Check if `/tmp/git_ip_cache` exists
- Reload your shell configuration: `source ~/.zshrc`

### Hook not triggering

- For new repos: The hook is automatically installed via git templates
- For existing repos: Run `git init` in the repository to apply the template

### False positives with VPN

If you're using a VPN, the detected country will be the VPN server's location, not your actual location. You can use the temporary bypass method described above.

## Security Considerations

- This is a client-side check and can be bypassed by modifying the hook
- For server-side enforcement, implement similar checks in your Git server
- The hook uses ipinfo.io as primary service with automatic fallback to ifconfig.co to handle rate limits
- IP detection services have rate limits for free usage, but the helper includes retry logic
- **Important**: The system fails securely - if IP location cannot be determined (e.g., due to service blocking certain countries), the push is blocked for security reasons
- Some IP services (like ipinfo.io) may block requests from certain countries (e.g., Iran), which will result in blocked pushes from those locations

## Contributing

Pull requests are welcome! Please feel free to submit improvements.

## Advanced Features

### Rate Limit Handling

The git-ip-check helper includes automatic fallback to alternative IP services:
1. Primary: `ifconfig.co/json` (more reliable, less restrictive)
2. Fallback: `ipinfo.io/json` (may block certain countries)
3. Retry logic with delays

This ensures the IP check continues working even during rate limiting.

### Reusable Helper Script

The `git-ip-check` script can be installed system-wide for use in multiple hooks:

```bash
# Install to /usr/local/bin (requires sudo)
sudo ./install-helper.sh

# Use in any git hook
git-ip-check "/path/to/config.json"

# With custom bypass variables
git-ip-check "/path/to/config.json" MY_BYPASS_VAR my.config.key
```

### Using in Other Hooks

Example pre-commit hook:
```bash
#!/bin/bash
git-ip-check "$(dirname "$0")/ip-check-config.json" \
  "COMMIT_IPCHECK_BYPASS" \
  "ipcheck.disable.commit"
```

This allows you to:
- Use different bypass mechanisms for different hooks
- Share the same IP checking logic across multiple git operations
- Maintain consistent security policies

## Future Improvements

### Country List Management

The allowed/blocked country lists can be managed via:
1. Direct editing of `ip-check-config.json`
2. Remote configuration downloads (for enterprise setups)
3. Dynamic updates based on compliance requirements

### Integration with CI/CD

The git-ip-check helper can be integrated into CI/CD pipelines:
```bash
# In your CI script
if git-ip-check "/path/to/ci-config.json"; then
    echo "Location check passed"
else
    echo "Build blocked due to location restrictions"
    exit 1
fi
```

## License

MIT License - feel free to use this in your projects!

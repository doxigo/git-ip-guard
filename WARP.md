# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Git IP Guard v2.0 is a security tool that prevents git pushes and pulls from sanctioned countries using git hooks and wrapper scripts. The system detects the user's IP location via external services (ifconfig.co, ipinfo.io) and blocks operations from sanctioned countries defined in the configuration. It includes visual country flag indicators, comprehensive bypass mechanisms, granular control over push/pull operations, and complete fast-forward pull protection.

## Core Architecture

- **Hook System**: Four Git hooks for comprehensive coverage:
  - `pre-push` (push operations)
  - `pre-merge-commit` (pull merge operations)  
  - `pre-rebase` (pull rebase operations)
  - `post-merge` (fast-forward pull detection)
- **Wrapper System**: Shell wrapper that intercepts ALL `git pull` commands for complete fast-forward protection
- **IP Detection**: Primary service (ifconfig.co) with automatic fallback to ipinfo.io
- **Configuration**: JSON-based country lists with pull/push operation toggles (`ip-check-config.json`)
- **Helper Scripts**: Reusable `git-ip-check` script with operation-type support
- **Control Utility**: `git-ip-control` for managing global and repository-specific settings
- **Bypass Mechanisms**: Environment variables, global/local git config, and operation-specific overrides

## Essential Commands

### Installation & Setup
```bash
# Basic installation (includes pull protection)
chmod +x scripts/install.sh
./scripts/install.sh

# Install with system-wide helper (requires sudo)
./scripts/install.sh --install-helper

# Optional: Enable fast-forward pull protection (intercepts all git pull)
./scripts/setup-fastforward-protection.sh

# Update existing installation (preserves config)
./scripts/install.sh  # Detects and updates automatically

# Apply to existing repositories (interactive)
./scripts/apply-to-existing-repos.sh

# Force apply to existing repositories (no prompts)
./scripts/apply-to-existing-repos.sh --force
```

### Testing & Validation
```bash
# Run complete test suite
./test/test.sh

# Test current location only
./test/test.sh current

# Test bypass mechanisms
./test/test.sh bypass

# Test pull protection
./test/test.sh pull

# Test global enable/disable controls
./test/test.sh global

# Test helper script functionality
./test/test.sh helper

# Check IP and git configuration
git-ip-info  # (if system-wide helper installed)
./scripts/git-ip-info  # (local script)
```

### Development & Debugging
```bash
# Test IP detection manually
curl -s https://ifconfig.co/json | jq .
curl -s https://ipinfo.io/json | jq .

# Test the git-ip-check helper directly
./scripts/git-ip-check ./config/ip-check-config.json

# Simulate pre-push hook in a test repo
.git/hooks/pre-push
```

### Control & Management
```bash
# Check system status
./scripts/git-ip-control status

# Global disable/enable
./scripts/git-ip-control disable --global
./scripts/git-ip-control enable --global

# Operation-specific global controls
./scripts/git-ip-control disable --global --push
./scripts/git-ip-control disable --global --pull
./scripts/git-ip-control enable --global --pull

# Repository-specific controls
./scripts/git-ip-control disable --repo
./scripts/git-ip-control enable --repo --push
```

### Bypass Operations
```bash
# Temporary bypass for single operation
IPCHECK_BYPASS=1 git push origin main
IPCHECK_BYPASS=1 git pull origin main

# Repository-specific disable
git config ipcheck.disable true
git config ipcheck.push.disable true
git config ipcheck.pull.disable true

# Global disable options
git config --global ipcheck.global.disable true
git config --global ipcheck.push.disable true
git config --global ipcheck.pull.disable true

# Complete removal
chmod +x scripts/uninstall.sh
./scripts/uninstall.sh
```

## Key Configuration Files

- `config/ip-check-config.json`: Master configuration with blocked countries and regions
- `hooks/pre-push`: Git hook template for push protection
- `hooks/pre-merge-commit`: Git hook template for pull merge protection
- `hooks/pre-rebase`: Git hook template for pull rebase protection
- `hooks/post-merge`: Git hook template for fast-forward pull detection
- `scripts/git-ip-check`: Core IP checking logic with service fallbacks
- `scripts/git-ip-info`: Diagnostic tool for IP and Git configuration display
- `scripts/git-ip-control`: Control utility for managing global and repository settings
- `scripts/git-pull-wrapper`: Wrapper script for comprehensive fast-forward pull protection
- `scripts/setup-fastforward-protection.sh`: Setup script for complete pull protection

## Development Notes

### Sanctioned Countries List
Currently blocks: Belarus (BY), Cuba (CU), Iran (IR), North Korea (KP), Russia (RU), Syria (SY), plus specific Ukrainian regions (Crimea, Donetsk, Luhansk).

### Service Reliability
- Primary: ifconfig.co (provides ISO country codes)
- Fallback: ipinfo.io (automatic failover)
- Retry logic with delays for rate limiting
- Fails securely: blocks unknown locations

### Hook Installation Patterns
- New repositories: Automatic via `git config --global init.templateDir ~/.git-templates`
- Existing repositories: Manual via `git init` or bulk apply script
- Required files in `.git/hooks/`: `pre-push`, `pre-merge-commit`, `pre-rebase`, `post-merge`, `ip-check-config.json`
- Fast-forward protection: Optional shell wrapper via `setup-fastforward-protection.sh`

### Testing Considerations
- VPN testing: Hook detects VPN server location, not user's actual location
- Rate limiting: External IP services have usage limits
- Network failures: System blocks when IP cannot be determined
- Cache behavior: No persistent caching (queries on every push)

## Troubleshooting

### Common Issues
- "IP cache file not found": Outdated helper, run `./scripts/install.sh --install-helper`
- Hook not triggering: Missing config file, use `apply-to-existing-repos.sh --force`
- False positives with VPN: Use `IPCHECK_BYPASS=1` for emergency pushes
- Connection errors: External services may be blocked in some countries (intended behavior)

### Uninstallation
```bash
chmod +x scripts/uninstall.sh
./scripts/uninstall.sh
```

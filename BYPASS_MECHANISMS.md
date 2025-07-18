# Git IP Guard - Bypass Mechanisms

This document summarizes the bypass mechanisms implemented for Git IP Guard.

## Implementation Details

### 1. Pre-push Hook Modifications

The `pre-push` hook now includes two bypass checks at the beginning:

```bash
# Check for temporary bypass via environment variable
if [ "$IPCHECK_BYPASS" = "1" ]; then
  echo -e "${YELLOW}⚠️  IP check bypassed via IPCHECK_BYPASS environment variable${NC}"
  exit 0
fi

# Check for repo-local disable via git config
if [ "$(git config --get ipcheck.disable)" = "true" ]; then
  echo -e "${YELLOW}⚠️  IP check disabled for this repository${NC}"
  exit 0
fi
```

### 2. Bypass Methods

#### Temporary Bypass (Environment Variable)
- Usage: `IPCHECK_BYPASS=1 git push origin main`
- Scope: Single command only
- Use case: Emergency pushes, false positives

#### Repository-Specific Disable
- Enable: `git config ipcheck.disable true`
- Disable: `git config --unset ipcheck.disable`
- Scope: Current repository only
- Use case: Repos that should never have IP checks

#### Global Disable
- Commands:
  ```bash
  git config --global --unset init.templateDir
  rm ~/.git-templates/hooks/pre-push
  ```
- Scope: All new repositories (existing repos keep their hooks)
- Use case: Complete removal of Git IP Guard

### 3. Testing

A test script (`test-bypass.sh`) verifies all bypass mechanisms work correctly:
- Creates a temporary test repository
- Tests normal IP check behavior
- Tests environment variable bypass
- Tests repository-specific disable
- Tests re-enabling checks

### 4. Documentation

The README.md has been updated with:
- A dedicated "Disabling/Bypassing IP Checks" section
- Clear instructions for each bypass method
- Use cases and scope for each method
- Notes about persistence and cleanup

## Security Notes

- These bypass mechanisms are intentionally easy to use
- They're designed for legitimate use cases (false positives, testing, emergencies)
- The tool is meant as a safety check, not a security enforcement mechanism
- For true security, server-side checks should be implemented

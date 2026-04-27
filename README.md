# Git IP Guard v2.1

A developer-side reminder that prevents accidental git pushes and pulls from sanctioned countries. Runs as a set of git hooks that check your public IP geolocation before push, pull (merge), pull (rebase), and fast-forward pulls.

## What this is — and what it isn't

Git IP Guard is a **local guardrail**, not a security control.

- It runs entirely on the developer's machine, in standard git hooks.
- A determined user can bypass it with `IPCHECK_BYPASS=1`, `git push --no-verify`, by editing `.git/hooks/`, by using a VPN, or by removing the tool.
- For real enforcement (CI checks, server-side validation, branch protection), you need server-side controls. This tool is for the case where someone *wants* compliance and wants the friendly reminder.

## Why this exists

Sanctions affect a lot of people who have nothing to do with the politics. This tool helps developers who need to demonstrate good-faith compliance with location-based restrictions while keeping clear escape hatches when those restrictions conflict with day-to-day work. It is transparent about what it does and does not promise.

## Features

- Blocks `git push`, `git pull` (merge & rebase), and fast-forward pulls when location can be determined and matches the blocklist.
- **Multi-provider IP geolocation** with automatic fallback: ipinfo.io → ipwho.is → api.country.is → freeipapi.com. Validates JSON and country code so a Cloudflare challenge or a malformed response can no longer be silently treated as "sanctioned".
- **Local cache** (5 min TTL) — one network round-trip across many git operations.
- **Fail-closed by default**: if no provider can verify your location, the operation is blocked and you get a clear message (and a bypass hint) instead of a misleading "sanctioned" warning.
- **Allowlist, blocklist, or both** — selectable via `mode` in the config.
- **Granular bypass**: env var, repo-level git config, or global git config; per-operation (push/pull) or all.
- **Region-level rules** for cases where ISO country code isn't enough (e.g. Crimea/Donetsk/Luhansk under UA).
- `git-ip-info` and `git-ip-control` companion commands for status and configuration.
- One shared library (`scripts/lib/ip-common.sh`) — no duplication of flag tables or country data across hooks.

## Screenshots

### ✅ Push allowed
![Git push allowed from safe location](screenshots/git-ip-guard--allowed.png)

### ⛔ Push blocked
![Git push blocked from sanctioned location](screenshots/git-ip-guard--blocked.png)

### 📊 `git-ip-info`
![Git IP info showing current location and git configuration](screenshots/git-ip-guard--git-ip-info.png)

## Requirements

- bash 3.2+ (macOS default works) or any modern Linux shell
- `git`, `curl`, `jq`

```bash
# macOS
brew install jq
# Debian / Ubuntu
sudo apt-get install jq
```

## Installation

```bash
git clone https://github.com/doxigo/git-ip-guard.git
cd git-ip-guard
./scripts/install.sh
```

The installer copies hooks, the helper script, the shared library, and the default config into `~/.git-templates/hooks/` and points `init.templateDir` there. Every `git init` and `git clone` after that picks up the hooks automatically.

For system-wide CLI access (`git-ip-info`, `git-ip-control`, `git-ip-check` from any directory):

```bash
./scripts/install.sh --install-helper
```

For existing repos, run:

```bash
# Most common: all repos directly under ~/Sites, overwrite existing hooks, no prompts
./scripts/apply-to-existing-repos.sh -f ~/Sites

# Multiple parent dirs at once
./scripts/apply-to-existing-repos.sh -f ~/Sites ~/code ~/Desktop

# Repos are nested deeper (e.g. ~/Sites/clients/acme/repo) — opt into recursive search
./scripts/apply-to-existing-repos.sh -f --recursive ~/Sites

# Specific depth (1 = direct children, 2 = one level of nesting, …)
./scripts/apply-to-existing-repos.sh -f --depth 2 ~/Sites

# Common dev dirs, fully non-interactive
./scripts/apply-to-existing-repos.sh -f -y

# Sweep every repo under $HOME (recursive, slow but exhaustive)
./scripts/apply-to-existing-repos.sh --all --force

# Interactive (menu + per-repo prompts)
./scripts/apply-to-existing-repos.sh
```

**By default the search only descends one level** into each directory — that matches the common case where each repo sits directly under a parent like `~/Sites`. Pass `--recursive` (or `--depth N`, or `--all`) to go deeper.

**Flags:**

| Flag | Effect |
|---|---|
| `--force`, `-f` | Overwrite existing hooks without the per-repo "Overwrite? (y/N)" prompt. |
| `--yes`, `-y` | Skip the directory-picker menu; defaults to the common dev dirs (`~/Desktop`, `~/Sites`, `~/Projects`, `~/dev`, `~/code`, `~/src`, `~/repos`, …). |
| `--recursive`, `-r` | Descend into nested directories. Default is direct children only. |
| `--depth N` | Explicit max depth (`1` = direct children, the default). Overrides `--recursive`. |
| `--all`, `-a` | Scan the entire `$HOME` recursively. Heavy folders (`Library`, `node_modules`, `.npm`, `.cache`, `target`, `build`, `vendor`, virtualenvs, etc.) are pruned, and a heartbeat is printed while `find` runs so you can tell it's alive. |

### Updating

Re-run `./scripts/install.sh`. It detects an existing install, backs up the config, deep-merges your customisations on top of the latest defaults, and writes it back. You won't lose your blocklist.

### Uninstalling

```bash
./scripts/uninstall.sh
```

## Usage

After installation, a normal `git push` looks like:

```text
$ git push
✅ Location verified: 🇩🇪 DE - Push allowed
…
```

A blocked location looks like:

```text
$ git push
⛔ Push blocked: access denied from sanctioned country 🇮🇷 IR
IP: 1.2.3.4, Location: 🇮🇷 Tehran, IR
error: failed to push some refs
```

When location cannot be verified at all (every provider failed):

```text
Error: Could not detect IP information from any provider.
Operation blocked because location is unverifiable.
Set GIT_IP_GUARD_VERBOSE=1 to see provider errors,
or use IPCHECK_BYPASS=1 git push to bypass.
```

This is a behaviour change from v2.0, which previously accepted invalid responses and could falsely classify the user as being in a sanctioned country. **v2.1 fails closed.**

### `git-ip-info`

Shows your detected IP, location, ISP, timezone, the provider that answered, and how the current config would treat your location.

```bash
git-ip-info                    # cached, fast
git-ip-info --no-cache         # bypass the local cache
git-ip-info --verbose          # also print provider errors
```

### `git-ip-control`

```bash
git-ip-control status                    # show all settings
git-ip-control enable  --global          # enable everywhere
git-ip-control disable --global          # disable everywhere
git-ip-control disable --repo --pull     # disable only pulls in this repo
git-ip-control enable  --repo --push     # enable only pushes in this repo
```

## Configuration

Default config (`~/.git-templates/hooks/ip-check-config.json`):

```json
{
  "version": "2.1",
  "mode": "blocklist",
  "blocked_countries": ["BY", "CU", "IR", "KP", "RU", "SY"],
  "allowed_countries": [],
  "blocked_regions": {
    "UA": ["crimea", "donetsk", "luhansk"]
  },
  "enable_push_check": true,
  "enable_pull_check": true,
  "log_file": "~/.git_ip_error.log"
}
```

| Field | Meaning |
|---|---|
| `mode` | `blocklist` (default), `allowlist`, or `both`. |
| `blocked_countries` | ISO-3166-1 alpha-2 codes that are denied. |
| `allowed_countries` | ISO-3166-1 alpha-2 codes that are permitted. **Only enforced when `mode` is `allowlist` or `both`** — in v2.0 this field existed but was silently ignored. |
| `blocked_regions` | Per-country list of region/city substrings to block (case-insensitive). |
| `enable_push_check` / `enable_pull_check` | Disable a whole operation type without touching git config. |
| `log_file` | Path for block/error log entries. `~` is expanded safely (no `eval`). |

## Bypass options

| Scope | Command |
|---|---|
| One command | `IPCHECK_BYPASS=1 git push` |
| This repo, all ops | `git config ipcheck.disable true` |
| This repo, push only | `git config ipcheck.push.disable true` |
| This repo, pull only | `git config ipcheck.pull.disable true` |
| Everywhere, all ops | `git config --global ipcheck.global.disable true` |
| Everywhere, push only | `git config --global ipcheck.push.disable true` |
| Everywhere, pull only | `git config --global ipcheck.pull.disable true` |

## Known limitations

- **`git push --no-verify` skips all client-side hooks.** This is unavoidable in client-side enforcement.
- **Fast-forward pulls bypass `pre-merge-commit`.** The included `post-merge` hook detects fast-forwards and warns *after* the fact, but cannot block them. For real fast-forward coverage, run `./scripts/setup-fastforward-protection.sh`, which installs a `git pull-guarded` alias and (optionally) a shell wrapper that intercepts `git pull`. This shell wrapper writes to your `.zshrc` / `.bashrc`, so review the script before opting in.
- **Geolocation can lag.** ISP databases are updated on a delay; brand-new prefixes may resolve to the wrong country. Use `git-ip-info` to see what the providers actually return.
- **VPN / proxy use is not detected.** This tool only sees the IP your traffic leaves from.
- This is **not a security control.** See "What this is — and what it isn't" above.

## IP geolocation providers

In order of preference, the following are queried until one succeeds:

| Service | URL | Notes |
|---|---|---|
| ipinfo.io | `https://ipinfo.io/json` | 50k req/mo free, HTTPS, no key. Reliable. |
| ipwho.is | `https://ipwho.is/` | Unlimited free, HTTPS, no key. Newer. |
| api.country.is | `https://api.country.is/` | Country only — light fallback. |
| freeipapi.com | `https://freeipapi.com/api/json` | 60 req/min free. |

You can override the order with the `GIT_IP_GUARD_PROVIDERS` env var:

```bash
export GIT_IP_GUARD_PROVIDERS="ipwho.is|https://ipwho.is/ ipinfo.io|https://ipinfo.io/json"
```

`ifconfig.co` was removed in v2.1: it is now consistently behind a Cloudflare bot challenge that returns HTML (not JSON), which the v2.0 detector mishandled and which caused false "sanctioned country" warnings on machines with otherwise normal IPs.

## Caching

Successful IP lookups are cached at `~/.cache/git-ip-guard/last.json` for 5 minutes. Override:

```bash
export GIT_IP_GUARD_CACHE_TTL=900    # 15 min
export GIT_IP_GUARD_CACHE_TTL=0      # disable caching entirely
IPCHECK_NO_CACHE=1 git push          # one-off bypass
```

## What changed in v2.1

| | v2.0 | v2.1 |
|---|---|---|
| Fetch failure handling | Silent: empty country could match the blocklist | **Fails closed** with a clear message |
| Provider list | ifconfig.co → ipinfo.io | ipinfo.io → ipwho.is → country.is → freeipapi.com |
| Response validation | Substring-match on "Forbidden" / "429" | Strict: must be JSON with a usable country |
| `allowed_countries` | Defined but ignored | Enforced when `mode` is `allowlist`/`both` |
| Caching | None — every git op = network call | 5 min on-disk cache |
| Log path expansion | `eval echo` (command-injection prone) | `${path/#\~/$HOME}` |
| Flag table | Duplicated in two scripts | Generated dynamically from country code |
| Country-name table | Duplicated and incomplete | One copy in shared lib, full ISO list |
| Config validation | None | `jq -e .` before reading any value |

## Testing

```bash
./test/test.sh           # full suite
./test/test.sh current   # just check current location
./test/test.sh bypass    # test the bypass mechanisms
./test/test.sh pull      # test pull-side hooks
./test/ci-test.sh        # mock-country CI tests
```

## Project layout

```
config/                       Default config shipped to ~/.git-templates
hooks/
  pre-push                    Blocks push
  pre-merge-commit            Blocks merge-style pull
  pre-rebase                  Blocks rebase-style pull
  post-merge                  Warns after fast-forward pull
scripts/
  git-ip-check                Core check, used by every hook
  git-ip-info                 Status command
  git-ip-control              Enable/disable management
  git-pull-wrapper            Used by fast-forward protection setup
  install.sh                  Installer (also handles updates)
  apply-to-existing-repos.sh  Bulk-apply to existing repos
  setup-fastforward-protection.sh
  uninstall.sh
  lib/
    ip-common.sh              Shared library: providers, cache, flags, names
```

## License

[MIT](LICENSE)

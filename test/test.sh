#!/bin/bash

# Offline test suite. Providers are mocked with file:// URLs, $HOME is a throwaway
# directory, and a stand-in ssh runs the remote side locally, so nothing here touches
# the network or your real git config.
#   ./test/test.sh

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_IP_GUARD_CACHE_TTL=0
unset GIT_CONFIG_GLOBAL GIT_SSH_COMMAND GIT_SSH IPCHECK_BYPASS IPCHECK_NO_CACHE GIT_IP_GUARD_CACHE_DIR
mkdir -p "$HOME"
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

CHECK="$ROOT/scripts/git-ip-check"
CFG="$ROOT/config/ip-check-config.json"
failures=0

# mock <country> [region]: every provider lookup now answers with this location.
mock() {
    printf '{"ip":"203.0.113.7","country":"%s","region":"%s","city":"Testville"}' "$1" "${2:-}" > "$T/geo.json"
    export GIT_IP_GUARD_PROVIDERS="mock|file://$T/geo.json"
}

# expect <pass|block> <description> <command...>
expect() {
    local want="$1" desc="$2" got
    shift 2
    if "$@" > "$T/out" 2>&1; then got=pass; else got=block; fi
    if [ "$got" = "$want" ]; then
        echo "ok    $desc"
    else
        echo "FAIL  $desc (wanted $want, got $got)"
        sed 's/^/      /' "$T/out"
        failures=$((failures + 1))
    fi
}

config() { jq "$1" "$CFG" > "$T/cfg.json"; echo "$T/cfg.json"; }

echo "== verdicts"
mock NO;              expect pass  "allowed country"                  "$CHECK" "$CFG" push
mock IR;              expect block "blocked country"                  "$CHECK" "$CFG" push
mock ir;              expect block "lowercase country from provider"  "$CHECK" "$CFG" pull
mock UA "Crimea";     expect block "blocked region"                   "$CHECK" "$CFG" push
mock UA "Kyiv City";  expect pass  "other region, same country"       "$CHECK" "$CFG" push
mock DE;              expect block "allowlist: country not listed"    "$CHECK" "$(config '.mode = "allowlist" | .allowed_countries = ["NO"]')" push
mock DE;              expect pass  "blocklist mode ignores allowlist" "$CHECK" "$(config '.allowed_countries = ["NO"]')" push
mock IR;              expect pass  "enable_push_check: false"         "$CHECK" "$(config '.enable_push_check = false')" push
mock IR;              expect block "enable_pull_check: false only skips pulls" "$CHECK" "$(config '.enable_pull_check = false')" push
echo '<html>Just a moment...</html>' > "$T/geo.json"
expect block "HTML from a provider fails closed"                     "$CHECK" "$CFG" push
mock IR
expect pass  "IPCHECK_BYPASS=1"                                      env IPCHECK_BYPASS=1 "$CHECK" "$CFG" push
expect block "missing config fails closed"                           "$CHECK" "$T/nope.json" push
grep -qs 'Push blocked from IR: blocked' "$HOME/.git_ip_error.log" \
    && echo "ok    blocks are logged" || { echo "FAIL  blocks are logged"; failures=$((failures + 1)); }
printf '{"ip":"203.0.113.7","country":"NO","city":"\\u001b]0;pwned\\u0007Oslo"}' > "$T/geo.json"
"$CHECK" "$(config '.mode = "allowlist" | .allowed_countries = ["SE"]')" push > "$T/out" 2>&1
if grep -q $'\033]0;' "$T/out"; then
    echo "FAIL  provider text can't inject terminal escapes"; failures=$((failures + 1))
else
    echo "ok    provider text can't inject terminal escapes"
fi

echo "== cache"
export GIT_IP_GUARD_CACHE_TTL=300
mkdir -p "$HOME/.cache/git-ip-guard"
printf '%s some-other-route\n{"ip":"203.0.113.7","country":"IR"}\n' "$(date +%s)" > "$HOME/.cache/git-ip-guard/last.json"
mock NO;  expect pass  "a cache from another route is ignored"      "$CHECK" "$CFG" push
mock IR;  expect pass  "same route within the TTL uses the cache"   "$CHECK" "$CFG" push
expect block "IPCHECK_NO_CACHE=1 looks again"                       env IPCHECK_NO_CACHE=1 "$CHECK" "$CFG" push
# The cache now says IR for this route. Without the env var, the config's cache_ttl decides.
mock NO
expect block "config cache_ttl keeps a cached answer"   env -u GIT_IP_GUARD_CACHE_TTL "$CHECK" "$(config '.cache_ttl = 600')" push
expect pass  "config cache_ttl: 0 always looks again"   env -u GIT_IP_GUARD_CACHE_TTL "$CHECK" "$(config '.cache_ttl = 0')" push
export GIT_IP_GUARD_CACHE_TTL=0

echo "== whereabouts"
W="$HOME/Library/Application Support/Whereabouts"
mkdir -p "$W"
sh -c 'exit 0' & dead_pid=$!
wait "$dead_pid"
# status <pid> <kind> <seconds ago>: Whereabouts saw Iran.
status() {
    printf '{"checkedAt":%s,"country":"Iran","countryCode":"IR","ip":"198.51.100.1","kind":"%s","pid":%s,"version":1}' \
        "$(( $(date +%s) - $3 ))" "$2" "$1" > "$W/status.json"
}
mock NO
export GIT_IP_GUARD_CACHE_TTL=300
status $$ safe 5;               expect block "uses a running Whereabouts' location"   "$CHECK" "$CFG" push
status $$ safe 90;              expect pass  "cache_ttl also limits Whereabouts' age" env GIT_IP_GUARD_CACHE_TTL=60 "$CHECK" "$CFG" push
status $$ safe 5;               expect pass  "cache_ttl 0 skips Whereabouts"         env GIT_IP_GUARD_CACHE_TTL=0 "$CHECK" "$CFG" push
status $$ checking 5;           expect pass  "'checking' falls back to a lookup"      "$CHECK" "$CFG" push
status $$ safe 600;             expect pass  "an old check falls back to a lookup"    "$CHECK" "$CFG" push
status "$dead_pid" safe 5;      expect pass  "a crashed app's file is ignored"        "$CHECK" "$CFG" push
status $$ safe 5;               expect pass  "IPCHECK_NO_CACHE=1 skips Whereabouts"   env IPCHECK_NO_CACHE=1 "$CHECK" "$CFG" push
rm -rf "$HOME/Library"
export GIT_IP_GUARD_CACHE_TTL=0

echo "== install"
# Whatever ssh command was configured before must keep running after the check.
cat > "$T/fake-ssh" <<'EOF'
#!/bin/sh
# Stand-in for ssh: answers git's -G probe, then runs the remote command locally.
for arg; do last=$arg; done
case " $* " in *" -G "*) exit 0 ;; esac
exec sh -c "$last"
EOF
chmod +x "$T/fake-ssh"
git config --global core.sshCommand "$T/fake-ssh"
expect pass "install.sh" "$ROOT/scripts/install.sh"
[ "$(git config --global ipguard.sshCommand)" = "$T/fake-ssh" ] \
    && echo "ok    previous core.sshCommand is chained" \
    || { echo "FAIL  previous core.sshCommand is chained"; failures=$((failures + 1)); }

echo "== hooks"
git init -q --bare "$T/remote.git"
mock NO
expect pass  "clone over ssh"                          git clone -q "localhost:$T/remote.git" "$T/work"
[ -x "$T/work/.git/hooks/pre-push" ] && echo "ok    clone gets the template hook" \
    || { echo "FAIL  clone gets the template hook"; failures=$((failures + 1)); }
cd "$T/work" || exit 1
echo one > f && git add f && git commit -qm one
expect pass  "push from an allowed country"            git push -q origin main
mock IR
echo two >> f && git commit -qam two
expect block "push from a blocked country"             git push -q origin main
expect block "push --no-verify is still checked (ssh)" git push -q --no-verify origin main
expect block "fetch from a blocked country"            git fetch -q
expect pass  "local rebase isn't checked"              .git/hooks/pre-rebase main
expect block "rebase during pull is checked"           env GIT_REFLOG_ACTION="pull --rebase" .git/hooks/pre-rebase main
expect pass  "post-merge only warns"                   env GIT_REFLOG_ACTION=pull .git/hooks/post-merge 0
git config ipcheck.disable true
expect pass  "git config ipcheck.disable true"         git push -q origin main
git config --unset ipcheck.disable
cd "$ROOT" || exit 1

echo "== apply to existing repos"
git init -q "$T/existing"
printf '#!/bin/sh\necho husky\n' > "$T/existing/.git/hooks/pre-push"
printf '#!/bin/bash\n/usr/local/bin/git-ip-check "$CONFIG_FILE" pull\n' > "$T/existing/.git/hooks/pre-rebase"
touch "$T/existing/.git/hooks/ip-common.sh"
expect pass "apply-to-existing-repos.sh" "$ROOT/scripts/apply-to-existing-repos.sh" -y "$T"
grep -q husky "$T/existing/.git/hooks/pre-push" && grep -q git-ip-guard "$T/existing/.git/hooks/pre-rebase" \
    && [ ! -e "$T/existing/.git/hooks/ip-common.sh" ] \
    && echo "ok    keeps foreign hooks, replaces v2 ones" \
    || { echo "FAIL  keeps foreign hooks, replaces v2 ones"; failures=$((failures + 1)); }

echo "== uninstall"
expect pass "uninstall.sh" "$ROOT/scripts/uninstall.sh"
[ "$(git config --global core.sshCommand)" = "$T/fake-ssh" ] && [ ! -e "$HOME/.git-templates/hooks/pre-push" ] \
    && echo "ok    restores core.sshCommand and removes template hooks" \
    || { echo "FAIL  restores core.sshCommand and removes template hooks"; failures=$((failures + 1)); }
cd "$T/work" || exit 1
expect pass "hooks left in repos skip the check once uninstalled" git push -q origin main
cd "$ROOT" || exit 1

echo ""
if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures failed."; exit 1; fi

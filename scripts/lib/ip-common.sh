#!/bin/bash

# ip-common.sh: shared helpers for Git IP Guard, sourced by git-ip-check and git-ip-info.
# IP lookup with multi-provider fallback and a route-aware cache, the allow/block
# verdict, and flag/name lookups.

# Colors (only set if not already defined so callers can override).
: "${GREEN:=$'\033[0;32m'}"
: "${RED:=$'\033[0;31m'}"
: "${YELLOW:=$'\033[0;33m'}"
: "${BLUE:=$'\033[0;34m'}"
: "${CYAN:=$'\033[0;36m'}"
: "${MAGENTA:=$'\033[0;35m'}"
: "${BOLD:=$'\033[1m'}"
: "${NC:=$'\033[0m'}"

GIT_IP_GUARD_HOME="$HOME/.local/share/git-ip-guard"
GIT_IP_GUARD_CONFIG="$HOME/.config/git-ip-guard/config.json"
GIT_IP_GUARD_CACHE_DIR="${GIT_IP_GUARD_CACHE_DIR:-$HOME/.cache/git-ip-guard}"
GIT_IP_GUARD_VERBOSE="${GIT_IP_GUARD_VERBOSE:-0}"

# Expand a leading ~ without using eval.
expand_tilde() {
    case "$1" in
        "~"|"~/"*) echo "${HOME}${1:1}" ;;
        *) echo "$1" ;;
    esac
}

log_verbose() {
    [ "$GIT_IP_GUARD_VERBOSE" = "1" ] && echo "[git-ip-guard] $*" >&2
    return 0
}

# Try one provider. Prints normalized JSON
#   { ip, country, country_name, city, region, org, timezone, provider }
# and returns 0 only for a JSON answer with an IP and a two-letter country, so a
# bot-challenge HTML page or an error body can never be read as a location.
try_provider() {
    local name="$1" url="$2" body
    body=$(curl -fsSL --proto-redir =https --connect-timeout 4 --max-time 8 \
                -H 'Accept: application/json' \
                -H 'User-Agent: git-ip-guard/3.0' \
                "$url" 2>/dev/null) || {
        log_verbose "provider $name: request failed"
        return 1
    }
    printf '%s' "$body" | jq -ce --arg provider "$name" '
        def pick(a): (a | map(select(. != null and . != "")) | .[0] // "");
        {
            ip: pick([.ip, .query, .ipAddress]),
            country: (pick([.country_iso, .countryCode, .country_code, .country]) | ascii_upcase),
            country_name: pick([.country_name, .countryName, .country]),
            city: pick([.city, .cityName]),
            region: pick([.region, .region_name, .regionName]),
            org: pick([.org, .asn_org, .isp, .connection.isp, .connection.org]),
            timezone: pick([(.timezone | if type == "object" then (.id // .name) else . end), .time_zone, .timeZones[0]?]),
            provider: $provider
        }
        | select(.ip != "" and (.country | test("^[A-Z]{2}$")))
        # These end up on the terminal: no escape sequences from a provider.
        | map_values(gsub("[[:cntrl:]]"; ""))
    ' 2>/dev/null || {
        log_verbose "provider $name: not JSON, or no usable IP/country"
        return 1
    }
}

# Which way traffic leaves this machine. A VPN going up or down changes it, so a
# cached location is dropped at once instead of being trusted for the rest of the TTL.
route_fingerprint() {
    # Whitespace is squeezed because the cache reads this back with `read`, which trims it.
    if command -v ip >/dev/null 2>&1; then
        ip route get 1.1.1.1 2>/dev/null | awk 'NR == 1 { $1 = $1; print }'
    else
        route -n get 1.1.1.1 2>/dev/null | awk '/gateway:|interface:/ { printf "%s%s", sep, $2; sep = " " }'
    fi
}

# Whereabouts, a macOS menu-bar app, publishes each of its location checks here.
WHEREABOUTS_STATUS="$HOME/Library/Application Support/Whereabouts/status.json"

# Prints the location from Whereabouts' status file, normalized like a provider's answer,
# when the app is running and its last check is under $1 seconds old and found a country.
# Whereabouts writes "checking" the moment the Mac sees the network change; anything else
# falls back to our own lookup.
whereabouts_ip_info() {
    [ -r "$WHEREABOUTS_STATUS" ] || return 1
    local pid info
    { read -r pid; IFS= read -r info; } < <(jq -r --argjson now "$(date +%s)" --argjson max "$1" '
        select((.kind == "safe" or .kind == "violation") and ((.countryCode // "") | test("^[A-Z]{2}$")))
        | select(($now - .checkedAt) as $age | $age >= 0 and $age < $max)
        | .pid,
          ({ ip: (.ip // ""), country: .countryCode, country_name: (.country // ""), city: (.city // ""),
             region: (.region // ""), org: (.isp // ""), timezone: "", provider: "Whereabouts" }
           | map_values(gsub("[[:cntrl:]]"; "")) | tojson)
    ' "$WHEREABOUTS_STATUS" 2>/dev/null)
    # A file left behind by a crash names a pid that's gone.
    [ -n "$info" ] && kill -0 "$pid" 2>/dev/null || return 1
    log_verbose "using Whereabouts' location"
    printf '%s' "$info"
}

# Public: fetch IP info: from Whereabouts or the on-disk cache when they have a recent
# answer, otherwise from the providers in turn. "Recent" is cache_ttl seconds from the
# config file in $1 (default 300; 0 always looks again), and the cache also needs the
# route out to be unchanged. GIT_IP_GUARD_CACHE_TTL overrides the config, so a one-off
# run or a test can change it. IPCHECK_NO_CACHE=1 skips Whereabouts and the cache.
get_ip_info() {
    local config="${1:-}" cache_file="$GIT_IP_GUARD_CACHE_DIR/last.json"
    local now route ttl reuse=0
    ttl="${GIT_IP_GUARD_CACHE_TTL:-}"
    [ -z "$ttl" ] && [ -r "$config" ] && ttl=$(jq -r '.cache_ttl // empty' "$config" 2>/dev/null)
    ttl="${ttl:-300}"
    [ "${IPCHECK_NO_CACHE:-0}" != "1" ] && [ "$ttl" -gt 0 ] 2>/dev/null && reuse=1

    [ "$reuse" = 1 ] && whereabouts_ip_info "$ttl" && return 0

    now=$(date +%s)
    route=$(route_fingerprint)

    # Line 1: "<epoch> <route>", line 2: the normalized JSON.
    if [ "$reuse" = 1 ] && [ -r "$cache_file" ]; then
        local cached_at cached_route cached
        { read -r cached_at cached_route; IFS= read -r cached; } < "$cache_file"
        case "$cached_at" in ''|*[!0-9]*) cached_at=0 ;; esac
        if [ $((now - cached_at)) -lt "$ttl" ] && [ "$cached_route" = "$route" ] \
           && [ -n "$cached" ]; then
            log_verbose "using cached IP info (age $((now - cached_at))s)"
            printf '%s' "$cached"
            return 0
        fi
    fi

    local providers=(
        "ipinfo.io|https://ipinfo.io/json"
        "ipwho.is|https://ipwho.is/"
        "country.is|https://api.country.is/"
        "freeipapi.com|https://free.freeipapi.com/api/v1/json"
    )
    # Override with space-separated name|url pairs.
    [ -n "${GIT_IP_GUARD_PROVIDERS:-}" ] && read -ra providers <<< "$GIT_IP_GUARD_PROVIDERS"

    local entry result
    for entry in "${providers[@]}"; do
        if result=$(try_provider "${entry%%|*}" "${entry#*|}"); then
            # Private to the user, and swapped in whole so a concurrent reader never sees half a file.
            (
                umask 077
                mkdir -p "$GIT_IP_GUARD_CACHE_DIR" &&
                printf '%s %s\n%s\n' "$now" "$route" "$result" > "$cache_file.$$" &&
                mv -f "$cache_file.$$" "$cache_file"
            ) 2>/dev/null
            printf '%s' "$result"
            return 0
        fi
    done
    return 1
}

# Public: judge IP info ($2) against a config file ($1). Prints one line of fields
# separated by \x1f (unlike a tab, `read` keeps empty fields):
#   verdict country city region ip
# where verdict is allowed, not-allowed, blocked, region:<name> or unverified.
# Returns 1 when the config is missing or not valid JSON.
ip_guard_verdict() {
    printf '%s' "$2" | jq -r --slurpfile cfg "$1" '
        ($cfg[0]) as $c
        | (.country // "") as $cc
        | (if ($c.mode | IN("allowlist", "blocklist", "both")) then $c.mode else "blocklist" end) as $mode
        | (($c.allowed_countries // []) | map(ascii_upcase)) as $allow
        | (($c.blocked_countries // []) | map(ascii_upcase)) as $block
        | ((.region // "") | ascii_downcase) as $r
        | ((.city // "") | ascii_downcase) as $ci
        | ([($c.blocked_regions // {})[$cc] // [] | .[] | ascii_downcase
            | select(. != "" and (. as $b | ($r | contains($b)) or ($ci | contains($b))))] | first) as $hit
        | (if ($cc | test("^[A-Z]{2}$") | not) then "unverified"
           elif $mode != "blocklist" and ($allow | length) > 0 and ($allow | any(. == $cc) | not) then "not-allowed"
           elif $mode != "allowlist" and ($block | any(. == $cc)) then "blocked"
           elif $hit then "region:\($hit)"
           else "allowed" end) as $verdict
        | [$verdict, $cc, .city // "", .region // "", .ip // ""] | join("\u001f")
    ' 2>/dev/null
}

# Look up flag emoji for an uppercase ISO-3166-1 alpha-2 country code.
# Builds the regional-indicator pair as UTF-8 bytes with octal printf escapes,
# which is portable across bash 3.2 (macOS default) and bash 5+.
get_flag() {
    case "$1" in
        [A-Z][A-Z]) ;;
        *) printf '🏳️'; return ;;
    esac
    local a b
    a=$(printf '%d' "'${1:0:1}")
    b=$(printf '%d' "'${1:1:1}")
    # Regional Indicator Symbol Letter A is U+1F1E6, encoded as F0 9F 87 A6.
    # Each subsequent letter shifts the last byte: B = A7, C = A8, ...
    printf '\360\237\207\'"$(printf '%o' $((0xA6 + a - 65)))"'\360\237\207\'"$(printf '%o' $((0xA6 + b - 65)))"
}

# Map ISO code to a human-readable country name. Falls back to the code itself.
get_country_name() {
    case "$1" in
        AD) echo "Andorra" ;; AE) echo "United Arab Emirates" ;; AF) echo "Afghanistan" ;;
        AG) echo "Antigua and Barbuda" ;; AL) echo "Albania" ;; AM) echo "Armenia" ;;
        AO) echo "Angola" ;; AR) echo "Argentina" ;; AT) echo "Austria" ;;
        AU) echo "Australia" ;; AZ) echo "Azerbaijan" ;; BA) echo "Bosnia and Herzegovina" ;;
        BB) echo "Barbados" ;; BD) echo "Bangladesh" ;; BE) echo "Belgium" ;;
        BF) echo "Burkina Faso" ;; BG) echo "Bulgaria" ;; BH) echo "Bahrain" ;;
        BI) echo "Burundi" ;; BJ) echo "Benin" ;; BN) echo "Brunei" ;;
        BO) echo "Bolivia" ;; BR) echo "Brazil" ;; BS) echo "Bahamas" ;;
        BT) echo "Bhutan" ;; BW) echo "Botswana" ;; BY) echo "Belarus" ;;
        BZ) echo "Belize" ;; CA) echo "Canada" ;; CD) echo "DR Congo" ;;
        CF) echo "Central African Republic" ;; CG) echo "Republic of the Congo" ;;
        CH) echo "Switzerland" ;; CI) echo "Côte d'Ivoire" ;; CL) echo "Chile" ;;
        CM) echo "Cameroon" ;; CN) echo "China" ;; CO) echo "Colombia" ;;
        CR) echo "Costa Rica" ;; CU) echo "Cuba" ;; CV) echo "Cape Verde" ;;
        CY) echo "Cyprus" ;; CZ) echo "Czech Republic" ;; DE) echo "Germany" ;;
        DJ) echo "Djibouti" ;; DK) echo "Denmark" ;; DM) echo "Dominica" ;;
        DO) echo "Dominican Republic" ;; DZ) echo "Algeria" ;; EC) echo "Ecuador" ;;
        EE) echo "Estonia" ;; EG) echo "Egypt" ;; ER) echo "Eritrea" ;;
        ES) echo "Spain" ;; ET) echo "Ethiopia" ;; FI) echo "Finland" ;;
        FJ) echo "Fiji" ;; FR) echo "France" ;; GA) echo "Gabon" ;;
        GB) echo "United Kingdom" ;; GD) echo "Grenada" ;; GE) echo "Georgia" ;;
        GH) echo "Ghana" ;; GM) echo "Gambia" ;; GN) echo "Guinea" ;;
        GQ) echo "Equatorial Guinea" ;; GR) echo "Greece" ;; GT) echo "Guatemala" ;;
        GW) echo "Guinea-Bissau" ;; GY) echo "Guyana" ;; HN) echo "Honduras" ;;
        HR) echo "Croatia" ;; HT) echo "Haiti" ;; HU) echo "Hungary" ;;
        ID) echo "Indonesia" ;; IE) echo "Ireland" ;; IL) echo "Israel" ;;
        IN) echo "India" ;; IQ) echo "Iraq" ;; IR) echo "Iran" ;;
        IS) echo "Iceland" ;; IT) echo "Italy" ;; JM) echo "Jamaica" ;;
        JO) echo "Jordan" ;; JP) echo "Japan" ;; KE) echo "Kenya" ;;
        KG) echo "Kyrgyzstan" ;; KH) echo "Cambodia" ;; KM) echo "Comoros" ;;
        KN) echo "Saint Kitts and Nevis" ;; KP) echo "North Korea" ;;
        KR) echo "South Korea" ;; KW) echo "Kuwait" ;; KZ) echo "Kazakhstan" ;;
        LA) echo "Laos" ;; LB) echo "Lebanon" ;; LC) echo "Saint Lucia" ;;
        LI) echo "Liechtenstein" ;; LK) echo "Sri Lanka" ;; LR) echo "Liberia" ;;
        LS) echo "Lesotho" ;; LT) echo "Lithuania" ;; LU) echo "Luxembourg" ;;
        LV) echo "Latvia" ;; LY) echo "Libya" ;; MA) echo "Morocco" ;;
        MC) echo "Monaco" ;; MD) echo "Moldova" ;; ME) echo "Montenegro" ;;
        MG) echo "Madagascar" ;; MK) echo "North Macedonia" ;; ML) echo "Mali" ;;
        MM) echo "Myanmar" ;; MN) echo "Mongolia" ;; MR) echo "Mauritania" ;;
        MT) echo "Malta" ;; MU) echo "Mauritius" ;; MV) echo "Maldives" ;;
        MW) echo "Malawi" ;; MX) echo "Mexico" ;; MY) echo "Malaysia" ;;
        MZ) echo "Mozambique" ;; NA) echo "Namibia" ;; NE) echo "Niger" ;;
        NG) echo "Nigeria" ;; NI) echo "Nicaragua" ;; NL) echo "Netherlands" ;;
        NO) echo "Norway" ;; NP) echo "Nepal" ;; NZ) echo "New Zealand" ;;
        OM) echo "Oman" ;; PA) echo "Panama" ;; PE) echo "Peru" ;;
        PG) echo "Papua New Guinea" ;; PH) echo "Philippines" ;; PK) echo "Pakistan" ;;
        PL) echo "Poland" ;; PT) echo "Portugal" ;; PY) echo "Paraguay" ;;
        QA) echo "Qatar" ;; RO) echo "Romania" ;; RS) echo "Serbia" ;;
        RU) echo "Russia" ;; RW) echo "Rwanda" ;; SA) echo "Saudi Arabia" ;;
        SB) echo "Solomon Islands" ;; SC) echo "Seychelles" ;; SD) echo "Sudan" ;;
        SE) echo "Sweden" ;; SG) echo "Singapore" ;; SI) echo "Slovenia" ;;
        SK) echo "Slovakia" ;; SL) echo "Sierra Leone" ;; SM) echo "San Marino" ;;
        SN) echo "Senegal" ;; SO) echo "Somalia" ;; SR) echo "Suriname" ;;
        SS) echo "South Sudan" ;; ST) echo "São Tomé and Príncipe" ;;
        SV) echo "El Salvador" ;; SY) echo "Syria" ;; SZ) echo "Eswatini" ;;
        TD) echo "Chad" ;; TG) echo "Togo" ;; TH) echo "Thailand" ;;
        TJ) echo "Tajikistan" ;; TL) echo "Timor-Leste" ;; TM) echo "Turkmenistan" ;;
        TN) echo "Tunisia" ;; TO) echo "Tonga" ;; TR) echo "Turkey" ;;
        TT) echo "Trinidad and Tobago" ;; TW) echo "Taiwan" ;; TZ) echo "Tanzania" ;;
        UA) echo "Ukraine" ;; UG) echo "Uganda" ;; US) echo "United States" ;;
        UY) echo "Uruguay" ;; UZ) echo "Uzbekistan" ;; VA) echo "Vatican City" ;;
        VC) echo "Saint Vincent and the Grenadines" ;; VE) echo "Venezuela" ;;
        VN) echo "Vietnam" ;; VU) echo "Vanuatu" ;; WS) echo "Samoa" ;;
        XK) echo "Kosovo" ;; YE) echo "Yemen" ;; ZA) echo "South Africa" ;;
        ZM) echo "Zambia" ;; ZW) echo "Zimbabwe" ;;
        *) echo "$1" ;;
    esac
}

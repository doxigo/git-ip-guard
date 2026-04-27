#!/bin/bash

# ip-common.sh: shared helpers for Git IP Guard.
# Sourced by git-ip-check, git-ip-info, and other scripts.
# Provides IP fetching with multi-provider fallback, caching, country
# normalization, flag/name lookups, and safe path expansion.

# Colors (only set if not already defined so callers can override).
: "${GREEN:=$'\033[0;32m'}"
: "${RED:=$'\033[0;31m'}"
: "${YELLOW:=$'\033[0;33m'}"
: "${BLUE:=$'\033[0;34m'}"
: "${CYAN:=$'\033[0;36m'}"
: "${MAGENTA:=$'\033[0;35m'}"
: "${BOLD:=$'\033[1m'}"
: "${NC:=$'\033[0m'}"

GIT_IP_GUARD_CACHE_DIR="${GIT_IP_GUARD_CACHE_DIR:-$HOME/.cache/git-ip-guard}"
GIT_IP_GUARD_CACHE_TTL="${GIT_IP_GUARD_CACHE_TTL:-300}"
GIT_IP_GUARD_VERBOSE="${GIT_IP_GUARD_VERBOSE:-0}"

# Expand a leading ~ without using eval.
expand_tilde() {
    local path="$1"
    case "$path" in
        "~"|"~/"*) echo "${HOME}${path:1}" ;;
        *) echo "$path" ;;
    esac
}

log_verbose() {
    [ "$GIT_IP_GUARD_VERBOSE" = "1" ] && echo "[git-ip-guard] $*" >&2
    return 0
}

# Validate that a string is well-formed JSON containing at least an `ip` field.
is_valid_ip_json() {
    local body="$1"
    [ -z "$body" ] && return 1
    # Cheap structural check before invoking jq.
    case "$body" in
        "{"*"}"*) ;;
        *) return 1 ;;
    esac
    local ip
    ip=$(printf '%s' "$body" | jq -r '.ip // empty' 2>/dev/null)
    [ -n "$ip" ]
}

# Normalize a single provider's response into a unified JSON shape:
#   { "ip", "country", "country_name", "city", "region", "org", "timezone" }
# Country is uppercased ISO-3166-1 alpha-2.
normalize_provider_json() {
    local provider="$1"
    local body="$2"
    printf '%s' "$body" | jq -c --arg provider "$provider" '
        def upper: if . == null then "" else (. | ascii_upcase) end;
        def first(a): (a | map(select(. != null and . != "")) | .[0] // "");
        {
            ip: (.ip // .query // ""),
            country: (first([.country_iso, .countryCode, .country_code, .country]) | upper),
            country_name: (first([.country_name, .country])),
            city: (.city // ""),
            region: (first([.region, .region_name, .regionName])),
            org: (first([.org, .asn_org, .isp, .connection.isp, .connection.org])),
            timezone: ([(.timezone | if type=="object" then (.id // .name // "") else . end), .time_zone]
                       | map(select(. != null and . != "")) | .[0] // ""),
            provider: $provider
        }
    ' 2>/dev/null
}

# Try a single provider. Returns 0 and prints normalized JSON on success.
try_provider() {
    local name="$1"
    local url="$2"
    local body
    body=$(curl -fsSL --connect-timeout 4 --max-time 8 \
                -H 'Accept: application/json' \
                -H 'User-Agent: git-ip-guard/2.1' \
                "$url" 2>/dev/null) || {
        log_verbose "provider $name: curl failed"
        return 1
    }
    if ! is_valid_ip_json "$body"; then
        log_verbose "provider $name: invalid or non-JSON response"
        return 1
    fi
    local normalized
    normalized=$(normalize_provider_json "$name" "$body") || return 1
    # Require a country code to consider the result usable.
    local country
    country=$(printf '%s' "$normalized" | jq -r '.country // empty')
    if [ -z "$country" ] || [ ${#country} -ne 2 ]; then
        log_verbose "provider $name: missing/invalid country"
        return 1
    fi
    printf '%s' "$normalized"
    return 0
}

# Public: fetch IP info, trying multiple providers, with on-disk cache.
# Cache TTL is 5 minutes by default; set GIT_IP_GUARD_CACHE_TTL=0 to disable.
# Set IPCHECK_NO_CACHE=1 to bypass cache for one call.
get_ip_info() {
    local cache_file="$GIT_IP_GUARD_CACHE_DIR/last.json"
    local now
    now=$(date +%s)

    # Cache lookup.
    if [ "${IPCHECK_NO_CACHE:-0}" != "1" ] && [ "$GIT_IP_GUARD_CACHE_TTL" -gt 0 ] \
       && [ -f "$cache_file" ] && [ -r "$cache_file" ]; then
        local mtime age
        mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        age=$((now - mtime))
        if [ "$age" -lt "$GIT_IP_GUARD_CACHE_TTL" ]; then
            local cached
            cached=$(cat "$cache_file" 2>/dev/null)
            if is_valid_ip_json "$cached"; then
                log_verbose "using cached IP info (age ${age}s)"
                printf '%s' "$cached"
                return 0
            fi
        fi
    fi

    # Provider order can be overridden via GIT_IP_GUARD_PROVIDERS
    # (space-separated name=url pairs).
    local providers=(
        "ipinfo.io|https://ipinfo.io/json"
        "ipwho.is|https://ipwho.is/"
        "country.is|https://api.country.is/"
        "freeipapi.com|https://freeipapi.com/api/json"
    )
    if [ -n "${GIT_IP_GUARD_PROVIDERS:-}" ]; then
        # shellcheck disable=SC2206
        providers=($GIT_IP_GUARD_PROVIDERS)
    fi

    local entry name url result
    for entry in "${providers[@]}"; do
        name="${entry%%|*}"
        url="${entry#*|}"
        if result=$(try_provider "$name" "$url"); then
            mkdir -p "$GIT_IP_GUARD_CACHE_DIR" 2>/dev/null
            printf '%s' "$result" > "$cache_file" 2>/dev/null
            chmod 600 "$cache_file" 2>/dev/null
            printf '%s' "$result"
            return 0
        fi
    done

    return 1
}

# Look up flag emoji for an ISO-3166-1 alpha-2 country code.
# Builds the regional-indicator pair as UTF-8 bytes with octal printf escapes,
# which is portable across bash 3.2 (macOS default) and bash 5+.
get_flag() {
    local code="$1"
    code=$(printf '%s' "$code" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
    case "$code" in
        [A-Z][A-Z]) ;;
        *) printf '🏳️'; return ;;
    esac
    local a b b4_a b4_b
    a=$(printf '%d' "'${code:0:1}")
    b=$(printf '%d' "'${code:1:1}")
    # Regional Indicator Symbol Letter A is U+1F1E6, encoded as F0 9F 87 A6.
    # Each subsequent letter shifts the last byte: B = A7, C = A8, ...
    b4_a=$(printf '%o' $((0xA6 + a - 65)))
    b4_b=$(printf '%o' $((0xA6 + b - 65)))
    printf '\360\237\207\'"$b4_a"'\360\237\207\'"$b4_b"
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

# Locate the shared lib so other scripts can find it from any install location.
find_ip_common_lib() {
    local candidates=(
        "/usr/local/lib/git-ip-guard/ip-common.sh"
        "$HOME/.git-templates/hooks/ip-common.sh"
    )
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    candidates+=("$self_dir/ip-common.sh" "$self_dir/lib/ip-common.sh" "$self_dir/../scripts/lib/ip-common.sh")
    local p
    for p in "${candidates[@]}"; do
        [ -r "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

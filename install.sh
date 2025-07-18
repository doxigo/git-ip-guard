#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      Git IP Guard Installation         ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Parse command line arguments
INSTALL_HELPER=false

for arg in "$@"; do
    case $arg in
        --install-helper)
            INSTALL_HELPER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --install-helper    Also install git-ip-check helper to /usr/local/bin (requires sudo)"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     # Basic installation"
            echo "  $0 --install-helper    # Install with system-wide helper"
            exit 0
            ;;
    esac
done

# Install helper if requested
if [ "$INSTALL_HELPER" = true ]; then
    echo -e "${YELLOW}Installing git-ip-check helper...${NC}"
    
    # Check if git-ip-check exists
    if [ ! -f "git-ip-check" ]; then
        echo -e "${RED}Error: git-ip-check not found in current directory${NC}"
        exit 1
    fi
    
    # Check for sudo privileges
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}sudo privileges required to install helper to /usr/local/bin${NC}"
        sudo cp git-ip-check /usr/local/bin/
        sudo chmod +x /usr/local/bin/git-ip-check
    else
        cp git-ip-check /usr/local/bin/
        chmod +x /usr/local/bin/git-ip-check
    fi
    
    if [ -x "/usr/local/bin/git-ip-check" ]; then
        echo -e "${GREEN}✅ Helper installed to /usr/local/bin/git-ip-check${NC}"
    else
        echo -e "${RED}Failed to install helper${NC}"
    fi
    echo ""
fi

# Define directories
TEMPLATE_DIR="$HOME/.git-templates"
HOOKS_DIR="$TEMPLATE_DIR/hooks"

# Clean existing setup
rm -rf $TEMPLATE_DIR

# Create directories
mkdir -p $HOOKS_DIR

# Create pre-push hook
cat << 'EOF' > $HOOKS_DIR/pre-push
#!/bin/bash

# Check for bypass via environment variable
if [ "${SKIP_IP_CHECK}" = "1" ]; then
    echo -e "\033[0;33m⚠️  Bypassing IP check via SKIP_IP_CHECK environment variable\033[0m"
    exit 0
fi

# Check for repo-specific disable
if [ "$(git config --get hooks.allowpush)" = "true" ]; then
    echo -e "\033[0;33m⚠️  IP check disabled for this repository\033[0m"
    exit 0
fi

# Try to use git-ip-check helper if available
if command -v git-ip-check >/dev/null 2>&1; then
    # Use the system-wide helper
    git-ip-check "$(dirname "$0")/ip-check-config.json" SKIP_IP_CHECK hooks.allowpush
    exit $?
elif [ -x "$(dirname "$0")/git-ip-check" ]; then
    # Use local helper if available
    "$(dirname "$0")/git-ip-check" "$(dirname "$0")/ip-check-config.json" SKIP_IP_CHECK hooks.allowpush
    exit $?
fi

# Fallback to inline implementation
# Function to get country flag emoji
get_country_flag() {
    local country=$1
    case $country in
        "AD") echo "🇦🇩" ;;
        "AE") echo "🇦🇪" ;;
        "AF") echo "🇦🇫" ;;
        "AG") echo "🇦🇬" ;;
        "AI") echo "🇦🇮" ;;
        "AL") echo "🇦🇱" ;;
        "AM") echo "🇦🇲" ;;
        "AO") echo "🇦🇴" ;;
        "AQ") echo "🇦🇶" ;;
        "AR") echo "🇦🇷" ;;
        "AS") echo "🇦🇸" ;;
        "AT") echo "🇦🇹" ;;
        "AU") echo "🇦🇺" ;;
        "AW") echo "🇦🇼" ;;
        "AX") echo "🇦🇽" ;;
        "AZ") echo "🇦🇿" ;;
        "BA") echo "🇧🇦" ;;
        "BB") echo "🇧🇧" ;;
        "BD") echo "🇧🇩" ;;
        "BE") echo "🇧🇪" ;;
        "BF") echo "🇧🇫" ;;
        "BG") echo "🇧🇬" ;;
        "BH") echo "🇧🇭" ;;
        "BI") echo "🇧🇮" ;;
        "BJ") echo "🇧🇯" ;;
        "BL") echo "🇧🇱" ;;
        "BM") echo "🇧🇲" ;;
        "BN") echo "🇧🇳" ;;
        "BO") echo "🇧🇴" ;;
        "BQ") echo "🇧🇶" ;;
        "BR") echo "🇧🇷" ;;
        "BS") echo "🇧🇸" ;;
        "BT") echo "🇧🇹" ;;
        "BV") echo "🇧🇻" ;;
        "BW") echo "🇧🇼" ;;
        "BY") echo "🇧🇾" ;;
        "BZ") echo "🇧🇿" ;;
        "CA") echo "🇨🇦" ;;
        "CC") echo "🇨🇨" ;;
        "CD") echo "🇨🇩" ;;
        "CF") echo "🇨🇫" ;;
        "CG") echo "🇨🇬" ;;
        "CH") echo "🇨🇭" ;;
        "CI") echo "🇨🇮" ;;
        "CK") echo "🇨🇰" ;;
        "CL") echo "🇨🇱" ;;
        "CM") echo "🇨🇲" ;;
        "CN") echo "🇨🇳" ;;
        "CO") echo "🇨🇴" ;;
        "CR") echo "🇨🇷" ;;
        "CU") echo "🇨🇺" ;;
        "CV") echo "🇨🇻" ;;
        "CW") echo "🇨🇼" ;;
        "CX") echo "🇨🇽" ;;
        "CY") echo "🇨🇾" ;;
        "CZ") echo "🇨🇿" ;;
        "DE") echo "🇩🇪" ;;
        "DJ") echo "🇩🇯" ;;
        "DK") echo "🇩🇰" ;;
        "DM") echo "🇩🇲" ;;
        "DO") echo "🇩🇴" ;;
        "DZ") echo "🇩🇿" ;;
        "EC") echo "🇪🇨" ;;
        "EE") echo "🇪🇪" ;;
        "EG") echo "🇪🇬" ;;
        "EH") echo "🇪🇭" ;;
        "ER") echo "🇪🇷" ;;
        "ES") echo "🇪🇸" ;;
        "ET") echo "🇪🇹" ;;
        "FI") echo "🇫🇮" ;;
        "FJ") echo "🇫🇯" ;;
        "FK") echo "🇫🇰" ;;
        "FM") echo "🇫🇲" ;;
        "FO") echo "🇫🇴" ;;
        "FR") echo "🇫🇷" ;;
        "GA") echo "🇬🇦" ;;
        "GB") echo "🇬🇧" ;;
        "GD") echo "🇬🇩" ;;
        "GE") echo "🇬🇪" ;;
        "GF") echo "🇬🇫" ;;
        "GG") echo "🇬🇬" ;;
        "GH") echo "🇬🇭" ;;
        "GI") echo "🇬🇮" ;;
        "GL") echo "🇬🇱" ;;
        "GM") echo "🇬🇲" ;;
        "GN") echo "🇬🇳" ;;
        "GP") echo "🇬🇵" ;;
        "GQ") echo "🇬🇶" ;;
        "GR") echo "🇬🇷" ;;
        "GS") echo "🇬🇸" ;;
        "GT") echo "🇬🇹" ;;
        "GU") echo "🇬🇺" ;;
        "GW") echo "🇬🇼" ;;
        "GY") echo "🇬🇾" ;;
        "HK") echo "🇭🇰" ;;
        "HM") echo "🇭🇲" ;;
        "HN") echo "🇭🇳" ;;
        "HR") echo "🇭🇷" ;;
        "HT") echo "🇭🇹" ;;
        "HU") echo "🇭🇺" ;;
        "ID") echo "🇮🇩" ;;
        "IE") echo "🇮🇪" ;;
        "IL") echo "🇮🇱" ;;
        "IM") echo "🇮🇲" ;;
        "IN") echo "🇮🇳" ;;
        "IO") echo "🇮🇴" ;;
        "IQ") echo "🇮🇶" ;;
        "IR") echo "🇮🇷" ;;
        "IS") echo "🇮🇸" ;;
        "IT") echo "🇮🇹" ;;
        "JE") echo "🇯🇪" ;;
        "JM") echo "🇯🇲" ;;
        "JO") echo "🇯🇴" ;;
        "JP") echo "🇯🇵" ;;
        "KE") echo "🇰🇪" ;;
        "KG") echo "🇰🇬" ;;
        "KH") echo "🇰🇭" ;;
        "KI") echo "🇰🇮" ;;
        "KM") echo "🇰🇲" ;;
        "KN") echo "🇰🇳" ;;
        "KP") echo "🇰🇵" ;;
        "KR") echo "🇰🇷" ;;
        "KW") echo "🇰🇼" ;;
        "KY") echo "🇰🇾" ;;
        "KZ") echo "🇰🇿" ;;
        "LA") echo "🇱🇦" ;;
        "LB") echo "🇱🇧" ;;
        "LC") echo "🇱🇨" ;;
        "LI") echo "🇱🇮" ;;
        "LK") echo "🇱🇰" ;;
        "LR") echo "🇱🇷" ;;
        "LS") echo "🇱🇸" ;;
        "LT") echo "🇱🇹" ;;
        "LU") echo "🇱🇺" ;;
        "LV") echo "🇱🇻" ;;
        "LY") echo "🇱🇾" ;;
        "MA") echo "🇲🇦" ;;
        "MC") echo "🇲🇨" ;;
        "MD") echo "🇲🇩" ;;
        "ME") echo "🇲🇪" ;;
        "MF") echo "🇲🇫" ;;
        "MG") echo "🇲🇬" ;;
        "MH") echo "🇲🇭" ;;
        "MK") echo "🇲🇰" ;;
        "ML") echo "🇲🇱" ;;
        "MM") echo "🇲🇲" ;;
        "MN") echo "🇲🇳" ;;
        "MO") echo "🇲🇴" ;;
        "MP") echo "🇲🇵" ;;
        "MQ") echo "🇲🇶" ;;
        "MR") echo "🇲🇷" ;;
        "MS") echo "🇲🇸" ;;
        "MT") echo "🇲🇹" ;;
        "MU") echo "🇲🇺" ;;
        "MV") echo "🇲🇻" ;;
        "MW") echo "🇲🇼" ;;
        "MX") echo "🇲🇽" ;;
        "MY") echo "🇲🇾" ;;
        "MZ") echo "🇲🇿" ;;
        "NA") echo "🇳🇦" ;;
        "NC") echo "🇳🇨" ;;
        "NE") echo "🇳🇪" ;;
        "NF") echo "🇳🇫" ;;
        "NG") echo "🇳🇬" ;;
        "NI") echo "🇳🇮" ;;
        "NL") echo "🇳🇱" ;;
        "NO") echo "🇳🇴" ;;
        "NP") echo "🇳🇵" ;;
        "NR") echo "🇳🇷" ;;
        "NU") echo "🇳🇺" ;;
        "NZ") echo "🇳🇿" ;;
        "OM") echo "🇴🇲" ;;
        "PA") echo "🇵🇦" ;;
        "PE") echo "🇵🇪" ;;
        "PF") echo "🇵🇫" ;;
        "PG") echo "🇵🇬" ;;
        "PH") echo "🇵🇭" ;;
        "PK") echo "🇵🇰" ;;
        "PL") echo "🇵🇱" ;;
        "PM") echo "🇵🇲" ;;
        "PN") echo "🇵🇳" ;;
        "PR") echo "🇵🇷" ;;
        "PS") echo "🇵🇸" ;;
        "PT") echo "🇵🇹" ;;
        "PW") echo "🇵🇼" ;;
        "PY") echo "🇵🇾" ;;
        "QA") echo "🇶🇦" ;;
        "RE") echo "🇷🇪" ;;
        "RO") echo "🇷🇴" ;;
        "RS") echo "🇷🇸" ;;
        "RU") echo "🇷🇺" ;;
        "RW") echo "🇷🇼" ;;
        "SA") echo "🇸🇦" ;;
        "SB") echo "🇸🇧" ;;
        "SC") echo "🇸🇨" ;;
        "SD") echo "🇸🇩" ;;
        "SE") echo "🇸🇪" ;;
        "SG") echo "🇸🇬" ;;
        "SH") echo "🇸🇭" ;;
        "SI") echo "🇸🇮" ;;
        "SJ") echo "🇸🇯" ;;
        "SK") echo "🇸🇰" ;;
        "SL") echo "🇸🇱" ;;
        "SM") echo "🇸🇲" ;;
        "SN") echo "🇸🇳" ;;
        "SO") echo "🇸🇴" ;;
        "SR") echo "🇸🇷" ;;
        "SS") echo "🇸🇸" ;;
        "ST") echo "🇸🇹" ;;
        "SV") echo "🇸🇻" ;;
        "SX") echo "🇸🇽" ;;
        "SY") echo "🇸🇾" ;;
        "SZ") echo "🇸🇿" ;;
        "TC") echo "🇹🇨" ;;
        "TD") echo "🇹🇩" ;;
        "TF") echo "🇹🇫" ;;
        "TG") echo "🇹🇬" ;;
        "TH") echo "🇹🇭" ;;
        "TJ") echo "🇹🇯" ;;
        "TK") echo "🇹🇰" ;;
        "TL") echo "🇹🇱" ;;
        "TM") echo "🇹🇲" ;;
        "TN") echo "🇹🇳" ;;
        "TO") echo "🇹🇴" ;;
        "TR") echo "🇹🇷" ;;
        "TT") echo "🇹🇹" ;;
        "TV") echo "🇹🇻" ;;
        "TW") echo "🇹🇼" ;;
        "TZ") echo "🇹🇿" ;;
        "UA") echo "🇺🇦" ;;
        "UG") echo "🇺🇬" ;;
        "UM") echo "🇺🇲" ;;
        "US") echo "🇺🇸" ;;
        "UY") echo "🇺🇾" ;;
        "UZ") echo "🇺🇿" ;;
        "VA") echo "🇻🇦" ;;
        "VC") echo "🇻🇨" ;;
        "VE") echo "🇻🇪" ;;
        "VG") echo "🇻🇬" ;;
        "VI") echo "🇻🇮" ;;
        "VN") echo "🇻🇳" ;;
        "VU") echo "🇻🇺" ;;
        "WF") echo "🇼🇫" ;;
        "WS") echo "🇼🇸" ;;
        "XK") echo "🇽🇰" ;;
        "YE") echo "🇾🇪" ;;
        "YT") echo "🇾🇹" ;;
        "ZA") echo "🇿🇦" ;;
        "ZM") echo "🇿🇲" ;;
        "ZW") echo "🇿🇼" ;;
        *) echo "🏳️" ;;
    esac
}

# File containing IP info
IP_CACHE="/tmp/git_ip_cache"

# Check if IP cache file exists
if [[ ! -f $IP_CACHE ]]; then
  echo "IP cache file not found. Cannot proceed with push."
  exit 1
fi

# Get country from cache
COUNTRY=$(jq -r .country < $IP_CACHE)

# List of sanctioned countries/regions
# BY: Belarus, CU: Cuba, IR: Iran, KP: North Korea, RU: Russia, SY: Syria
# UA regions are handled separately by checking city/region
SANCTIONED_COUNTRIES=(BY CU IR KP RU SY)

# Check if country is sanctioned
if [[ " ${SANCTIONED_COUNTRIES[@]} " =~ " $COUNTRY " ]]; then
  echo "⛔ Git push blocked: Access denied from sanctioned country: $COUNTRY"
  exit 1
fi

# Special check for sanctioned regions of Ukraine
if [[ "$COUNTRY" == "UA" ]]; then
  REGION=$(jq -r .region < $IP_CACHE | tr '[:upper:]' '[:lower:]')
  CITY=$(jq -r .city < $IP_CACHE | tr '[:upper:]' '[:lower:]')
  
  # Check for sanctioned regions
  if [[ "$REGION" =~ (crimea|donetsk|luhansk) ]] || [[ "$CITY" =~ (crimea|donetsk|luhansk|sevastopol|simferopol) ]]; then
    echo "⛔ Git push blocked: Access denied from sanctioned region: $REGION/$CITY"
    exit 1
  fi
fi

# If we reach here, the push is allowed
COUNTRY_FLAG=$(get_country_flag "$COUNTRY")
    if [ "$COUNTRY_FLAG" = "🏳️" ]; then COUNTRY_FLAG=""; fi
echo "✅ Location verified: $COUNTRY_FLAG $COUNTRY - Push allowed"
EOF

# Make the hook executable
chmod +x $HOOKS_DIR/pre-push

# Create a simple config file for the hook
cat << 'EOF' > $HOOKS_DIR/ip-check-config.json
{
  "blocked_countries": ["BY", "CU", "IR", "KP", "RU", "SY"],
  "blocked_regions": {
    "UA": ["crimea", "donetsk", "luhansk", "sevastopol", "simferopol"]
  },
  "ip_services": [
    "https://ipinfo.io/json",
    "https://ifconfig.co/json"
  ],
  "cache_duration": 300,
  "log_file": "~/.git_ip_error.log"
}
EOF

# Set the template directory
git config --global init.templateDir $TEMPLATE_DIR

echo -e "${GREEN}✅ Git hooks installation complete!${NC}"
echo ""
echo "What's been installed:"
echo "  • Pre-push hook in ~/.git-templates/hooks/"
echo "  • Configuration file for IP checking"
echo "  • Global git template directory configured"

if [ -x "/usr/local/bin/git-ip-check" ] || [ -x "./git-ip-check" ]; then
    echo "  • git-ip-check helper available"
fi

echo ""
echo "All new repositories will automatically use this template."
echo ""
echo "For existing repositories, run:"
echo -e "  ${BLUE}git init${NC}  (inside the repository)"
echo ""
echo "To bypass the IP check temporarily:"
echo -e "  ${BLUE}SKIP_IP_CHECK=1 git push${NC}"
echo ""
echo "To permanently disable for a specific repo:"
echo -e "  ${BLUE}git config hooks.allowpush true${NC}"

#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Clear screen for better presentation
clear

# ASCII Art Header
echo -e "${CYAN}"
cat << 'EOF'
   _____ _ _     _____ _____     _____                     _ 
  / ____(_) |   |_   _|  __ \   / ____|                   | |
 | |  __ _| |_    | | | |__) | | |  __ _   _  __ _ _ __ __| |
 | | |_ | | __|   | | |  ___/  | | |_ | | | |/ _` | '__/ _` |
 | |__| | | |_   _| |_| |      | |__| | |_| | (_| | | | (_| |
  \_____|_|\__| |_____|_|       \_____|\__,_|\__,_|_|  \__,_|
                                                              
EOF
echo -e "${NC}"
echo -e "${BOLD}Protect your Git repositories from unauthorized locations${NC}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}⚠ Error: jq is not installed. Please install jq first.${NC}"
    echo "  On macOS: brew install jq"
    echo "  On Ubuntu/Debian: sudo apt-get install jq"
    exit 1
fi

# Function to display current IP info with better formatting
function show_current_ip() {
    echo -e "${YELLOW}🌐 Detecting your current location...${NC}"
    IP_INFO=$(curl -s https://ipinfo.io)
    if [ -n "$IP_INFO" ]; then
        IP=$(echo "$IP_INFO" | jq -r '.ip')
        COUNTRY=$(echo "$IP_INFO" | jq -r '.country')
        CITY=$(echo "$IP_INFO" | jq -r '.city')
        REGION=$(echo "$IP_INFO" | jq -r '.region')
        ORG=$(echo "$IP_INFO" | jq -r '.org')
        
        echo ""
        echo -e "${GREEN}📍 Your Current Location:${NC}"
        echo -e "   ${BOLD}IP Address:${NC} $IP"
        echo -e "   ${BOLD}Country:${NC} $COUNTRY"
        echo -e "   ${BOLD}City:${NC} $CITY, $REGION"
        echo -e "   ${BOLD}ISP:${NC} $ORG"
        echo ""
    fi
}

# Default lists
DEFAULT_BLOCKED='BY CU IR KP RU SY'
DEFAULT_BLOCKED_NOTE='Belarus (BY), Cuba (CU), Iran (IR), North Korea (KP), Russia (RU), Syria (SY)'

# Note about regional restrictions
echo -e "${YELLOW}ℹ️  Note:${NC} Some regions cannot be blocked at the country level:"
echo "   - Crimea, Donetsk, and Luhansk (part of Ukraine's country code)"
echo "   These require server-side enforcement for proper blocking."
echo ""

# Show current IP
show_current_ip

# Divider
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Ask for configuration mode with better formatting
echo -e "${BLUE}${BOLD}📋 Select Configuration Mode${NC}"
echo ""
echo -e "  ${BOLD}1)${NC} ${GREEN}Quick Setup${NC} - Europe + Americas allowed, sanctioned countries blocked"
echo -e "  ${BOLD}2)${NC} ${MAGENTA}Custom Setup${NC} - Build your own allowed/blocked lists interactively"
echo -e "  ${BOLD}3)${NC} ${CYAN}Use Existing${NC} - Keep your current configuration"
echo ""
read -p "$(echo -e ${BOLD}"Enter your choice [1-3]: "${NC})" mode

case $mode in
    1)
        # Quick setup with predefined lists
        cat > ip-check-config.json << 'EOF'
{
  "allowed_countries": [
    "US", "CA", "MX", "BR", "AR", "CL", "CO", "PE", "VE", "UY", "PY", "EC", "BO", "GY", "SR", "GF",
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", 
    "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "GB", "NO", "CH", "IS", "LI",
    "AD", "MC", "SM", "VA", "BA", "AL", "ME", "RS", "MK", "XK", "MD", "UA", "BY", "RU", "TR"
  ],
  "blocked_countries": ["IR", "KP"],
  "description": "Quick setup: Europe + Americas allowed, Iran and North Korea blocked"
}
EOF
        echo -e "${GREEN}✓ Quick setup configuration created${NC}"
        ;;
    
    2)
        # Custom setup
        echo ""
        echo -e "${BLUE}Custom Configuration${NC}"
        echo ""
        
        # Mode selection
        echo "Select restriction mode:"
        echo "1) Allowlist mode - Only allow specific countries"
        echo "2) Blocklist mode - Block specific countries"
        echo "3) Combined mode - Use both allowed and blocked lists"
        read -p "Select mode (1-3): " restriction_mode
        
        allowed_list="[]"
        blocked_list="[]"
        
        case $restriction_mode in
            1)
                echo ""
                echo "Enter allowed country codes (space-separated, e.g., US CA GB NO):"
                echo "Common codes: US (USA), GB (UK), DE (Germany), FR (France), NO (Norway), SE (Sweden)"
                echo "See https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2 for full list"
                read -p "> " allowed_input
                if [ -n "$allowed_input" ]; then
                    allowed_list=$(echo "$allowed_input" | tr ' ' '\n' | jq -R . | jq -s .)
                fi
                ;;
            
            2)
                echo ""
                echo "Enter blocked country codes (space-separated, e.g., IR KP):"
                echo "Common codes: IR (Iran), KP (North Korea), CN (China), RU (Russia)"
                read -p "> " blocked_input
                if [ -n "$blocked_input" ]; then
                    blocked_list=$(echo "$blocked_input" | tr ' ' '\n' | jq -R . | jq -s .)
                fi
                ;;
            
            3)
                echo ""
                echo "Enter allowed country codes (space-separated):"
                read -p "> " allowed_input
                if [ -n "$allowed_input" ]; then
                    allowed_list=$(echo "$allowed_input" | tr ' ' '\n' | jq -R . | jq -s .)
                fi
                
                echo ""
                echo "Enter blocked country codes (space-separated):"
                read -p "> " blocked_input
                if [ -n "$blocked_input" ]; then
                    blocked_list=$(echo "$blocked_input" | tr ' ' '\n' | jq -R . | jq -s .)
                fi
                ;;
        esac
        
        # Create custom configuration
        cat > ip-check-config.json << EOF
{
  "allowed_countries": $allowed_list,
  "blocked_countries": $blocked_list,
  "description": "Custom configuration"
}
EOF
        echo -e "${GREEN}✓ Custom configuration created${NC}"
        ;;
    
    3)
        # Use existing configuration
        if [ -f "ip-check-config.json" ]; then
            echo -e "${GREEN}✓ Using existing configuration${NC}"
        else
            echo -e "${RED}Error: No existing configuration found${NC}"
            exit 1
        fi
        ;;
    
    *)
        echo -e "${RED}Invalid selection${NC}"
        exit 1
        ;;
esac

# Show configuration summary
echo ""
echo -e "${BLUE}Configuration Summary${NC}"
echo "Allowed countries: $(cat ip-check-config.json | jq -r '.allowed_countries | length') countries"
echo "Blocked countries: $(cat ip-check-config.json | jq -r '.blocked_countries | length') countries"

# Ask if user wants to see the full list
read -p "Show full country lists? (y/n): " show_lists
if [ "$show_lists" = "y" ]; then
    echo ""
    echo "Allowed countries:"
    cat ip-check-config.json | jq -r '.allowed_countries[]' | tr '\n' ' '
    echo ""
    echo ""
    echo "Blocked countries:"
    cat ip-check-config.json | jq -r '.blocked_countries[]' | tr '\n' ' '
    echo ""
fi

# Installation
echo ""
echo -e "${BLUE}Installing Git IP Guard...${NC}"

# Create git templates directory if it doesn't exist
mkdir -p ~/.git-templates/hooks

# Copy the pre-push hook and config
cp pre-push ~/.git-templates/hooks/
cp ip-check-config.json ~/.git-templates/hooks/
chmod +x ~/.git-templates/hooks/pre-push

# Set global git config
git config --global init.templateDir ~/.git-templates

echo ""
echo -e "${GREEN}✅ Git IP Guard installed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. For NEW repositories: The hook will be automatically installed"
echo "2. For EXISTING repositories: Run ./apply-to-existing-repos.sh"
echo "3. To test: Run ./test-ip-check.sh"
echo "4. To reconfigure: Run ./setup.sh again"
echo ""
echo -e "${YELLOW}Configuration file location:${NC} ~/.git-templates/hooks/ip-check-config.json"

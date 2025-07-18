#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}       Git IP Guard Test Suite          ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to display test results
show_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
    fi
}

# Parse command line arguments
TEST_TYPE="all"
if [ $# -gt 0 ]; then
    TEST_TYPE=$1
fi

# Show usage
if [ "$TEST_TYPE" = "--help" ] || [ "$TEST_TYPE" = "-h" ]; then
    echo "Usage: $0 [test-type]"
    echo ""
    echo "Test types:"
    echo "  all      - Run all tests (default)"
    echo "  current  - Test with current IP location"
    echo "  bypass   - Test bypass mechanisms"
    echo "  helper   - Test git-ip-check helper"
    echo ""
    echo "Examples:"
    echo "  ./test.sh          # Run all tests"
    echo "  ./test.sh current  # Test current location only"
    echo "  ./test.sh bypass   # Test bypass methods"
    exit 0
fi

# Test 1: Current Location Check
test_current_location() {
    echo -e "${YELLOW}Test 1: Current Location Check${NC}"
    echo "----------------------------------------"
    
    # Get current IP info
    IP_INFO=$(curl -s https://ipinfo.io/json)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to fetch IP information${NC}"
        return 1
    fi
    
    # Save to cache for testing
    echo "$IP_INFO" > /tmp/git_ip_cache
    
    # Extract location info
    COUNTRY=$(echo "$IP_INFO" | jq -r '.country // "Unknown"')
    CITY=$(echo "$IP_INFO" | jq -r '.city // "Unknown"')
    IP=$(echo "$IP_INFO" | jq -r '.ip // "Unknown"')
    
    echo "Your current location:"
    echo "  IP: $IP"
    echo "  Country: $COUNTRY"
    echo "  City: $CITY"
    echo ""
    
    # Test if the pre-push hook would block
    BLOCKED_COUNTRIES=("BY" "CU" "IR" "KP" "RU" "SY")
    if [[ " ${BLOCKED_COUNTRIES[@]} " =~ " $COUNTRY " ]]; then
        echo -e "${RED}⛔ Your current location ($COUNTRY) would be BLOCKED${NC}"
    else
        echo -e "${GREEN}✅ Your current location ($COUNTRY) is ALLOWED${NC}"
    fi
    echo ""
}

# Test 2: Bypass Mechanisms
test_bypass_mechanisms() {
    echo -e "${YELLOW}Test 2: Bypass Mechanisms${NC}"
    echo "----------------------------------------"
    
    # Create a test repository
    TEST_REPO="/tmp/test-git-ip-guard-$$"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init --quiet
    
    # Copy the pre-push hook
    mkdir -p .git/hooks
    cp ~/.git-templates/hooks/pre-push .git/hooks/
    cp ~/.git-templates/hooks/ip-check-config.json .git/hooks/ 2>/dev/null || true
    
    # Ensure we have a cache file
    if [ ! -f /tmp/git_ip_cache ]; then
        curl -s https://ipinfo.io/json > /tmp/git_ip_cache
    fi
    
    # Test 2.1: Environment variable bypass
    echo "Testing SKIP_IP_CHECK environment variable..."
    SKIP_IP_CHECK=1 .git/hooks/pre-push 2>&1 | grep -q "Bypassing IP check"
    show_result $? "Environment variable bypass"
    
    # Test 2.2: Repository config bypass
    echo "Testing git config bypass..."
    git config hooks.allowpush true
    .git/hooks/pre-push 2>&1 | grep -q "IP check disabled"
    show_result $? "Repository config bypass"
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    echo ""
}

# Test 3: Helper Script
test_helper_script() {
    echo -e "${YELLOW}Test 3: Git IP Check Helper${NC}"
    echo "----------------------------------------"
    
    # Check if helper is available
    if command -v git-ip-check >/dev/null 2>&1; then
        echo "Testing system-wide helper..."
        HELPER_CMD="git-ip-check"
    elif [ -x "./git-ip-check" ]; then
        echo "Testing local helper..."
        HELPER_CMD="./git-ip-check"
    else
        echo -e "${YELLOW}Helper script not found, skipping helper tests${NC}"
        echo ""
        return
    fi
    
    # Create test config
    TEST_CONFIG="/tmp/test-config-$$.json"
    cat > "$TEST_CONFIG" << EOF
{
  "blocked_countries": ["XX", "YY"],
  "blocked_regions": {},
  "ip_services": ["https://ipinfo.io/json"],
  "cache_duration": 300,
  "log_file": "/tmp/test-ip-error.log"
}
EOF
    
    # Test with current location (should pass with test config)
    $HELPER_CMD "$TEST_CONFIG" >/dev/null 2>&1
    show_result $? "Helper with test config"
    
    # Test with bypass
    SKIP_IP_CHECK=1 $HELPER_CMD "$TEST_CONFIG" 2>&1 | grep -q "Bypassing"
    show_result $? "Helper with bypass variable"
    
    # Clean up
    rm -f "$TEST_CONFIG"
    echo ""
}

# Test 4: Simulated Push Test
test_simulated_push() {
    echo -e "${YELLOW}Test 4: Simulated Push Test${NC}"
    echo "----------------------------------------"
    
    # Create a test repository
    TEST_REPO="/tmp/test-push-$$"
    mkdir -p "$TEST_REPO"
    cd "$TEST_REPO"
    git init --quiet
    
    # Copy the pre-push hook
    mkdir -p .git/hooks
    cp ~/.git-templates/hooks/pre-push .git/hooks/
    cp ~/.git-templates/hooks/ip-check-config.json .git/hooks/ 2>/dev/null || true
    
    # Create a test commit
    echo "test" > test.txt
    git add test.txt
    git commit -m "Test commit" --quiet
    
    # Add a fake remote
    git remote add origin https://github.com/test/test.git
    
    echo "Simulating git push (hook will run)..."
    
    # Run the pre-push hook directly
    .git/hooks/pre-push
    RESULT=$?
    
    if [ $RESULT -eq 0 ]; then
        echo -e "${GREEN}✅ Push would be ALLOWED from your location${NC}"
    else
        echo -e "${RED}⛔ Push would be BLOCKED from your location${NC}"
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    echo ""
}

# Main test execution
case "$TEST_TYPE" in
    "current")
        test_current_location
        ;;
    "bypass")
        test_bypass_mechanisms
        ;;
    "helper")
        test_helper_script
        ;;
    "all"|*)
        test_current_location
        test_bypass_mechanisms
        test_helper_script
        test_simulated_push
        
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}         Test Suite Complete            ${NC}"
        echo -e "${BLUE}========================================${NC}"
        ;;
esac

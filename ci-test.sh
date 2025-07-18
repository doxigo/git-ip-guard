#!/bin/bash

# CI Test Script for Git IP Guard
# Tests the IP checking functionality with mocked locations

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Git IP Guard CI Test Suite         ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name=$1
    local country=$2
    local expected_result=$3
    
    echo -n "Testing $test_name (Country: $country)... "
    
    # Run the pre-commit hook with mocked country
    CI_MOCK_COUNTRY="$country" .git/hooks/pre-commit > /tmp/test_output 2>&1
    local exit_code=$?
    
    if [ "$expected_result" = "pass" ]; then
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}PASSED${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAILED${NC}"
            echo "  Expected: Pass (exit 0)"
            echo "  Got: Blocked (exit $exit_code)"
            cat /tmp/test_output | sed 's/^/  /'
            ((TESTS_FAILED++))
        fi
    else
        if [ $exit_code -ne 0 ]; then
            echo -e "${GREEN}PASSED${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAILED${NC}"
            echo "  Expected: Block (exit 1)"
            echo "  Got: Pass (exit 0)"
            cat /tmp/test_output | sed 's/^/  /'
            ((TESTS_FAILED++))
        fi
    fi
}

# Test European countries (should pass)
echo -e "${YELLOW}Testing European countries (should pass):${NC}"
run_test "Norway" "NO" "pass"
run_test "Germany" "DE" "pass"
run_test "France" "FR" "pass"
run_test "United Kingdom" "GB" "pass"
run_test "Spain" "ES" "pass"
run_test "Italy" "IT" "pass"
run_test "Sweden" "SE" "pass"
run_test "Poland" "PL" "pass"
echo ""

# Test American countries (should pass)
echo -e "${YELLOW}Testing American countries (should pass):${NC}"
run_test "United States" "US" "pass"
run_test "Canada" "CA" "pass"
run_test "Mexico" "MX" "pass"
run_test "Brazil" "BR" "pass"
run_test "Argentina" "AR" "pass"
echo ""

# Test blocked countries (should fail)
echo -e "${YELLOW}Testing blocked countries (should fail):${NC}"
run_test "Iran" "IR" "fail"
run_test "North Korea" "KP" "fail"
echo ""

# Test non-allowed countries (should fail)
echo -e "${YELLOW}Testing non-allowed countries (should fail):${NC}"
run_test "China" "CN" "fail"
run_test "Japan" "JP" "fail"
run_test "Australia" "AU" "fail"
run_test "India" "IN" "fail"
run_test "South Africa" "ZA" "fail"
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary:${NC}"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

# Check error log
if [ -f ~/.git_ip_error.log ]; then
    echo ""
    echo -e "${YELLOW}Recent error log entries:${NC}"
    tail -5 ~/.git_ip_error.log
fi

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

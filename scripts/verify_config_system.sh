#!/bin/bash
# Verification script for Medusa configuration system implementation

set -e

echo ""
echo "========================================"
echo "  Configuration System Verification"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check counter
CHECKS_PASSED=0
CHECKS_FAILED=0

# Helper function
check_file() {
  local file=$1
  local description=$2

  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $description"
    ((CHECKS_PASSED++))
  else
    echo -e "${RED}✗${NC} $description (missing: $file)"
    ((CHECKS_FAILED++))
  fi
}

# Navigate to project root
cd "$(dirname "$0")/.."

echo "Checking core modules..."
check_file "src/q/config/parser.q" "Parser module"
check_file "src/q/config/validator.q" "Validator module"
check_file "src/q/config/loader.q" "Loader module"
check_file "src/q/config/config.q" "Main API module"
echo ""

echo "Checking configuration files..."
check_file "configs/defaults.conf" "System defaults"
check_file "configs/strategies/example_strategy.conf" "Example strategy config"
check_file "configs/exchanges/kraken.conf" "Kraken exchange config"
echo ""

echo "Checking test files..."
check_file "tests/q/test_parser.q" "Parser tests"
check_file "tests/q/test_validator.q" "Validator tests"
check_file "tests/q/test_loader.q" "Loader tests"
check_file "tests/q/test_config.q" "Integration tests"
check_file "tests/q/test_config_all.q" "Comprehensive test runner"
echo ""

echo "Checking documentation..."
check_file "src/q/config/README.md" "Configuration README"
check_file "src/q/config/example_usage.q" "Usage examples"
check_file "ai/docs/configuration-system-implementation-summary.md" "Implementation summary"
echo ""

echo "Checking init.q integration..."
if grep -q "\\l config/config.q" src/q/init.q; then
  echo -e "${GREEN}✓${NC} config.q loaded in init.q"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}✗${NC} config.q not loaded in init.q"
  ((CHECKS_FAILED++))
fi

if grep -q "\\.conf" src/q/init.q; then
  echo -e "${GREEN}✓${NC} .conf namespace listed in init.q"
  ((CHECKS_PASSED++))
else
  echo -e "${RED}✗${NC} .conf namespace not listed in init.q"
  ((CHECKS_FAILED++))
fi
echo ""

echo "Checking file structure..."
MODULE_COUNT=$(find src/q/config -name "*.q" | wc -l | xargs)
if [ "$MODULE_COUNT" -eq 2 ]; then
  echo -e "${GREEN}✓${NC} All q modules present ($MODULE_COUNT files)"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Expected 2 q modules, found $MODULE_COUNT"
fi

CONF_COUNT=$(find configs -name "*.conf" | wc -l | xargs)
if [ "$CONF_COUNT" -eq 3 ]; then
  echo -e "${GREEN}✓${NC} All config files present ($CONF_COUNT files)"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Expected 3 config files, found $CONF_COUNT"
fi

TEST_COUNT=$(find tests/q -name "test_*.q" | grep -E "(parser|validator|loader|config)" | wc -l | xargs)
if [ "$TEST_COUNT" -ge 5 ]; then
  echo -e "${GREEN}✓${NC} All test files present ($TEST_COUNT files)"
  ((CHECKS_PASSED++))
else
  echo -e "${YELLOW}⚠${NC} Expected 5+ test files, found $TEST_COUNT"
fi
echo ""

echo "Summary:"
echo "--------"
echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed! Configuration system is ready.${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Run tests: q tests/q/test_config_all.q"
  echo "  2. Try examples: q src/q/config/example_usage.q"
  echo "  3. Load Medusa: q src/q/init.q"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
  echo ""
  exit 1
fi

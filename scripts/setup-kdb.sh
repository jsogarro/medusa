#!/usr/bin/env bash
# Setup script for q/kdb+ environment

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "Medusa — q/kdb+ Environment Setup"
echo "========================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
Q_SRC_DIR="$PROJECT_ROOT/src/q"
DATA_DIR="$PROJECT_ROOT/data"

# Check if kdb+ is installed
echo "Checking kdb+ installation..."
if command -v q &> /dev/null; then
    Q_VERSION=$(q -version 2>&1 | head -n 1 || echo "unknown")
    echo -e "${GREEN}✓ kdb+ found: $Q_VERSION${NC}"
else
    echo -e "${RED}✗ kdb+ not found in PATH${NC}"
    echo ""
    echo "Please install kdb+ from https://kx.com/kdb-insights-personal-edition-license-download/"
    echo "Or use Docker: make docker-up"
    exit 1
fi

# Check QHOME
if [ -z "${QHOME:-}" ]; then
    echo -e "${YELLOW}⚠ QHOME not set, attempting auto-detect${NC}"
    if [ -d "$HOME/q" ]; then
        export QHOME="$HOME/q"
    elif [ -d "/usr/local/q" ]; then
        export QHOME="/usr/local/q"
    else
        echo -e "${RED}✗ Could not detect QHOME${NC}"
        echo "Please set QHOME environment variable"
        exit 1
    fi
fi
echo -e "${GREEN}✓ QHOME: $QHOME${NC}"

# Create data directories
echo ""
echo "Creating directory structure..."
mkdir -p "$DATA_DIR/orderbooks"
mkdir -p "$DATA_DIR/trades"
mkdir -p "$DATA_DIR/positions"
echo -e "${GREEN}✓ Data directories created${NC}"

# Validate q source structure
echo ""
echo "Validating q source structure..."
REQUIRED_DIRS=("schema" "lib" "exchange" "engine" "audit" "risk" "config")

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$Q_SRC_DIR/$dir" ]; then
        echo -e "${GREEN}✓ $dir/${NC}"
    else
        echo -e "${RED}✗ Missing: $dir/${NC}"
        exit 1
    fi
done

if [ -f "$Q_SRC_DIR/init.q" ]; then
    echo -e "${GREEN}✓ init.q found${NC}"
else
    echo -e "${RED}✗ init.q not found${NC}"
    exit 1
fi

echo ""
echo "========================================"
echo -e "${GREEN}✓ q/kdb+ environment setup complete${NC}"
echo "========================================"
echo ""
echo "To start kdb+ REPL:"
echo "  rlwrap q $Q_SRC_DIR/init.q"
echo ""

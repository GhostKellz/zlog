#!/usr/bin/env bash
# Comprehensive sanitizer testing for zlog
# Part of Week 1-2: Stability Hardening

set -e

echo "🧪 Running zlog with sanitizers..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED=0

# Test with AddressSanitizer (ASan)
echo -e "${YELLOW}=== AddressSanitizer (ASan) ===${NC}"
if zig build test:quick -Dfile_targets=true -fsanitize-address 2>&1 | tee asan.log; then
    echo -e "${GREEN}✓ ASan tests passed${NC}"
else
    echo -e "${RED}✗ ASan tests failed${NC}"
    FAILED=1
fi
echo ""

# Test with UndefinedBehaviorSanitizer (UBSan)
echo -e "${YELLOW}=== UndefinedBehaviorSanitizer (UBSan) ===${NC}"
if zig build test:quick -Dfile_targets=true -fsanitize-undefined 2>&1 | tee ubsan.log; then
    echo -e "${GREEN}✓ UBSan tests passed${NC}"
else
    echo -e "${RED}✗ UBSan tests failed${NC}"
    FAILED=1
fi
echo ""

# Test with ThreadSanitizer (TSan)
echo -e "${YELLOW}=== ThreadSanitizer (TSan) ===${NC}"
if zig build test:quick -Dfile_targets=true -fsanitize-thread 2>&1 | tee tsan.log; then
    echo -e "${GREEN}✓ TSan tests passed${NC}"
else
    echo -e "${RED}✗ TSan tests failed${NC}"
    FAILED=1
fi
echo ""

# Summary
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All sanitizer tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some sanitizer tests failed${NC}"
    echo "Check asan.log, ubsan.log, tsan.log for details"
    exit 1
fi

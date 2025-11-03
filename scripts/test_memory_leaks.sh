#!/usr/bin/env bash
# Memory leak detection with valgrind
# Part of Week 1-2: Stability Hardening

set -e

echo "🔍 Memory leak detection with valgrind..."

if ! command -v valgrind &> /dev/null; then
    echo "❌ valgrind not installed"
    echo "Install with: sudo apt-get install valgrind"
    exit 1
fi

# Build test binary
echo "Building test binary..."
zig build -Dfile_targets=true -Dasync_io=true

# Run with valgrind
echo ""
echo "Running valgrind leak check..."
valgrind \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --verbose \
    --log-file=valgrind.log \
    ./zig-out/bin/zlog

echo ""
echo "Valgrind output saved to valgrind.log"

# Check for leaks
if grep -q "definitely lost: 0 bytes" valgrind.log && \
   grep -q "indirectly lost: 0 bytes" valgrind.log; then
    echo "✓ No memory leaks detected!"
    exit 0
else
    echo "✗ Memory leaks detected! Check valgrind.log"
    exit 1
fi

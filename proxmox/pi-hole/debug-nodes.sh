#!/bin/bash

echo "=== Raw pvecm nodes output ==="
pvecm nodes 2>/dev/null

echo ""
echo "=== Filtered output ==="
pvecm nodes 2>/dev/null | grep -E "^[[:space:]]*[0-9]+"

echo ""
echo "=== Current parsing (wrong) ==="
pvecm nodes 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | awk '{printf "%d. %s (Status: %s)\n", NR, $3, $4}'

echo ""
echo "=== All columns ==="
pvecm nodes 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | awk '{print "Col1:", $1, "Col2:", $2, "Col3:", $3, "Col4:", $4, "Col5:", $5}' 
#!/bin/bash

# Add frozen_string_literal pragma to Ruby files missing it

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Adding frozen_string_literal pragmas...${NC}"

count=0

# Function to add pragma to file
add_pragma() {
    local file="$1"
    echo -n "Processing $file... "
    
    # Create temporary file with pragma at top
    {
        echo "# frozen_string_literal: true"
        echo ""
        cat "$file"
    } > "$file.tmp"
    
    # Replace original file
    mv "$file.tmp" "$file"
    echo -e "${GREEN}✓${NC}"
    ((count++))
}

# Find and process backend files
echo "Backend files:"
find server/app -name "*.rb" -exec grep -L "frozen_string_literal" {} \; | while read -r file; do
    add_pragma "$file"
done

# Find and process worker files
echo "Worker files:"
find worker/app -name "*.rb" -exec grep -L "frozen_string_literal" {} \; | while read -r file; do
    add_pragma "$file"
done

echo -e "${GREEN}Completed! Added pragmas to Ruby files.${NC}"
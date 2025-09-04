#!/bin/bash

# Quick fix script for AxiosResponse mock issues
# This script updates test files to use the proper createMockAxiosResponse pattern

echo "🔧 Fixing AxiosResponse mock patterns in test files..."

# Find all test files that need AxiosResponse mocks
find frontend/src -name "*.test.ts" -o -name "*.test.tsx" | while read -r file; do
  if grep -q "mockApi.*mockResolvedValue" "$file" && ! grep -q "createMockAxiosResponse" "$file"; then
    echo "Updating: $file"
    
    # Add import for createMockAxiosResponse if not present
    if ! grep -q "createMockAxiosResponse" "$file"; then
      sed -i '1a import { createMockAxiosResponse } from "@/test-utils";' "$file"
    fi
    
    # Replace common patterns with proper AxiosResponse structure
    sed -i 's/mockApi\.\([a-z]*\)\.mockResolvedValue({/mockApi.\1.mockResolvedValue(createMockAxiosResponse({/g' "$file"
    sed -i 's/mockResolvedValue({\s*success: true,/mockResolvedValue(createMockAxiosResponse({/g' "$file"
    sed -i 's/mockResolvedValue({\s*data:/mockResolvedValue(createMockAxiosResponse(/g' "$file"
  fi
done

echo "✅ AxiosResponse mock patterns updated"
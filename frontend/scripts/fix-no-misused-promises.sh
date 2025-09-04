#!/bin/bash

# Script to fix @typescript-eslint/no-misused-promises errors
# This script adds 'void' wrapper to async function calls in event handlers

set -e

echo "Fixing @typescript-eslint/no-misused-promises errors..."

# Get all files with no-misused-promises errors
FILES=$(npm run lint -- --format=compact 2>&1 | grep "no-misused-promises" | cut -d: -f1 | sort | uniq)

echo "Files to fix:"
echo "$FILES"

for file in $FILES; do
  if [[ -f "$file" ]]; then
    echo "Processing $file..."
    
    # Common patterns to fix:
    # onClick={() => asyncFunction(...)} -> onClick={() => void asyncFunction(...)}
    # onSubmit={asyncFunction} -> onSubmit={(e) => void asyncFunction(e)}
    # onChange={() => asyncFunction(...)} -> onChange={() => void asyncFunction(...)}
    
    # Pattern 1: onClick={() => function(args)}
    sed -i 's/onClick={() => \([^}]*\)}/onClick={() => void \1}/g' "$file"
    
    # Pattern 2: onSubmit={function}
    sed -i 's/onSubmit={\([^}]*\)}/onSubmit={(e) => void \1(e)}/g' "$file"
    
    # Pattern 3: onChange={() => function(args)}
    sed -i 's/onChange={() => \([^}]*\)}/onChange={() => void \1}/g' "$file"
    
    # Pattern 4: onFocus={() => function(args)}  
    sed -i 's/onFocus={() => \([^}]*\)}/onFocus={() => void \1}/g' "$file"
    
    # Pattern 5: onBlur={() => function(args)}
    sed -i 's/onBlur={() => \([^}]*\)}/onBlur={() => void \1}/g' "$file"
    
    # Pattern 6: callback props with async functions
    sed -i 's/={\([^}]*async[^}]*\)}/={(...args) => void \1(...args)}/g' "$file"
    
  fi
done

echo "Fixed no-misused-promises errors in frontend files"
echo "Running lint check to verify fixes..."

npm run lint | grep "no-misused-promises" | wc -l || echo "All no-misused-promises errors fixed!"
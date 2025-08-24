#!/bin/bash

# Remove debug code from frontend and backend
# Excludes scripts/ directories and legitimate logging

echo "🧹 Cleaning debug code from platform..."

# Frontend: Remove console.log (excluding scripts directory)
echo "Frontend: Removing console.log statements..."
find frontend/src -name "*.ts" -o -name "*.tsx" | grep -v "/scripts/" | while read file; do
    if grep -q "console\.log" "$file"; then
        echo "  Cleaning: $file"
        # Remove console.log lines (but not console.error/warn/info)
        sed -i '/console\.log(/d' "$file"
    fi
done

# Backend: Remove puts, p, print statements  
echo "Backend: Removing debug statements..."
find server/app -name "*.rb" | while read file; do
    if grep -q "^\s*puts\s\|^\s*p\s\|^\s*print\s" "$file"; then
        echo "  Cleaning: $file"
        # Remove lines that start with puts, p, or print (with optional whitespace)
        sed -i '/^\s*puts\s/d; /^\s*p\s/d; /^\s*print\s/d' "$file"
    fi
done

# Worker: Remove debug statements
echo "Worker: Removing debug statements..."
find worker/app -name "*.rb" | while read file; do
    if grep -q "^\s*puts\s\|^\s*p\s\|^\s*print\s" "$file"; then
        echo "  Cleaning: $file"
        sed -i '/^\s*puts\s/d; /^\s*p\s/d; /^\s*print\s/d' "$file"
    fi
done

echo "✅ Debug code cleanup completed!"
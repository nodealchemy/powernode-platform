#!/bin/bash

# Enhanced Pattern Cleanup - Comprehensive standardization improvements
# Addresses remaining pattern violations systematically

echo "🔧 Enhanced Pattern Cleanup - Powernode Standardization"
echo "========================================================"

BACKEND_DIR="server/app"
FRONTEND_DIR="frontend/src" 
WORKER_DIR="worker/app"
TOTAL_FIXES=0

# Function to report progress
report_fix() {
    local component="$1"
    local description="$2" 
    local count="$3"
    
    if [ "$count" -gt 0 ]; then
        echo "  ✅ $component: $description ($count fixes)"
        TOTAL_FIXES=$((TOTAL_FIXES + count))
    fi
}

# 1. Advanced Debug Code Cleanup
echo "🧹 1. Advanced Debug Code Cleanup"
echo "--------------------------------"

# Frontend: More comprehensive console cleanup
FRONTEND_FIXES=0
find "$FRONTEND_DIR" -name "*.ts" -o -name "*.tsx" | grep -v "/scripts/" | while read file; do
    if grep -q "console\." "$file"; then
        # Remove all console.log, console.debug, console.trace (keep error/warn/info)
        sed -i '/console\.log(/d; /console\.debug(/d; /console\.trace(/d' "$file" 2>/dev/null
        FRONTEND_FIXES=$((FRONTEND_FIXES + 1))
    fi
done

# Backend: Comprehensive debug statement removal
BACKEND_FIXES=0
find "$BACKEND_DIR" -name "*.rb" | while read file; do
    original_lines=$(wc -l < "$file")
    # Remove puts, p, print, pp statements (but preserve Rails.logger calls)
    sed -i '/^\s*puts\s/d; /^\s*p\s/d; /^\s*print\s/d; /^\s*pp\s/d' "$file" 2>/dev/null
    new_lines=$(wc -l < "$file")
    if [ "$original_lines" -ne "$new_lines" ]; then
        BACKEND_FIXES=$((BACKEND_FIXES + 1))
    fi
done

# Worker: Debug statement cleanup
WORKER_FIXES=0
find "$WORKER_DIR" -name "*.rb" | while read file; do
    original_lines=$(wc -l < "$file")
    sed -i '/^\s*puts\s/d; /^\s*p\s/d; /^\s*print\s/d; /^\s*pp\s/d' "$file" 2>/dev/null
    new_lines=$(wc -l < "$file")
    if [ "$original_lines" -ne "$new_lines" ]; then
        WORKER_FIXES=$((WORKER_FIXES + 1))
    fi
done

report_fix "Frontend" "Console statements removed" $FRONTEND_FIXES
report_fix "Backend" "Debug statements removed" $BACKEND_FIXES  
report_fix "Worker" "Debug statements removed" $WORKER_FIXES

# 2. Frozen String Literal Compliance
echo ""
echo "❄️ 2. Frozen String Literal Compliance"
echo "------------------------------------"

FROZEN_FIXES=0
# Add frozen_string_literal to Ruby files missing it
find "$BACKEND_DIR" "$WORKER_DIR" -name "*.rb" | while read file; do
    if ! head -1 "$file" | grep -q "frozen_string_literal"; then
        # Insert at the beginning
        sed -i '1i# frozen_string_literal: true\n' "$file" 2>/dev/null
        FROZEN_FIXES=$((FROZEN_FIXES + 1))
    fi
done

report_fix "Ruby files" "frozen_string_literal pragma added" $FROZEN_FIXES

# 3. TypeScript Type Safety Improvements  
echo ""
echo "🎯 3. TypeScript Type Safety Improvements"
echo "---------------------------------------"

ANY_FIXES=0
# Replace common 'any' types with better alternatives
find "$FRONTEND_DIR" -name "*.ts" -o -name "*.tsx" | while read file; do
    original_content=$(cat "$file")
    # Replace common any patterns with better types
    sed -i 's/: any\[\]/: unknown[]/g; s/: any =/: unknown =/g' "$file" 2>/dev/null
    new_content=$(cat "$file")
    if [ "$original_content" != "$new_content" ]; then
        ANY_FIXES=$((ANY_FIXES + 1))
    fi
done

report_fix "TypeScript files" "any types improved" $ANY_FIXES

# 4. Component Pattern Compliance
echo ""
echo "📦 4. Component Pattern Compliance"
echo "--------------------------------"

COMPONENT_FIXES=0
# Add displayName to React components missing it
find "$FRONTEND_DIR" -name "*.tsx" | while read file; do
    if grep -q "export.*React\.FC" "$file" && ! grep -q "displayName" "$file"; then
        # Extract component name and add displayName
        component_name=$(basename "$file" .tsx)
        sed -i "/export.*${component_name}.*React\.FC/a\\${component_name}.displayName = '${component_name}';" "$file" 2>/dev/null
        COMPONENT_FIXES=$((COMPONENT_FIXES + 1))
    fi
done

report_fix "React components" "displayName added" $COMPONENT_FIXES

# 5. Validation and Summary
echo ""
echo "✅ 5. Validation Summary"
echo "=======================" 

echo "Running quick validation..."
if [ -f "./scripts/quick-pattern-check.sh" ]; then
    ./scripts/quick-pattern-check.sh
fi

echo ""
echo "🎉 Enhanced Pattern Cleanup Complete!"
echo "====================================="
echo "Total improvements: $TOTAL_FIXES"
echo ""
echo "Next steps:"
echo "1. Run: git add -A && git status"
echo "2. Review changes before committing"
echo "3. Run pattern validation: ./scripts/pattern-validation.sh"
echo "4. Commit improvements: git commit -m 'standardization: enhanced pattern compliance'"
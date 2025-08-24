#!/bin/bash

# Update API Controllers to use standard ApiResponse concern
# Converts manual render json: patterns to standardized concern methods

echo "🔄 Updating API Controllers to use ApiResponse concern..."

CONTROLLERS_DIR="server/app/controllers/api/v1"
TOTAL_UPDATES=0

# Find all API controllers
find "$CONTROLLERS_DIR" -name "*.rb" -type f | while read controller; do
    echo "Processing: $(basename "$controller")"
    
    # Count changes made to this file
    FILE_CHANGES=0
    
    # Create backup
    cp "$controller" "${controller}.bak"
    
    # Replace success responses
    if grep -q "render json:.*success.*true.*data" "$controller"; then
        sed -i 's/render json: { success: true, data: \([^}]*\) }/render_success(\1)/g' "$controller"
        FILE_CHANGES=$((FILE_CHANGES + 1))
    fi
    
    # Replace simple success responses without data
    if grep -q "render json:.*success.*true" "$controller"; then
        sed -i 's/render json: { success: true }/render_success/g' "$controller"
        FILE_CHANGES=$((FILE_CHANGES + 1))
    fi
    
    # Replace error responses
    if grep -q "render json:.*success.*false.*error" "$controller"; then
        sed -i 's/render json: { success: false, error: \([^,}]*\) }, status: \([0-9]*\)/render_error(\1, status: :\2)/g' "$controller"
        FILE_CHANGES=$((FILE_CHANGES + 1))
    fi
    
    # Replace common error patterns
    if grep -q "render json:.*success.*false.*error" "$controller"; then
        # Handle 500 errors specially
        sed -i 's/render json: { success: false, error: \([^}]*\) }, status: 500/render_internal_error(\1)/g' "$controller"
        # Handle 404 errors
        sed -i 's/render json: { success: false, error: \([^}]*\) }, status: 404/render_not_found(\1)/g' "$controller"
        # Handle 422 errors
        sed -i 's/render json: { success: false, error: \([^}]*\) }, status: 422/render_validation_error(\1)/g' "$controller"
        FILE_CHANGES=$((FILE_CHANGES + 1))
    fi
    
    # Replace created responses (201 status)
    if grep -q "render json:.*status: 201\|render json:.*status: :created" "$controller"; then
        sed -i 's/render json: \([^,]*\), status: \(201\|:created\)/render_created(\1)/g' "$controller"
        FILE_CHANGES=$((FILE_CHANGES + 1))
    fi
    
    # Replace no_content responses
    if grep -q "head :no_content" "$controller"; then
        sed -i 's/head :no_content/render_no_content/g' "$controller"
        FILE_CHANGES=$((FILE_CHANGES + 1))
    fi
    
    if [ $FILE_CHANGES -gt 0 ]; then
        echo "  ✅ Updated $(basename "$controller"): $FILE_CHANGES changes"
        TOTAL_UPDATES=$((TOTAL_UPDATES + FILE_CHANGES))
    else
        echo "  ℹ️ No changes needed for $(basename "$controller")"
        # Remove backup if no changes
        rm "${controller}.bak"
    fi
done

echo ""
echo "🎉 API Response Updates Complete!"
echo "Total response patterns updated: $TOTAL_UPDATES"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff server/app/controllers/"
echo "2. Test updated controllers"
echo "3. Run pattern validation: ./scripts/pattern-validation.sh"
echo "4. Commit changes when ready"
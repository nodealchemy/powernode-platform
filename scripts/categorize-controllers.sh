#!/bin/bash
# categorize-controllers.sh - Categorize controllers by migration complexity
#
# Usage: ./scripts/categorize-controllers.sh
#
# Categorizes controllers into:
# - Category A: Simple (automated migration ready)
# - Category B: Complex (manual migration needed)
# - Category C: Special (exclude from migration)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}🔍 Categorizing Controllers for API Response Migration${NC}"
echo ""

# Find all controllers
CONTROLLER_DIR="server/app/controllers"

# Category C: Special cases (webhooks, streaming, etc.) - EXCLUDE
echo -e "${YELLOW}📦 Category C: Special Cases (Exclude from Migration)${NC}"
echo -e "${CYAN}   Webhooks, streaming, and external API handlers${NC}"
echo ""

CATEGORY_C_FILES=$(find "$CONTROLLER_DIR" -name "*_controller.rb" -type f | \
  xargs grep -l "render json:" | \
  grep -E "webhook|stream|export" | sort)

CATEGORY_C_COUNT=0
for file in $CATEGORY_C_FILES; do
  count=$(grep -c "render json:" "$file" 2>/dev/null || echo "0")
  if [ "$count" -gt 0 ]; then
    echo "   $(basename "$file" .rb): $count renders"
    CATEGORY_C_COUNT=$((CATEGORY_C_COUNT + count))
  fi
done

echo -e "   ${GREEN}Total Category C renders: $CATEGORY_C_COUNT${NC}"
echo ""

# Create temp files for categorization
TEMP_SIMPLE=$(mktemp)
TEMP_COMPLEX=$(mktemp)

# Find all controllers with manual JSON renders (excluding Category C)
ALL_CONTROLLERS=$(find "$CONTROLLER_DIR" -name "*_controller.rb" -type f | \
  xargs grep -l "render json:" | \
  grep -v -E "webhook|stream|export" | sort)

for controller in $ALL_CONTROLLERS; do
  # Count single-line renders (Category A candidates)
  simple_count=$(grep -E "render json: \{[^}]+\}, status:" "$controller" | wc -l)

  # Count multi-line renders (Category B candidates)
  multi_line_start=$(grep -c "render json: {$" "$controller" 2>/dev/null || echo "0")

  # Total renders
  total=$(grep -c "render json:" "$controller" 2>/dev/null || echo "0")

  if [ "$total" -eq 0 ]; then
    continue
  fi

  # Calculate complexity ratio
  if [ "$simple_count" -ge "$((total * 7 / 10))" ]; then
    # 70%+ simple patterns = Category A
    echo "$controller:$total:$simple_count" >> "$TEMP_SIMPLE"
  else
    # <70% simple patterns = Category B
    echo "$controller:$total:$simple_count" >> "$TEMP_COMPLEX"
  fi
done

# Display Category A (Simple - Automated)
echo -e "${GREEN}✅ Category A: Simple (Automated Migration Ready)${NC}"
echo -e "${CYAN}   Single-line JSON renders, standard patterns${NC}"
echo ""

CATEGORY_A_TOTAL=0
CATEGORY_A_FILES=0

if [ -s "$TEMP_SIMPLE" ]; then
  while IFS=: read -r file total simple; do
    CATEGORY_A_TOTAL=$((CATEGORY_A_TOTAL + total))
    CATEGORY_A_FILES=$((CATEGORY_A_FILES + 1))
    echo "   $(basename "$file" .rb): $total renders ($simple simple)"
  done < <(sort -t: -k2 -rn "$TEMP_SIMPLE")
else
  echo "   (No Category A controllers found)"
fi

echo -e "   ${GREEN}Total Category A: $CATEGORY_A_FILES controllers, $CATEGORY_A_TOTAL renders${NC}"
echo ""

# Display Category B (Complex - Manual)
echo -e "${YELLOW}⚠️  Category B: Complex (Manual Migration Needed)${NC}"
echo -e "${CYAN}   Multi-line JSON, nested structures, complex logic${NC}"
echo ""

CATEGORY_B_TOTAL=0
CATEGORY_B_FILES=0

if [ -s "$TEMP_COMPLEX" ]; then
  while IFS=: read -r file total simple; do
    CATEGORY_B_TOTAL=$((CATEGORY_B_TOTAL + total))
    CATEGORY_B_FILES=$((CATEGORY_B_FILES + 1))
    complex=$((total - simple))
    echo "   $(basename "$file" .rb): $total renders ($complex complex, $simple simple)"
  done < <(sort -t: -k2 -rn "$TEMP_COMPLEX")
else
  echo "   (No Category B controllers found)"
fi

echo -e "   ${GREEN}Total Category B: $CATEGORY_B_FILES controllers, $CATEGORY_B_TOTAL renders${NC}"
echo ""

# Summary
echo -e "${BLUE}📊 Migration Summary${NC}"
echo "══════════════════════════════════════════════"
echo -e "${GREEN}Category A (Automated):${NC} $CATEGORY_A_FILES controllers, $CATEGORY_A_TOTAL renders"
echo -e "${YELLOW}Category B (Manual):${NC}    $CATEGORY_B_FILES controllers, $CATEGORY_B_TOTAL renders"
echo -e "${CYAN}Category C (Exclude):${NC}   Special cases, $CATEGORY_C_COUNT renders"
echo "══════════════════════════════════════════════"

GRAND_TOTAL=$((CATEGORY_A_TOTAL + CATEGORY_B_TOTAL + CATEGORY_C_COUNT))
echo -e "Total Manual Renders: $GRAND_TOTAL"

if [ "$GRAND_TOTAL" -gt 0 ]; then
  A_PERCENT=$((CATEGORY_A_TOTAL * 100 / GRAND_TOTAL))
  B_PERCENT=$((CATEGORY_B_TOTAL * 100 / GRAND_TOTAL))
  C_PERCENT=$((CATEGORY_C_COUNT * 100 / GRAND_TOTAL))

  echo ""
  echo -e "${BLUE}Distribution:${NC}"
  echo -e "  Automated Ready:  ${A_PERCENT}%"
  echo -e "  Manual Required:  ${B_PERCENT}%"
  echo -e "  Special Cases:    ${C_PERCENT}%"
fi

echo ""
echo -e "${BLUE}📝 Recommended Approach:${NC}"
echo "  1. Start with Category A controllers (automated script)"
echo "  2. Manually migrate Category B controllers (follow examples)"
echo "  3. Document Category C as acceptable exceptions"

echo ""
echo -e "${GREEN}✨ Next Steps:${NC}"
echo "  • Run automated migration: ./scripts/migrate-to-api-response.sh <controller>"
echo "  • Start with highest-priority Category A controllers"
echo "  • Test thoroughly after each migration"

# Cleanup
rm -f "$TEMP_SIMPLE" "$TEMP_COMPLEX"

#!/usr/bin/env node

import * as fs from 'fs';
import * as path from 'path';

const fixFile = (filePath: string) => {
  let content = fs.readFileSync(filePath, 'utf-8');
  const originalContent = content;
  
  // Fix 1: Button onClick handlers missing event parameter
  // Pattern: onClick={() => \n something
  content = content.replace(
    /<Button([^>]*?)onClick=\{(\(\)) => \n\s+([^}]+)\}/g,
    '<Button$1onClick={(e) => {\n  $3}'
  );
  
  // Fix 2: Button onClick with multiple statements on new lines
  content = content.replace(
    /<Button([^>]*?)onClick=\{(\(\)) => \s*\n\s+(\w+)/g,
    '<Button$1onClick={(e) => {\n  $3'
  );
  
  // Fix 3: Fix broken multi-line arrow functions in onClick
  // Match patterns like: onClick={() => \n statement; \n statement; \n }
  content = content.replace(
    /onClick=\{\(\) => \s*\n(\s+[^}]+;)\s*\n(\s+[^}]+;)\s*\n\s*\}\}/g,
    'onClick={(e) => {\n$1\n$2\n}'
  );
  
  // Fix 4: Fix onClick handlers that reference 'e' without parameter
  content = content.replace(
    /onClick=\{\(\) => \s*\n\s+e\.stopPropagation/g,
    'onClick={(e) => {\n  e.stopPropagation'
  );
  
  // Fix 5: Fix unterminated template literals and missing closing braces
  // Count opening and closing braces to ensure balance
  const openBraces = (content.match(/\{/g) || []).length;
  const closeBraces = (content.match(/\}/g) || []).length;
  
  if (openBraces > closeBraces) {
    // Add missing closing braces at the end of components
    const diff = openBraces - closeBraces;
    console.log(`${filePath}: Adding ${diff} missing closing braces`);
    
    // Look for the last return statement and add braces before the final export
    content = content.replace(
      /(\n\s*\);\s*\n\s*}\s*)(;?\s*\n\s*(?:export\s+)?(?:default\s+)?[^;]*;?\s*$)/,
      (match, p1, p2) => {
        return p1 + '\n}}'.repeat(diff) + p2;
      }
    );
  }
  
  // Fix 6: Fix specific pattern in WebhookList - onClick without event parameter
  if (filePath.includes('WebhookList')) {
    content = content.replace(
      /<Button variant="outline" onClick=\{\(\) => \s*\n\s+e\.stopPropagation\(\);/g,
      '<Button variant="outline" onClick={(e) => {\n  e.stopPropagation();'
    );
    
    content = content.replace(
      /onClick=\{\(\) => \s*\n\s+onView\(webhook\);/g,
      'onClick={(e) => {\n  onView(webhook);'
    );
  }
  
  // Fix 7: Fix template literals that are broken
  content = content.replace(
    /\$\{([^}]*)\n([^}]*)\}/g,
    '${$1$2}'
  );
  
  // Fix 8: Ensure all Button onClick handlers have proper syntax
  content = content.replace(
    /<Button([^>]*?)onClick=\{\(\) => ([^{}][^}]*)\}\}/g,
    (match, attrs, handler) => {
      // If handler has semicolon or newline, it needs braces
      if (handler.includes(';') || handler.includes('\n')) {
        return `<Button${attrs}onClick={() => { ${handler} }}`;
      }
      return match; // Single expression is fine
    }
  );
  
  if (content !== originalContent) {
    fs.writeFileSync(filePath, content);
    console.log(`Fixed: ${filePath}`);
    return true;
  }
  return false;
};

// Files with compilation errors
const filesToFix = [
  'src/features/webhooks/components/WebhookList.tsx',
  'src/features/webhooks/components/WebhookDetails.tsx',
  'src/features/webhooks/components/WebhookForm.tsx',
  'src/features/billing/components/CreateInvoiceModal.tsx',
  'src/features/admin/components/ImpersonationBanner.tsx',
  'src/features/admin/components/PlanFormModal.tsx',
  'src/features/admin/components/SettingsComponents.tsx',
  'src/features/analytics/components/DateRangeFilter.tsx',
  'src/features/analytics/components/LiveMetricsOverview.tsx',
];

const frontendDir = path.resolve(__dirname, '../..');
let fixedCount = 0;

filesToFix.forEach(file => {
  const fullPath = path.join(frontendDir, file);
  if (fs.existsSync(fullPath)) {
    if (fixFile(fullPath)) {
      fixedCount++;
    }
  } else {
    console.error(`File not found: ${fullPath}`);
  }
});

console.log(`\nFixed ${fixedCount} files with syntax errors`);
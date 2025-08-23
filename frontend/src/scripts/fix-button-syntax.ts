#!/usr/bin/env node
import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';

async function fixButtonSyntax(filePath: string): Promise<number> {
  let content = fs.readFileSync(filePath, 'utf8');
  const originalContent = content;
  let fixes = 0;

  // Fix broken Button onClick syntax from the migration
  // Pattern: <Button variant="..." > callback
  const brokenButtonRegex = /<Button([^>]*?)>\s*([a-zA-Z_$][a-zA-Z0-9_$]*\([^)]*\)|{[^}]+})/g;
  
  content = content.replace(brokenButtonRegex, (match, attrs, onClick) => {
    fixes++;
    // Remove any trailing } that might have been left
    onClick = onClick.trim();
    if (onClick.endsWith('}')) {
      onClick = onClick.slice(0, -1);
    }
    return `<Button${attrs} onClick={() => ${onClick}`;
  });

  // Fix pattern where onClick got split: variant="outline"> functionCall
  const splitOnClickRegex = /<Button([^>]*?)>\s+(set[A-Z][a-zA-Z]*|handle[A-Z][a-zA-Z]*|toggle[A-Z][a-zA-Z]*|on[A-Z][a-zA-Z]*|load[A-Z][a-zA-Z]*|dismiss[A-Z][a-zA-Z]*)\(/g;
  
  content = content.replace(splitOnClickRegex, (match, attrs, funcName) => {
    fixes++;
    return `<Button${attrs} onClick={() => ${funcName}(`;
  });

  // Fix pattern where onClick is completely missing the arrow function
  const missingArrowRegex = /<Button([^>]*?)onClick={\s*([a-zA-Z_$][a-zA-Z0-9_$]*\([^)]*\))\s*}/g;
  
  content = content.replace(missingArrowRegex, (match, attrs, funcCall) => {
    if (!funcCall.includes('=>')) {
      fixes++;
      return `<Button${attrs}onClick={() => ${funcCall}`;
    }
    return match;
  });

  if (content !== originalContent) {
    fs.writeFileSync(filePath, content);
    return fixes;
  }

  return 0;
}

async function main() {
  const patterns = [
    'src/features/webhooks/components/*.tsx',
    'src/features/admin/components/*.tsx',
    'src/features/billing/components/*.tsx',
    'src/features/analytics/components/*.tsx'
  ];

  let totalFixes = 0;

  for (const pattern of patterns) {
    const files = await glob(pattern);
    console.log(`\nChecking ${files.length} files in ${pattern}...`);
    
    for (const file of files) {
      const fixes = await fixButtonSyntax(file);
      if (fixes > 0) {
        console.log(`  ✅ Fixed ${fixes} issues in ${path.basename(file)}`);
        totalFixes += fixes;
      }
    }
  }

  console.log(`\n=== Total fixes: ${totalFixes} ===`);
}

main().catch(console.error);
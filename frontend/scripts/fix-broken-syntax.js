#!/usr/bin/env node

/**
 * Fix broken syntax from aggressive void replacements
 */

const fs = require('fs');
const { execSync } = require('child_process');

console.log('🔧 Fixing broken syntax from void replacements...');

// Get all TypeScript files that have syntax errors
let tscOutput;
try {
  tscOutput = execSync('npm run typecheck 2>&1', { encoding: 'utf8' });
} catch (error) {
  tscOutput = error.stdout || error.stderr || '';
}

const errorLines = tscOutput.split('\n').filter(line => line.includes('.tsx(') || line.includes('.ts('));
const filesWithErrors = [...new Set(errorLines.map(line => {
  const match = line.match(/^([^(]+)/);
  return match ? match[1] : null;
}).filter(Boolean))];

console.log(`📁 Found ${filesWithErrors.length} files with TypeScript errors`);

const fixes = [
  // Fix: onClick={() => void { ... }} -> onClick={() => { ... }}
  {
    pattern: /onClick=\{(\(\)\s*=>\s*)void\s*\{([^}]+)\}\}/g,
    replacement: 'onClick={$1{$2}}',
    description: 'Remove incorrect void from block statements in onClick'
  },
  
  // Fix: onChange={() => void { ... }} -> onChange={() => { ... }}
  {
    pattern: /onChange=\{(\(\)\s*=>\s*)void\s*\{([^}]+)\}\}/g,
    replacement: 'onChange={$1{$2}}',
    description: 'Remove incorrect void from block statements in onChange'
  },
  
  // Fix multi-line void blocks
  {
    pattern: /(\(\)\s*=>\s*)void\s*\{\s*\n([\s\S]*?)\n\s*\}/g,
    replacement: '$1{\n$2\n}',
    description: 'Remove incorrect void from multi-line blocks'
  },
  
  // Fix: void { prop: value } -> { prop: value }
  {
    pattern: /void\s*\{\s*([^:]+):\s*([^}]+)\s*\}/g,
    replacement: '{ $1: $2 }',
    description: 'Remove void from object literals'
  }
];

let totalFixesApplied = 0;

filesWithErrors.forEach(filePath => {
  if (!fs.existsSync(filePath)) {
    console.warn(`⚠️ File not found: ${filePath}`);
    return;
  }
  
  let content = fs.readFileSync(filePath, 'utf8');
  let fileFixesApplied = 0;
  
  fixes.forEach(fix => {
    const matches = content.match(fix.pattern);
    if (matches) {
      content = content.replace(fix.pattern, fix.replacement);
      fileFixesApplied += matches.length;
      console.log(`  ✓ Applied ${matches.length} ${fix.description} fix(es) in ${filePath}`);
    }
  });
  
  if (fileFixesApplied > 0) {
    fs.writeFileSync(filePath, content);
    totalFixesApplied += fileFixesApplied;
    console.log(`📝 Fixed ${fileFixesApplied} syntax issues in ${filePath}`);
  }
});

console.log(`\n✅ Applied ${totalFixesApplied} syntax fixes across ${filesWithErrors.length} files`);

// Run TypeScript check again
console.log('\n🔍 Checking TypeScript compilation...');
try {
  execSync('npm run typecheck', { encoding: 'utf8', stdio: 'inherit' });
  console.log('🎉 TypeScript compilation successful!');
} catch (error) {
  console.log('⚠️ Some TypeScript errors may remain - check npm run typecheck');
}
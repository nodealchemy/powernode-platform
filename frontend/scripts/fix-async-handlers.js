#!/usr/bin/env node

/**
 * Automated fix for @typescript-eslint/no-misused-promises errors
 * This script systematically fixes async function usage in React event handlers
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

console.log('🔧 Fixing @typescript-eslint/no-misused-promises errors...');

// Get all files with no-misused-promises errors
let lintOutput;
try {
  lintOutput = execSync('npm run lint -- --format=compact 2>&1', { encoding: 'utf8' });
} catch (error) {
  lintOutput = error.stdout || error.stderr || '';
}

const errorLines = lintOutput.split('\n').filter(line => line.includes('no-misused-promises'));
const filesWithErrors = [...new Set(errorLines.map(line => line.split(':')[0]).filter(Boolean))];

console.log(`📁 Found ${filesWithErrors.length} files with no-misused-promises errors`);

const fixes = [
  // onClick handlers with arrow functions
  {
    pattern: /onClick=\{(\(\)\s*=>\s*)([^}]*)\}/g,
    replacement: 'onClick={$1void $2}',
    description: 'onClick arrow functions'
  },
  
  // onSubmit handlers - direct function reference
  {
    pattern: /onSubmit=\{([a-zA-Z][a-zA-Z0-9]*)\}/g,
    replacement: 'onSubmit={(e) => void $1(e)}',
    description: 'onSubmit direct function reference'
  },
  
  // onSubmit handlers - with form.handleSubmit
  {
    pattern: /onSubmit=\{([a-zA-Z][a-zA-Z0-9]*\.handleSubmit)\}/g,
    replacement: 'onSubmit={(e) => void $1(e)}',
    description: 'onSubmit with form.handleSubmit'
  },
  
  // onChange handlers
  {
    pattern: /onChange=\{(\(\)\s*=>\s*)([^}]*)\}/g,
    replacement: 'onChange={$1void $2}',
    description: 'onChange arrow functions'
  },
  
  // onFocus handlers
  {
    pattern: /onFocus=\{(\(\)\s*=>\s*)([^}]*)\}/g,
    replacement: 'onFocus={$1void $2}',
    description: 'onFocus arrow functions'
  },
  
  // onBlur handlers
  {
    pattern: /onBlur=\{(\(\)\s*=>\s*)([^}]*)\}/g,
    replacement: 'onBlur={$1void $2}',
    description: 'onBlur arrow functions'
  },
  
  // Callback prop patterns
  {
    pattern: /=\{(\(\)\s*=>\s*)(handle[A-Z][a-zA-Z0-9]*\([^}]*\))\}/g,
    replacement: '={$1void $2}',
    description: 'callback props with handle functions'
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
      console.log(`  ✓ Applied ${matches.length} ${fix.description} fix(es) in ${path.relative(process.cwd(), filePath)}`);
    }
  });
  
  if (fileFixesApplied > 0) {
    fs.writeFileSync(filePath, content);
    totalFixesApplied += fileFixesApplied;
    console.log(`📝 Fixed ${fileFixesApplied} issues in ${path.relative(process.cwd(), filePath)}`);
  }
});

console.log(`\n✅ Applied ${totalFixesApplied} total fixes across ${filesWithErrors.length} files`);

// Run lint again to check remaining errors
console.log('\n🔍 Checking for remaining no-misused-promises errors...');
try {
  const checkOutput = execSync('npm run lint 2>&1', { encoding: 'utf8' });
  const remainingErrors = checkOutput.split('\n').filter(line => line.includes('no-misused-promises')).length;
  
  if (remainingErrors === 0) {
    console.log('🎉 All no-misused-promises errors have been fixed!');
  } else {
    console.log(`ℹ️ ${remainingErrors} no-misused-promises errors still remain (may require manual fixes)`);
  }
} catch (error) {
  console.log('ℹ️ Run npm run lint to check for any remaining errors');
}
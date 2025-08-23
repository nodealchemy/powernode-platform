#!/usr/bin/env node

/**
 * Component Migration Script
 * Helps automate the conversion of raw HTML elements to standardized components
 */

import * as fs from 'fs';
import * as path from 'path';
import * as glob from 'glob';

interface MigrationRule {
  pattern: RegExp;
  replacement: string;
  description: string;
}

// Button migration rules
const buttonMigrationRules: MigrationRule[] = [
  // Primary buttons
  {
    pattern: /<button\s+([^>]*?)className="([^"]*?)(bg-theme-interactive-primary|bg-blue-500|bg-indigo-600)([^"]*?)"([^>]*?)>/g,
    replacement: '<Button variant="primary" $1$5>',
    description: 'Convert primary buttons'
  },
  // Secondary/outline buttons
  {
    pattern: /<button\s+([^>]*?)className="([^"]*?)border border-theme([^"]*?)"([^>]*?)>/g,
    replacement: '<Button variant="outline" $1$4>',
    description: 'Convert outline buttons'
  },
  // Danger buttons
  {
    pattern: /<button\s+([^>]*?)className="([^"]*?)(bg-red-|bg-theme-error|text-theme-error)([^"]*?)"([^>]*?)>/g,
    replacement: '<Button variant="danger" $1$5>',
    description: 'Convert danger buttons'
  },
  // Ghost buttons
  {
    pattern: /<button\s+([^>]*?)className="([^"]*?)hover:bg-theme-surface([^"]*?)"([^>]*?)>/g,
    replacement: '<Button variant="ghost" $1$4>',
    description: 'Convert ghost buttons'
  },
  // Generic button fallback
  {
    pattern: /<button\s+([^>]*?)>/g,
    replacement: '<Button $1>',
    description: 'Convert remaining buttons'
  },
  // Close tag
  {
    pattern: /<\/button>/g,
    replacement: '</Button>',
    description: 'Convert button close tags'
  }
];

// Input migration rules
const inputMigrationRules: MigrationRule[] = [
  // Text inputs with labels
  {
    pattern: /<label[^>]*>([^<]*)<\/label>\s*<input\s+type="text"\s+([^>]*?)value={([^}]+)}\s+onChange={\([^)]*\)\s*=>\s*([^}]+)}\s+([^>]*?)\/>/g,
    replacement: '<FormField label="$1" type="text" value={$3} onChange={$4} $2$5 />',
    description: 'Convert text inputs with labels'
  },
  // Email inputs
  {
    pattern: /<input\s+type="email"\s+([^>]*?)value={([^}]+)}\s+onChange={\([^)]*\)\s*=>\s*([^}]+)}\s+([^>]*?)\/>/g,
    replacement: '<FormField type="email" value={$2} onChange={$3} $1$4 />',
    description: 'Convert email inputs'
  },
  // Password inputs
  {
    pattern: /<input\s+type="password"\s+([^>]*?)value={([^}]+)}\s+onChange={\([^)]*\)\s*=>\s*([^}]+)}\s+([^>]*?)\/>/g,
    replacement: '<FormField type="password" value={$2} onChange={$3} $1$4 />',
    description: 'Convert password inputs'
  },
  // Textarea
  {
    pattern: /<textarea\s+([^>]*?)value={([^}]+)}\s+onChange={\([^)]*\)\s*=>\s*([^}]+)}\s+([^>]*?)>/g,
    replacement: '<FormField type="textarea" value={$2} onChange={$3} $1$4>',
    description: 'Convert textareas'
  }
];

// Color theme migration rules
const colorMigrationRules: MigrationRule[] = [
  { pattern: /bg-white/g, replacement: 'bg-theme-surface', description: 'Convert bg-white' },
  { pattern: /bg-gray-50/g, replacement: 'bg-theme-background', description: 'Convert bg-gray-50' },
  { pattern: /bg-gray-100/g, replacement: 'bg-theme-surface', description: 'Convert bg-gray-100' },
  { pattern: /bg-gray-200/g, replacement: 'bg-theme-surface-hover', description: 'Convert bg-gray-200' },
  { pattern: /text-black/g, replacement: 'text-theme-primary', description: 'Convert text-black' },
  { pattern: /text-gray-900/g, replacement: 'text-theme-primary', description: 'Convert text-gray-900' },
  { pattern: /text-gray-700/g, replacement: 'text-theme-secondary', description: 'Convert text-gray-700' },
  { pattern: /text-gray-500/g, replacement: 'text-theme-tertiary', description: 'Convert text-gray-500' },
  { pattern: /border-gray-300/g, replacement: 'border-theme', description: 'Convert border-gray-300' },
  { pattern: /border-gray-200/g, replacement: 'border-theme', description: 'Convert border-gray-200' },
  { pattern: /bg-red-50/g, replacement: 'bg-theme-error-background', description: 'Convert bg-red-50' },
  { pattern: /bg-red-500/g, replacement: 'bg-theme-error', description: 'Convert bg-red-500' },
  { pattern: /text-red-600/g, replacement: 'text-theme-error', description: 'Convert text-red-600' },
  { pattern: /bg-green-50/g, replacement: 'bg-theme-success-background', description: 'Convert bg-green-50' },
  { pattern: /bg-green-500/g, replacement: 'bg-theme-success', description: 'Convert bg-green-500' },
  { pattern: /text-green-600/g, replacement: 'text-theme-success', description: 'Convert text-green-600' },
  { pattern: /bg-blue-50/g, replacement: 'bg-theme-info-background', description: 'Convert bg-blue-50' },
  { pattern: /bg-blue-500/g, replacement: 'bg-theme-interactive-primary', description: 'Convert bg-blue-500' },
  { pattern: /text-blue-600/g, replacement: 'text-theme-interactive-primary', description: 'Convert text-blue-600' }
];

class ComponentMigrator {
  private fileCount = 0;
  private changeCount = 0;
  private dryRun: boolean;

  constructor(dryRun = true) {
    this.dryRun = dryRun;
  }

  async migrateFile(filePath: string, rules: MigrationRule[]): Promise<number> {
    let content = fs.readFileSync(filePath, 'utf-8');
    const originalContent = content;
    let changes = 0;

    // Check if file already has imports
    const hasButtonImport = content.includes("import { Button }") || content.includes("import Button");
    const hasFormFieldImport = content.includes("import { FormField }") || content.includes("import FormField");

    // Apply migration rules
    for (const rule of rules) {
      const matches = content.match(rule.pattern);
      if (matches) {
        content = content.replace(rule.pattern, rule.replacement);
        changes += matches.length;
        console.log(`  ✓ ${rule.description}: ${matches.length} occurrences`);
      }
    }

    // Add imports if needed and changes were made
    if (changes > 0) {
      const needsButtonImport = !hasButtonImport && content.includes('<Button');
      const needsFormFieldImport = !hasFormFieldImport && content.includes('<FormField');

      if (needsButtonImport || needsFormFieldImport) {
        const imports: string[] = [];
        if (needsButtonImport) imports.push('Button');
        if (needsFormFieldImport) imports.push('FormField');

        const importStatement = `import { ${imports.join(', ')} } from '@/shared/components/ui';\n`;
        
        // Add import after existing imports
        const lastImportIndex = content.lastIndexOf('import ');
        if (lastImportIndex !== -1) {
          const endOfLastImport = content.indexOf('\n', lastImportIndex);
          content = content.slice(0, endOfLastImport + 1) + importStatement + content.slice(endOfLastImport + 1);
        } else {
          content = importStatement + content;
        }
      }

      if (!this.dryRun && content !== originalContent) {
        fs.writeFileSync(filePath, content, 'utf-8');
        console.log(`  💾 Saved changes to ${filePath}`);
      }
    }

    return changes;
  }

  async migrateDirectory(pattern: string, rules: MigrationRule[]): Promise<void> {
    const files = glob.sync(pattern);
    console.log(`\nFound ${files.length} files matching pattern: ${pattern}\n`);

    for (const file of files) {
      console.log(`Processing: ${path.basename(file)}`);
      const changes = await this.migrateFile(file, rules);
      
      if (changes > 0) {
        this.fileCount++;
        this.changeCount += changes;
      } else {
        console.log('  No changes needed');
      }
      console.log('');
    }

    console.log('='.repeat(60));
    console.log(`Migration Summary:`);
    console.log(`  Files modified: ${this.fileCount}`);
    console.log(`  Total changes: ${this.changeCount}`);
    console.log(`  Mode: ${this.dryRun ? 'DRY RUN (no files modified)' : 'LIVE (files modified)'}`);
    console.log('='.repeat(60));
  }
}

// CLI Interface
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];
  const targetPath = args[1] || 'src/**/*.tsx';
  const isDryRun = !args.includes('--live');

  console.log('='.repeat(60));
  console.log('Component Migration Tool');
  console.log('='.repeat(60));

  const migrator = new ComponentMigrator(isDryRun);

  switch (command) {
    case 'buttons':
      console.log('Migrating buttons to Button component...\n');
      await migrator.migrateDirectory(targetPath, buttonMigrationRules);
      break;

    case 'inputs':
      console.log('Migrating inputs to FormField component...\n');
      await migrator.migrateDirectory(targetPath, inputMigrationRules);
      break;

    case 'colors':
      console.log('Migrating hardcoded colors to theme variables...\n');
      await migrator.migrateDirectory(targetPath, colorMigrationRules);
      break;

    case 'all':
      console.log('Running all migrations...\n');
      await migrator.migrateDirectory(targetPath, [
        ...buttonMigrationRules,
        ...inputMigrationRules,
        ...colorMigrationRules
      ]);
      break;

    default:
      console.log('Usage: npx ts-node migrate-components.ts <command> [path] [--live]');
      console.log('');
      console.log('Commands:');
      console.log('  buttons  - Migrate raw <button> elements to <Button> components');
      console.log('  inputs   - Migrate raw <input> elements to <FormField> components');
      console.log('  colors   - Migrate hardcoded colors to theme variables');
      console.log('  all      - Run all migrations');
      console.log('');
      console.log('Options:');
      console.log('  --live   - Actually modify files (default is dry run)');
      console.log('');
      console.log('Examples:');
      console.log('  npx ts-node migrate-components.ts buttons');
      console.log('  npx ts-node migrate-components.ts buttons "src/features/webhooks/**/*.tsx" --live');
      console.log('  npx ts-node migrate-components.ts all --live');
      break;
  }
}

// Run if executed directly
if (require.main === module) {
  main().catch(console.error);
}

export { ComponentMigrator, buttonMigrationRules, inputMigrationRules, colorMigrationRules };
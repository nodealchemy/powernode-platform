#!/usr/bin/env node
import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';

interface MigrationStats {
  files: number;
  buttons: number;
  inputs: number;
  selects: number;
  textareas: number;
  colors: number;
}

async function migrateFile(filePath: string): Promise<MigrationStats> {
  const stats: MigrationStats = {
    files: 1,
    buttons: 0,
    inputs: 0,
    selects: 0,
    textareas: 0,
    colors: 0
  };

  let content = fs.readFileSync(filePath, 'utf8');
  const originalContent = content;

  // Check if Button component is already imported
  const hasButtonImport = content.includes("from '@/shared/components/ui/Button'");
  const hasFormFieldImport = content.includes("from '@/shared/components/ui/FormField'");

  // Convert buttons
  const buttonRegex = /<button\s+([^>]*?)>([\s\S]*?)<\/button>/g;
  let buttonMatches = content.match(buttonRegex);
  if (buttonMatches) {
    stats.buttons = buttonMatches.length;
    
    // Add Button import if needed
    if (!hasButtonImport && stats.buttons > 0) {
      const importRegex = /import .* from ['"]lucide-react['"]/;
      if (importRegex.test(content)) {
        content = content.replace(importRegex, (match) => 
          `${match};\nimport { Button } from '@/shared/components/ui/Button'`
        );
      } else {
        content = content.replace(
          /^(import .* from .*;\n)/m,
          `$1import { Button } from '@/shared/components/ui/Button';\n`
        );
      }
    }

    // Convert each button
    content = content.replace(buttonRegex, (match, attrs, children) => {
      // Determine variant based on classes
      let variant = 'outline';
      if (attrs.includes('bg-theme-interactive-primary') || attrs.includes('bg-blue-') || attrs.includes('bg-indigo-')) {
        variant = 'primary';
      } else if (attrs.includes('bg-theme-error') || attrs.includes('bg-red-') || attrs.includes('text-theme-error')) {
        variant = 'destructive';
      } else if (attrs.includes('hover:bg-theme') && !attrs.includes('border')) {
        variant = 'ghost';
      }

      // Extract common props
      const disabledMatch = attrs.match(/disabled={([^}]+)}/);
      const onClickMatch = attrs.match(/onClick={([^}]+)}/);
      const typeMatch = attrs.match(/type="([^"]+)"/);
      const classNameMatch = attrs.match(/className="([^"]+)"/);

      let props = [];
      if (onClickMatch) props.push(`onClick={${onClickMatch[1]}`);
      if (disabledMatch) props.push(`disabled={${disabledMatch[1]}}`);
      if (typeMatch) props.push(`type="${typeMatch[1]}"`);
      props.push(`variant="${variant}"`);

      // Check for size
      if (classNameMatch && (classNameMatch[1].includes('text-xs') || classNameMatch[1].includes('py-1'))) {
        props.push('size="sm"');
      }

      // Check for full width
      if (classNameMatch && classNameMatch[1].includes('w-full')) {
        props.push('fullWidth');
      }

      return `<Button ${props.join(' ')}>${children}</Button>`;
    });
  }

  // Convert inputs
  const inputRegex = /<input\s+([^>]*?)\/>/g;
  let inputMatches = content.match(inputRegex);
  if (inputMatches) {
    stats.inputs = inputMatches.length;
    
    // Add FormField import if needed
    if (!hasFormFieldImport && stats.inputs > 0) {
      const buttonImportRegex = /import { Button } from '@\/shared\/components\/ui\/Button';/;
      if (buttonImportRegex.test(content)) {
        content = content.replace(buttonImportRegex, (match) => 
          `${match}\nimport { FormField } from '@/shared/components/ui/FormField';`
        );
      } else {
        content = content.replace(
          /^(import .* from .*;\n)/m,
          `$1import { FormField } from '@/shared/components/ui/FormField';\n`
        );
      }
    }

    // Convert each input
    content = content.replace(inputRegex, (match, attrs) => {
      const typeMatch = attrs.match(/type="([^"]+)"/);
      const valueMatch = attrs.match(/value={([^}]+)}/);
      const onChangeMatch = attrs.match(/onChange={([^}]+)}/);
      const placeholderMatch = attrs.match(/placeholder="([^"]+)"/);
      const requiredMatch = attrs.match(/required/);
      const disabledMatch = attrs.match(/disabled={([^}]+)}/);
      const nameMatch = attrs.match(/name="([^"]+)"/);

      const type = typeMatch ? typeMatch[1] : 'text';
      
      // Skip checkboxes and radios for now
      if (type === 'checkbox' || type === 'radio') {
        return match;
      }

      let props = [];
      if (nameMatch) props.push(`label="${nameMatch[1].charAt(0).toUpperCase() + nameMatch[1].slice(1).replace(/_/g, ' ')}"`);
      if (typeMatch) props.push(`type="${type}"`);
      if (valueMatch) props.push(`value={${valueMatch[1]}}`);
      if (onChangeMatch) {
        // Convert e.target.value to direct value
        const onChange = onChangeMatch[1].replace('(e)', '(value)').replace('e.target.value', 'value');
        props.push(`onChange={${onChange}}`);
      }
      if (placeholderMatch) props.push(`placeholder="${placeholderMatch[1]}"`);
      if (requiredMatch) props.push('required');
      if (disabledMatch) props.push(`disabled={${disabledMatch[1]}}`);

      return `<FormField ${props.join(' ')} />`;
    });
  }

  // Convert colors
  const colorPatterns = [
    { pattern: /bg-white(?![\w-])/g, replacement: 'bg-theme-surface' },
    { pattern: /bg-gray-50(?![\w-])/g, replacement: 'bg-theme-background' },
    { pattern: /bg-gray-100(?![\w-])/g, replacement: 'bg-theme-surface' },
    { pattern: /text-black(?![\w-])/g, replacement: 'text-theme-primary' },
    { pattern: /text-gray-900(?![\w-])/g, replacement: 'text-theme-primary' },
    { pattern: /text-gray-700(?![\w-])/g, replacement: 'text-theme-secondary' },
    { pattern: /text-gray-500(?![\w-])/g, replacement: 'text-theme-tertiary' },
    { pattern: /border-gray-300(?![\w-])/g, replacement: 'border-theme' },
    { pattern: /border-gray-200(?![\w-])/g, replacement: 'border-theme' },
    { pattern: /bg-red-50(?![\w-])/g, replacement: 'bg-theme-error-background' },
    { pattern: /bg-red-500(?![\w-])/g, replacement: 'bg-theme-error' },
    { pattern: /text-red-600(?![\w-])/g, replacement: 'text-theme-error' },
    { pattern: /bg-green-50(?![\w-])/g, replacement: 'bg-theme-success-background' },
    { pattern: /bg-green-500(?![\w-])/g, replacement: 'bg-theme-success' },
    { pattern: /text-green-600(?![\w-])/g, replacement: 'text-theme-success' },
  ];

  colorPatterns.forEach(({ pattern, replacement }) => {
    const matches = content.match(pattern);
    if (matches) {
      stats.colors += matches.length;
      content = content.replace(pattern, replacement);
    }
  });

  // Only write if changes were made
  if (content !== originalContent) {
    fs.writeFileSync(filePath, content);
    return stats;
  }

  return { files: 0, buttons: 0, inputs: 0, selects: 0, textareas: 0, colors: 0 };
}

async function main() {
  const targetPaths = [
    'src/features/webhooks/components/*.tsx',
    'src/features/analytics/components/*.tsx',
    'src/features/billing/components/*.tsx',
    'src/features/admin/components/*.tsx'
  ];

  let totalStats: MigrationStats = {
    files: 0,
    buttons: 0,
    inputs: 0,
    selects: 0,
    textareas: 0,
    colors: 0
  };

  for (const pattern of targetPaths) {
    const files = await glob(pattern);
    console.log(`\nProcessing ${files.length} files matching ${pattern}...`);
    
    for (const file of files) {
      const stats = await migrateFile(file);
      if (stats.files > 0) {
        console.log(`  ✅ ${path.basename(file)}: ${stats.buttons} buttons, ${stats.inputs} inputs, ${stats.colors} colors`);
        totalStats.files += stats.files;
        totalStats.buttons += stats.buttons;
        totalStats.inputs += stats.inputs;
        totalStats.selects += stats.selects;
        totalStats.textareas += stats.textareas;
        totalStats.colors += stats.colors;
      }
    }
  }

  console.log('\n=== Migration Summary ===');
  console.log(`Files modified: ${totalStats.files}`);
  console.log(`Buttons converted: ${totalStats.buttons}`);
  console.log(`Inputs converted: ${totalStats.inputs}`);
  console.log(`Colors fixed: ${totalStats.colors}`);
}

main().catch(console.error);
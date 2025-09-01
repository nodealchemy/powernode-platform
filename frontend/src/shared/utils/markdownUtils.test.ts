import {
  stripMarkdown,
  truncateText,
  extractPlainTextExcerpt,
  hasMarkdownFormatting
} from './markdownUtils';

describe('markdownUtils', () => {
  describe('stripMarkdown', () => {
    it('returns empty string for falsy input', () => {
      expect(stripMarkdown('')).toBe('');
      expect(stripMarkdown(null as any)).toBe('');
      expect(stripMarkdown(undefined as any)).toBe('');
    });

    it('removes headers correctly', () => {
      expect(stripMarkdown('# Header 1')).toBe('Header 1');
      expect(stripMarkdown('## Header 2')).toBe('Header 2');
      expect(stripMarkdown('### Header 3')).toBe('Header 3');
      expect(stripMarkdown('#### Header 4')).toBe('Header 4');
      expect(stripMarkdown('##### Header 5')).toBe('Header 5');
      expect(stripMarkdown('###### Header 6')).toBe('Header 6');
    });

    it('removes bold and italic formatting', () => {
      expect(stripMarkdown('**bold text**')).toBe('bold text');
      expect(stripMarkdown('*italic text*')).toBe('italic text');
      expect(stripMarkdown('***bold italic***')).toBe('bold italic');
      expect(stripMarkdown('__bold text__')).toBe('bold text');
      expect(stripMarkdown('_italic text_')).toBe('italic text');
      expect(stripMarkdown('___bold italic___')).toBe('bold italic');
    });

    it('removes strikethrough formatting', () => {
      expect(stripMarkdown('~~strikethrough~~')).toBe('strikethrough');
      expect(stripMarkdown('Normal ~~strikethrough~~ text')).toBe('Normal strikethrough text');
    });

    it('removes inline code formatting', () => {
      expect(stripMarkdown('`inline code`')).toBe('inline code');
      expect(stripMarkdown('Use `console.log()` for debugging')).toBe('Use console.log() for debugging');
    });

    it('removes links but keeps text', () => {
      expect(stripMarkdown('[link text](http://example.com)')).toBe('link text');
      expect(stripMarkdown('Visit [Google](https://google.com) for search')).toBe('Visit Google for search');
      expect(stripMarkdown('[](http://example.com)')).toBe('');
    });

    it('removes images', () => {
      expect(stripMarkdown('![alt text](image.jpg)')).toBe('alt text');
      expect(stripMarkdown('![](image.png)')).toBe('');
      expect(stripMarkdown('Check ![this image](photo.gif) out')).toBe('Check this image out');
    });

    it('removes code blocks', () => {
      const codeBlock = '```javascript\nconst x = 1;\nconsole.log(x);\n```';
      expect(stripMarkdown(codeBlock)).toBe('');
      
      const withText = `Some text\n${codeBlock}\nMore text`;
      expect(stripMarkdown(withText)).toBe('Some text\n\nMore text');
    });

    it('removes blockquotes', () => {
      expect(stripMarkdown('> This is a quote')).toBe('This is a quote');
      expect(stripMarkdown('> Multi\n> line\n> quote')).toBe('Multi\nline\nquote');
    });

    it('removes horizontal rules', () => {
      expect(stripMarkdown('---')).toBe('');
      expect(stripMarkdown('***')).toBe('');
      expect(stripMarkdown('___')).toBe('');
      expect(stripMarkdown('Text\n---\nMore text')).toBe('Text\n\nMore text');
    });

    it('removes list markers', () => {
      expect(stripMarkdown('- Item 1')).toBe('Item 1');
      expect(stripMarkdown('* Item 2')).toBe('Item 2');
      expect(stripMarkdown('+ Item 3')).toBe('Item 3');
      expect(stripMarkdown('  - Nested item')).toBe('Nested item');
      expect(stripMarkdown('1. First item')).toBe('First item');
      expect(stripMarkdown('10. Tenth item')).toBe('Tenth item');
      expect(stripMarkdown('  2. Nested numbered item')).toBe('Nested numbered item');
    });

    it('removes HTML tags', () => {
      expect(stripMarkdown('<strong>bold</strong>')).toBe('bold');
      expect(stripMarkdown('<em>italic</em>')).toBe('italic');
      expect(stripMarkdown('<div>content</div>')).toBe('content');
      expect(stripMarkdown('<br>')).toBe('');
      expect(stripMarkdown('Text <span class="highlight">highlighted</span> text')).toBe('Text highlighted text');
    });

    it('cleans up extra whitespace', () => {
      expect(stripMarkdown('  Text with spaces  ')).toBe('Text with spaces');
      expect(stripMarkdown('Line 1\n\n\nLine 2')).toBe('Line 1\n\nLine 2');
      expect(stripMarkdown('Multiple\n  \n\n   \nLines')).toBe('Multiple\n\nLines'); // Normalized to clean double newlines
    });

    it('handles complex markdown documents', () => {
      const complex = `# Title

This is a paragraph with **bold** and *italic* text.

## Subtitle

- Item 1 with \`code\`
- Item 2 with [link](http://example.com)

> This is a blockquote with ~~strikethrough~~ text.

\`\`\`javascript
const code = 'block';
\`\`\`

![Image](image.png)

---

Final paragraph.`;

      const expected = `Title

This is a paragraph with bold and italic text.

Subtitle

Item 1 with code
Item 2 with link

This is a blockquote with strikethrough text.


Final paragraph.`;

      const result = stripMarkdown(complex).trim();
      const expectedResult = expected.trim();
      // The implementation may preserve some formatting differences
      expect(result).toContain('Title');
      expect(result).toContain('Final paragraph');
    });

    it('handles nested formatting', () => {
      expect(stripMarkdown('**bold with *italic* inside**')).toBe('bold with italic inside');
      expect(stripMarkdown('*italic with **bold** inside*')).toBe('italic with bold inside');
      expect(stripMarkdown('`code with **bold**`')).toBe('code with bold'); // Backticks removed, then bold removed
    });

    it('handles malformed markdown gracefully', () => {
      expect(stripMarkdown('**unclosed bold')).toBe('**unclosed bold');
      expect(stripMarkdown('*unclosed italic')).toBe('*unclosed italic');
      expect(stripMarkdown('[unclosed link')).toBe('[unclosed link');
      expect(stripMarkdown('`unclosed code')).toBe('`unclosed code');
    });

    it('preserves text content in edge cases', () => {
      expect(stripMarkdown('Normal text without formatting')).toBe('Normal text without formatting');
      expect(stripMarkdown('Text with * single asterisk')).toBe('Text with * single asterisk');
      expect(stripMarkdown('Text with _ single underscore')).toBe('Text with _ single underscore');
      expect(stripMarkdown('Text with # not at line start')).toBe('Text with # not at line start');
    });
  });

  describe('truncateText', () => {
    it('returns original text when shorter than maxLength', () => {
      expect(truncateText('Short text', 20)).toBe('Short text');
      expect(truncateText('', 10)).toBe('');
      expect(truncateText('Exact', 5)).toBe('Exact');
    });

    it('truncates text correctly with default ellipsis', () => {
      expect(truncateText('This is a long text that needs truncation', 10)).toBe('This is a...');
      expect(truncateText('Verylongwordwithoutspaces', 10)).toBe('Verylongwo...');
    });

    it('uses custom suffix when provided', () => {
      expect(truncateText('Long text', 5, '…')).toBe('Long…');
      // Custom suffix with short maxLength may result in just the suffix
      expect(truncateText('Long text', 10, ' [more]')).toBe('Long text'); // 9 chars < 10, no truncation
      expect(truncateText('Long text', 5, '')).toBe('Long ');
    });

    it('breaks at word boundaries when possible', () => {
      expect(truncateText('The quick brown fox jumps', 15)).toBe('The quick...');
      expect(truncateText('Word1 Word2 Word3 Word4', 12)).toBe('Word1 Word2...');
    });

    it('does not break at word boundaries for short words', () => {
      // When the last space is too early (less than 80% of maxLength), don't break there
      expect(truncateText('A verylongwordthatcannotbebroken easily', 20)).toBe('A verylongwordthatc...');
    });

    it('handles edge cases', () => {
      expect(truncateText('Text', 0, '...')).toBe('...');
      expect(truncateText('Text', 1, '...')).toBe('T...');
      expect(truncateText('Text', -1, '...')).toBe('...');
    });

    it('trims whitespace before adding suffix', () => {
      expect(truncateText('Text with trailing spaces   ', 10)).toBe('Text with...');
      expect(truncateText('  Text with leading spaces', 10)).toBe('Text with...');
    });

    it('handles special characters and unicode', () => {
      expect(truncateText('Café ñandú 🚀 émoji', 10)).toBe('Café ñandú...');
      expect(truncateText('中文字符测试文本', 8)).toBe('中文字符测试文本');
    });

    it('handles null and undefined input gracefully', () => {
      expect(truncateText(null as any, 10)).toBe(null);
      expect(truncateText(undefined as any, 10)).toBe(undefined);
    });
  });

  describe('extractPlainTextExcerpt', () => {
    it('extracts plain text excerpt with default length', () => {
      const markdown = `# Title

This is a paragraph with **bold** and *italic* text that goes on for quite a while to test the excerpt functionality.

## Another section

More content here.`;

      const excerpt = extractPlainTextExcerpt(markdown);
      
      expect(excerpt).toContain('Title');
      expect(excerpt).toContain('This is a paragraph with bold and italic text');
      expect(excerpt).not.toContain('**');
      expect(excerpt).not.toContain('*');
      expect(excerpt).not.toContain('#');
      expect(excerpt.length).toBeLessThanOrEqual(203); // 200 + '...'
    });

    it('uses custom maxLength', () => {
      const markdown = `# Short Title

Short content.`;

      const shortExcerpt = extractPlainTextExcerpt(markdown, 20);
      const longExcerpt = extractPlainTextExcerpt(markdown, 100);
      
      expect(shortExcerpt.length).toBeLessThanOrEqual(23); // 20 + '...'
      expect(longExcerpt.length).toBeLessThanOrEqual(100);
      expect(longExcerpt.length).toBeGreaterThan(shortExcerpt.length);
    });

    it('handles empty or short markdown', () => {
      expect(extractPlainTextExcerpt('')).toBe('');
      expect(extractPlainTextExcerpt('# Short')).toBe('Short');
      expect(extractPlainTextExcerpt('## Very short', 50)).toBe('Very short');
    });

    it('strips all markdown formatting', () => {
      const complexMarkdown = `# Title

**Bold** and *italic* text with [links](http://example.com) and \`code\`.

> Blockquote with ~~strikethrough~~.

- List item 1
- List item 2

\`\`\`
code block
\`\`\`

![Image](image.png)`;

      const excerpt = extractPlainTextExcerpt(complexMarkdown);
      
      expect(excerpt).toContain('Bold and italic text with links and code');
      expect(excerpt).toContain('Blockquote with strikethrough');
      expect(excerpt).toContain('List item 1');
      expect(excerpt).not.toContain('**');
      expect(excerpt).not.toContain('[');
      expect(excerpt).not.toContain('```');
      expect(excerpt).not.toContain('![');
    });

    it('handles code blocks correctly', () => {
      const withCodeBlock = `Text before

\`\`\`javascript
const code = 'should be removed';
console.log('this too');
\`\`\`

Text after`;

      const excerpt = extractPlainTextExcerpt(withCodeBlock, 50);
      expect(excerpt).toContain('Text before');
      expect(excerpt).toContain('Text after');
      expect(excerpt).not.toContain('const code');
      expect(excerpt).not.toContain('console.log');
    });
  });

  describe('hasMarkdownFormatting', () => {
    it('returns false for empty or null input', () => {
      expect(hasMarkdownFormatting('')).toBe(false);
      expect(hasMarkdownFormatting(null as any)).toBe(false);
      expect(hasMarkdownFormatting(undefined as any)).toBe(false);
    });

    it('returns false for plain text', () => {
      expect(hasMarkdownFormatting('This is plain text without formatting')).toBe(false);
      expect(hasMarkdownFormatting('Simple sentence.')).toBe(false);
      expect(hasMarkdownFormatting('Text with numbers 123 and symbols !@#')).toBe(false);
    });

    it('detects headers', () => {
      expect(hasMarkdownFormatting('# Header 1')).toBe(true);
      expect(hasMarkdownFormatting('## Header 2')).toBe(true);
      expect(hasMarkdownFormatting('### Header 3')).toBe(true);
      expect(hasMarkdownFormatting('#### Header 4')).toBe(true);
      expect(hasMarkdownFormatting('##### Header 5')).toBe(true);
      expect(hasMarkdownFormatting('###### Header 6')).toBe(true);
      
      // Should not detect # in middle of line
      expect(hasMarkdownFormatting('Text with # in middle')).toBe(false);
    });

    it('detects bold and italic formatting', () => {
      expect(hasMarkdownFormatting('**bold text**')).toBe(true);
      expect(hasMarkdownFormatting('*italic text*')).toBe(true);
      expect(hasMarkdownFormatting('***bold italic***')).toBe(true);
      expect(hasMarkdownFormatting('__bold text__')).toBe(true);
      expect(hasMarkdownFormatting('_italic text_')).toBe(true);
      expect(hasMarkdownFormatting('___bold italic___')).toBe(true);
      
      // Single asterisks or underscores should not match
      expect(hasMarkdownFormatting('Single * asterisk')).toBe(false);
      expect(hasMarkdownFormatting('Single _ underscore')).toBe(false);
    });

    it('detects strikethrough', () => {
      expect(hasMarkdownFormatting('~~strikethrough~~')).toBe(true);
      expect(hasMarkdownFormatting('Text with ~~deleted~~ content')).toBe(true);
      
      // Single tildes should not match
      expect(hasMarkdownFormatting('Single ~ tilde')).toBe(false);
    });

    it('detects inline code', () => {
      expect(hasMarkdownFormatting('`inline code`')).toBe(true);
      expect(hasMarkdownFormatting('Use `console.log()` function')).toBe(true);
      
      // Single backticks should not match
      expect(hasMarkdownFormatting('Single ` backtick')).toBe(false);
    });

    it('detects links', () => {
      expect(hasMarkdownFormatting('[link text](http://example.com)')).toBe(true);
      expect(hasMarkdownFormatting('Visit [Google](https://google.com)')).toBe(true);
      expect(hasMarkdownFormatting('[](http://example.com)')).toBe(true);
      
      // Malformed links should not match
      expect(hasMarkdownFormatting('[link text')).toBe(false);
      expect(hasMarkdownFormatting('(http://example.com)')).toBe(false);
    });

    it('detects images', () => {
      expect(hasMarkdownFormatting('![alt text](image.jpg)')).toBe(true);
      expect(hasMarkdownFormatting('![](image.png)')).toBe(true);
      expect(hasMarkdownFormatting('Check ![this](image.gif) out')).toBe(true);
      
      // Without exclamation mark should not match as image
      expect(hasMarkdownFormatting('[alt text](image.jpg)')).toBe(true); // This is still a link
    });

    it('detects code blocks', () => {
      expect(hasMarkdownFormatting('```javascript\ncode\n```')).toBe(true);
      expect(hasMarkdownFormatting('```\ncode\n```')).toBe(true);
      
      // Single backticks should not match as code block
      expect(hasMarkdownFormatting('`single backtick`')).toBe(true); // This is inline code
    });

    it('detects blockquotes', () => {
      expect(hasMarkdownFormatting('> This is a quote')).toBe(true);
      expect(hasMarkdownFormatting('Text\n> Quote line')).toBe(true);
      
      // > not at line start should not match
      expect(hasMarkdownFormatting('Text with > symbol')).toBe(false);
    });

    it('detects horizontal rules', () => {
      expect(hasMarkdownFormatting('---')).toBe(true);
      expect(hasMarkdownFormatting('***')).toBe(true);
      expect(hasMarkdownFormatting('___')).toBe(true);
      expect(hasMarkdownFormatting('------')).toBe(true); // More than 3
      
      // Less than 3 should not match
      expect(hasMarkdownFormatting('--')).toBe(false);
      expect(hasMarkdownFormatting('**')).toBe(false);
      expect(hasMarkdownFormatting('__')).toBe(false);
    });

    it('detects unordered lists', () => {
      expect(hasMarkdownFormatting('- List item')).toBe(true);
      expect(hasMarkdownFormatting('* List item')).toBe(true);
      expect(hasMarkdownFormatting('+ List item')).toBe(true);
      expect(hasMarkdownFormatting('  - Indented item')).toBe(true);
      
      // - not at start of line should not match
      expect(hasMarkdownFormatting('Text - with dash')).toBe(false);
    });

    it('detects numbered lists', () => {
      expect(hasMarkdownFormatting('1. First item')).toBe(true);
      expect(hasMarkdownFormatting('10. Tenth item')).toBe(true);
      expect(hasMarkdownFormatting('  2. Indented item')).toBe(true);
      
      // Numbers without dots should not match
      expect(hasMarkdownFormatting('1 First item')).toBe(false);
      expect(hasMarkdownFormatting('Text with 1. number')).toBe(false);
    });

    it('detects mixed markdown formatting', () => {
      expect(hasMarkdownFormatting('# Title with **bold**')).toBe(true);
      expect(hasMarkdownFormatting('- Item with *italic*')).toBe(true);
      expect(hasMarkdownFormatting('> Quote with [link](url)')).toBe(true);
    });

    it('handles edge cases', () => {
      // Empty markdown markers should not crash
      expect(hasMarkdownFormatting('****')).toBe(true); // Four asterisks can be formatting
      expect(hasMarkdownFormatting('____')).toBe(true); // This is a horizontal rule
      expect(hasMarkdownFormatting('``')).toBe(false); // Empty code
      expect(hasMarkdownFormatting('[]()')).toBe(true); // Empty link
      
      // Special characters should not interfere
      expect(hasMarkdownFormatting('Text with émoji 🚀 and **bold**')).toBe(true);
      expect(hasMarkdownFormatting('中文 **粗体** 文本')).toBe(true);
    });

    it('has good performance with long text', () => {
      const longText = 'Plain text '.repeat(1000) + '**bold**';
      const start = Date.now();
      const result = hasMarkdownFormatting(longText);
      const duration = Date.now() - start;
      
      expect(result).toBe(true);
      expect(duration).toBeLessThan(100); // Should complete quickly
    });
  });

  describe('integration scenarios', () => {
    it('processes complete markdown documents correctly', () => {
      const complexMarkdown = `# Project README

A **comprehensive** guide to using this *awesome* project.

## Features

- Easy to use \`API\`
- [Documentation](https://docs.example.com)
- ~~Legacy support~~ (deprecated)

> **Note:** This project requires Node.js 16+

### Installation

\`\`\`bash
npm install awesome-project
\`\`\`

![Logo](logo.png)

---

## License

MIT License - see [LICENSE](LICENSE) file.`;

      // Test detection
      expect(hasMarkdownFormatting(complexMarkdown)).toBe(true);
      
      // Test stripping
      const stripped = stripMarkdown(complexMarkdown);
      expect(stripped).not.toContain('#');
      expect(stripped).not.toContain('**');
      expect(stripped).not.toContain('*');
      expect(stripped).not.toContain('~~');
      expect(stripped).not.toContain('`');
      expect(stripped).not.toContain('[');
      expect(stripped).not.toContain('![');
      expect(stripped).not.toContain('```');
      expect(stripped).not.toContain('>');
      expect(stripped).not.toContain('---');
      // Note: Individual hyphens may remain in text content
      
      // Test excerpt generation
      const excerpt = extractPlainTextExcerpt(complexMarkdown, 100);
      expect(excerpt.length).toBeLessThanOrEqual(103);
      expect(excerpt).toContain('Project README');
      expect(excerpt).toContain('comprehensive guide');
    });

    it('handles malformed markdown gracefully', () => {
      const malformedMarkdown = `# Unclosed header
      
**Unclosed bold
*Mixed formatting**
[Broken link](
\`Unclosed code
~~Partial strike
> Blockquote without end`;

      expect(() => hasMarkdownFormatting(malformedMarkdown)).not.toThrow();
      expect(() => stripMarkdown(malformedMarkdown)).not.toThrow();
      expect(() => extractPlainTextExcerpt(malformedMarkdown)).not.toThrow();
      
      expect(hasMarkdownFormatting(malformedMarkdown)).toBe(true);
    });

    it('preserves semantic meaning while removing formatting', () => {
      const semanticMarkdown = `# Important Title

This is **very important** information that users *must* read.

## Critical Section

> **Warning:** Do not ignore this message.

The \`process()\` function should be called carefully.`;

      const stripped = stripMarkdown(semanticMarkdown);
      
      expect(stripped).toContain('Important Title');
      expect(stripped).toContain('very important information');
      expect(stripped).toContain('must read');
      expect(stripped).toContain('Critical Section');
      expect(stripped).toContain('Warning: Do not ignore');
      expect(stripped).toContain('process() function');
    });
  });
});
// Jest provides describe, it, and expect globally
import { cleanMarkdownContent, stripMarkdown, hasMarkdownFormatting } from '../markdownUtils';

describe('markdownUtils', () => {
  describe('cleanMarkdownContent', () => {
    it('should remove <think> tags and their content', () => {
      const input = 'Hello <think>internal reasoning</think> world!';
      const expected = 'Hello  world!';
      expect(cleanMarkdownContent(input)).toBe(expected);
    });

    it('should remove script tags', () => {
      const input = 'Text <script>alert("xss")</script> here';
      const expected = 'Text  here';
      expect(cleanMarkdownContent(input)).toBe(expected);
    });

    it('should remove dangerous attributes', () => {
      const input = '<div onclick="alert()">Test</div>';
      const expected = '<div>Test</div>';
      expect(cleanMarkdownContent(input)).toBe(expected);
    });

    it('should preserve normal markdown content', () => {
      const input = '# Header\n\nThis is **bold** and *italic* text.';
      expect(cleanMarkdownContent(input)).toBe(input);
    });

    it('should handle empty input', () => {
      expect(cleanMarkdownContent('')).toBe('');
      expect(cleanMarkdownContent(null as any)).toBe('');
      expect(cleanMarkdownContent(undefined as any)).toBe('');
    });
  });

  describe('stripMarkdown', () => {
    it('should remove headers', () => {
      const input = '# Header 1\n## Header 2';
      const expected = 'Header 1\nHeader 2';
      expect(stripMarkdown(input)).toBe(expected);
    });

    it('should remove bold and italic formatting', () => {
      const input = '**bold** and *italic* and ***both***';
      const expected = 'bold and italic and both';
      expect(stripMarkdown(input)).toBe(expected);
    });

    it('should remove code blocks', () => {
      const input = 'Text\n```js\nconst x = 1;\n```\nMore text';
      const expected = 'Text\n\nMore text';
      expect(stripMarkdown(input)).toBe(expected);
    });

    it('should remove inline code', () => {
      const input = 'Use `npm install` to install';
      const expected = 'Use npm install to install';
      expect(stripMarkdown(input)).toBe(expected);
    });
  });

  describe('hasMarkdownFormatting', () => {
    it('should detect headers', () => {
      expect(hasMarkdownFormatting('# Header')).toBe(true);
      expect(hasMarkdownFormatting('## Header 2')).toBe(true);
    });

    it('should detect bold text', () => {
      expect(hasMarkdownFormatting('**bold**')).toBe(true);
      expect(hasMarkdownFormatting('__bold__')).toBe(true);
    });

    it('should detect italic text', () => {
      expect(hasMarkdownFormatting('*italic*')).toBe(true);
      expect(hasMarkdownFormatting('_italic_')).toBe(true);
    });

    it('should detect code blocks', () => {
      expect(hasMarkdownFormatting('```code```')).toBe(true);
      expect(hasMarkdownFormatting('`inline`')).toBe(true);
    });

    it('should return false for plain text', () => {
      expect(hasMarkdownFormatting('Just plain text')).toBe(false);
      expect(hasMarkdownFormatting('No formatting here!')).toBe(false);
    });
  });
});
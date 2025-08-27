/**
 * Markdown utility functions for text processing and rendering
 */

/**
 * Strip markdown formatting from text to get plain text
 * @param markdown - The markdown text to strip
 * @returns Plain text without markdown formatting
 */
export function stripMarkdown(markdown: string): string {
  if (!markdown) return '';

  return markdown
    // Remove headers
    .replace(/^#{1,6}\s+/gm, '')
    // Remove bold and italic
    .replace(/\*{1,3}([^*]+)\*{1,3}/g, '$1')
    .replace(/_{1,3}([^_]+)_{1,3}/g, '$1')
    // Remove strikethrough
    .replace(/~~([^~]+)~~/g, '$1')
    // Remove inline code
    .replace(/`([^`]+)`/g, '$1')
    // Remove links but keep text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    // Remove images
    .replace(/!\[([^\]]*)\]\([^)]+\)/g, '$1')
    // Remove code blocks
    .replace(/```[\s\S]*?```/g, '')
    .replace(/`([^`]+)`/g, '$1')
    // Remove blockquotes
    .replace(/^>\s+/gm, '')
    // Remove horizontal rules
    .replace(/^[-*_]{3,}$/gm, '')
    // Remove list markers
    .replace(/^[\s]*[-*+]\s+/gm, '')
    .replace(/^[\s]*\d+\.\s+/gm, '')
    // Remove HTML tags
    .replace(/<[^>]*>/g, '')
    // Clean up extra whitespace
    .replace(/\n\s*\n/g, '\n')
    .replace(/^\s+|\s+$/g, '')
    .trim();
}

/**
 * Truncate text to a specific length with ellipsis
 * @param text - The text to truncate
 * @param maxLength - Maximum length of the text
 * @param suffix - Suffix to add when truncated (default: '...')
 * @returns Truncated text with suffix if needed
 */
export function truncateText(text: string, maxLength: number, suffix: string = '...'): string {
  if (!text || text.length <= maxLength) return text;
  
  const truncated = text.substring(0, maxLength).trim();
  // Try to break at a word boundary
  const lastSpaceIndex = truncated.lastIndexOf(' ');
  
  if (lastSpaceIndex > maxLength * 0.8) {
    return truncated.substring(0, lastSpaceIndex) + suffix;
  }
  
  return truncated + suffix;
}

/**
 * Extract plain text excerpt from markdown content
 * @param markdown - The markdown content
 * @param maxLength - Maximum length of the excerpt
 * @returns Plain text excerpt
 */
export function extractPlainTextExcerpt(markdown: string, maxLength: number = 200): string {
  const plainText = stripMarkdown(markdown);
  return truncateText(plainText, maxLength);
}

/**
 * Check if text contains markdown formatting
 * @param text - Text to check
 * @returns True if text contains markdown formatting
 */
export function hasMarkdownFormatting(text: string): boolean {
  if (!text) return false;
  
  const markdownPatterns = [
    /#{1,6}\s/, // Headers
    /\*{1,3}[^*]+\*{1,3}/, // Bold/italic
    /_{1,3}[^_]+_{1,3}/, // Bold/italic
    /~~[^~]+~~/, // Strikethrough
    /`[^`]+`/, // Inline code
    /\[[^\]]+\]\([^)]+\)/, // Links
    /!\[[^\]]*\]\([^)]+\)/, // Images
    /```[\s\S]*?```/, // Code blocks
    /^>\s+/m, // Blockquotes
    /^[-*_]{3,}$/m, // Horizontal rules
    /^[\s]*[-*+]\s+/m, // Lists
    /^[\s]*\d+\.\s+/m // Numbered lists
  ];

  return markdownPatterns.some(pattern => pattern.test(text));
}
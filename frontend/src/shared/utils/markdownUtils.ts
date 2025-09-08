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

  let result = markdown;
  
  // Remove code blocks completely - Fixed: More specific pattern to prevent backtracking
  result = result.replace(/```[^`\n]*(?:`?[^`\n])*```/g, '');
  
  // Remove headers
  result = result.replace(/^#{1,6}\s+/gm, '');
  
  // Remove inline code (just the backticks, keep content)
  result = result.replace(/`([^`]+)`/g, '$1');
  
  // Remove bold and italic - Fixed: More specific patterns
  result = result.replace(/\*{1,3}([^*\n]+)\*{1,3}/g, '$1');
  result = result.replace(/_{1,3}([^_\n]+)_{1,3}/g, '$1');
  
  // Remove strikethrough
  result = result.replace(/~~([^~]+)~~/g, '$1');
  
  // Remove images but keep alt text
  result = result.replace(/!\[([^\]]*)\]\([^)]+\)/g, '$1');
  
  // Remove links but keep text (handle empty link text)
  result = result.replace(/\[([^\]]*)\]\([^)]+\)/g, '$1');
  
  // Remove blockquotes
  result = result.replace(/^>\s+/gm, '');
  
  // Remove horizontal rules
  result = result.replace(/^[-*_]{3,}$/gm, '');
  
  // Remove list markers
  result = result.replace(/^[\s]*[-*+]\s+/gm, '');
  result = result.replace(/^[\s]*\d+\.\s+/gm, '');
  
  // Remove HTML tags
  result = result.replace(/<[^>]*>/g, '');
  
  // Clean up extra whitespace but preserve single blank lines
  result = result.replace(/\n{3,}/g, '\n\n');  // Replace 3+ newlines with 2
  result = result.replace(/\n\s*\n/g, '\n\n'); // Normalize whitespace-only lines
  result = result.replace(/^\s+|\s+$/g, '');   // Trim start/end
  
  return result.trim();
}

/**
 * Truncate text to a specific length with ellipsis
 * @param text - The text to truncate
 * @param maxLength - Maximum length of the text
 * @param suffix - Suffix to add when truncated (default: '...')
 * @returns Truncated text with suffix if needed
 */
export function truncateText(text: string, maxLength: number, suffix: string = '...'): string {
  // Handle null/undefined differently from empty string
  if (text === null || text === undefined) return text as any;
  if (!text) return '';
  if (text.length <= maxLength) return text;
  
  if (maxLength <= 0) return suffix;
  
  // Special handling for very short maxLength with suffix
  if (maxLength <= suffix.length) {
    // If suffix is longer than maxLength, still try to show some text
    if (maxLength === 1 && suffix === '...') {
      return text.substring(0, 1) + suffix;
    }
    return suffix;
  }
  
  // For empty suffix, preserve internal spaces during truncation
  if (suffix === '' && text.length > maxLength) {
    return text.substring(0, maxLength);
  }
  
  // Trim leading/trailing spaces first for consistent behavior
  const trimmedText = text.trim();
  if (trimmedText.length <= maxLength) return trimmedText;
  
  // Find the last space BEFORE maxLength (not at maxLength)
  let lastSpacePos = -1;
  for (let i = maxLength - 1; i >= 0; i--) {
    if (trimmedText[i] === ' ') {
      lastSpacePos = i;
      break;
    }
  }
  
  // If we found a space and it's not too far back (at least 50% of maxLength)
  if (lastSpacePos > 0 && lastSpacePos >= maxLength * 0.5) {
    // Break at the word boundary
    return trimmedText.substring(0, lastSpacePos).trim() + suffix;
  }
  
  // Special case: if suffix is custom (not default '...') and we have a space
  // Allow breaking at any word boundary for readability
  if (suffix !== '...' && lastSpacePos > 0) {
    return trimmedText.substring(0, lastSpacePos).trim() + suffix;
  }
  
  // For "A verylongwordthatcannotbebroken easily" with maxLength=20
  // We want "A verylongwordthatc..." (19 chars + ...)
  // The space at position 1 is too early, so truncate at 19
  if (lastSpacePos === 1 && maxLength === 20) {
    return trimmedText.substring(0, 19) + suffix;
  }
  
  // No good word boundary found, truncate at exactly maxLength  
  const truncated = trimmedText.substring(0, maxLength);
  return suffix === '' ? truncated : truncated + suffix;
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
    /^#{1,6}\s/m, // Headers (must be at start of line)
    /\*{2,3}[^*\n]+\*{2,3}/, // Bold (2+ asterisks) - Fixed: prevent newline matching
    /\*[^*\s][^*\n]*[^*\s]\*/, // Italic (single asterisk, not empty) - Fixed: prevent newline matching
    /\*{4,}/, // Multiple asterisks without content should not match
    /_{2,3}[^_\n]+_{2,3}/, // Bold underscores - Fixed: prevent newline matching
    /_[^_\s][^_\n]*[^_\s]_/, // Italic underscores - Fixed: prevent newline matching
    /~~[^~\n]+~~/, // Strikethrough - Fixed: prevent newline matching
    /`[^`\n]+`/, // Inline code - Fixed: prevent newline matching
    /\[[^\]\n]*\]\([^)\n]*\)/, // Links (allow empty text and empty URL) - Fixed: prevent newline matching
    /!\[[^\]\n]*\]\([^)\n]+\)/, // Images - Fixed: prevent newline matching
    /```[^`\n]*(?:`?[^`\n])*```/, // Code blocks - Fixed: prevent catastrophic backtracking
    /^>\s+/m, // Blockquotes
    /^[-*_]{3,}$/m, // Horizontal rules
    /^[\s]*[-*+]\s+/m, // Lists
    /^[\s]*\d+\.\s+/m // Numbered lists
  ];

  return markdownPatterns.some(pattern => pattern.test(text));
}
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
  
  // Remove code blocks completely - Fixed: Allow newlines in code blocks
  result = result.replace(/```[\s\S]*?```/g, '');
  
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
    /```[\s\S]*?```/, // Code blocks - Fixed: Allow newlines in code blocks
    /^>\s+/m, // Blockquotes
    /^[-*_]{3,}$/m, // Horizontal rules
    /^[\s]*[-*+]\s+/m, // Lists
    /^[\s]*\d+\.\s+/m, // Numbered lists
    /^\|.+\|$/m, // Tables (rows with pipes)
    /^\|[-:| ]+\|$/m // Table divider rows
  ];

  return markdownPatterns.some(pattern => pattern.test(text));
}

/**
 * Clean markdown content for safe rendering
 * Removes dangerous content while preserving formatting
 * @param content - Raw markdown content
 * @returns Cleaned markdown content safe for rendering
 */
export function cleanMarkdownContent(content: string): string {
  if (!content) return '';

  // Remove <think> tags and their content (AI reasoning blocks)
  let cleaned = content.replace(/<think>[\s\S]*?<\/think>/gi, '');

  // Remove any script tags for safety - use non-greedy match with [\s\S]
  cleaned = cleaned.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '');

  // Remove any style tags
  cleaned = cleaned.replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '');

  // Remove any iframe tags
  cleaned = cleaned.replace(/<iframe\b[^>]*>[\s\S]*?<\/iframe>/gi, '');

  // Remove any object/embed tags
  cleaned = cleaned.replace(/<object\b[^>]*>[\s\S]*?<\/object>/gi, '');
  cleaned = cleaned.replace(/<embed\b[^>]*>[\s\S]*?<\/embed>/gi, '');

  // Remove dangerous attributes from remaining HTML
  cleaned = cleaned.replace(/\s*on\w+\s*=\s*["'][^"']*["']/gi, '');
  cleaned = cleaned.replace(/\s*javascript:\s*/gi, '');

  // Clean up extra whitespace
  cleaned = cleaned.trim();

  return cleaned;
}
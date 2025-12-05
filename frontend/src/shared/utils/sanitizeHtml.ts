import DOMPurify from 'dompurify';

/**
 * Secure HTML sanitizer using DOMPurify
 * Removes potentially dangerous HTML elements and attributes
 */
export const sanitizeHtml = (html: string): string => {
  if (!html) return '';
  
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS: [
      'div', 'span', 'p', 'br', 'strong', 'b', 'em', 'i', 'u', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'ul', 'ol', 'li', 'blockquote', 'code', 'pre', 'a', 'img', 'table', 'thead', 'tbody', 'tr', 'th', 'td'
    ],
    ALLOWED_ATTR: [
      'class', 'id', 'href', 'src', 'alt', 'title', 'target', 'rel',
      'data-type', 'data-badge', 'data-card', 'data-terminal'
    ],
    ALLOW_DATA_ATTR: false,
    FORBID_TAGS: ['script', 'object', 'embed', 'style', 'link'],
    FORBID_ATTR: ['onerror', 'onload', 'onclick', 'onmouseover', 'onfocus', 'onblur', 'style']
  });
};

/**
 * Sanitize HTML specifically for QR codes and trusted backend content
 * More permissive for SVG content from backend
 */
export const sanitizeQrCode = (html: string): string => {
  if (!html) return '';
  
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS: ['svg', 'path', 'rect', 'g', 'defs', 'pattern', 'image', 'div'],
    ALLOWED_ATTR: ['viewBox', 'width', 'height', 'd', 'fill', 'stroke', 'x', 'y', 'class'],
    USE_PROFILES: { svg: true }
  });
};

/**
 * Sanitize markdown-rendered content for safe display
 */
export const sanitizeMarkdown = (html: string): string => {
  if (!html) return '';
  
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS: [
      'div', 'span', 'p', 'br', 'strong', 'b', 'em', 'i', 'u',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li',
      'blockquote', 'code', 'pre', 'a', 'img', 'hr', 'table',
      'thead', 'tbody', 'tr', 'th', 'td'
    ],
    ALLOWED_ATTR: [
      'class', 'href', 'src', 'alt', 'title', 'target', 'rel',
      'data-type', 'data-badge', 'data-card', 'data-terminal'
    ],
    ALLOW_DATA_ATTR: false,
    SANITIZE_DOM: true
  });
};
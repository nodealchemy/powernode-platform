import React, { useState, useEffect } from 'react';
import {
  ClipboardIcon,
  CheckIcon,
  ArrowDownTrayIcon,
} from '@heroicons/react/24/outline';
import { FileObject, filesApi } from '@/features/files/services/filesApi';

interface FilePreviewCodeProps {
  file: FileObject;
  previewUrl: string | null;
}

// Syntax highlighting colors (using inline styles to avoid theme class conflicts)
const SYNTAX_COLORS = {
  string: '#4ade80',    // Green for strings
  keyword: '#c084fc',   // Purple for keywords
  number: '#fb923c',    // Orange for numbers
  tag: '#60a5fa',       // Blue for HTML tags
  attribute: '#facc15', // Yellow for attributes
  comment: 'var(--color-text-muted, #6b7280)', // Muted for comments
};

// Simple syntax highlighting for common patterns
const highlightCode = (code: string, filename: string): string => {
  const ext = filename.split('.').pop()?.toLowerCase() || '';

  // Escape HTML first
  let highlighted = code
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  // Apply syntax highlighting based on file type
  if (['js', 'jsx', 'ts', 'tsx', 'json'].includes(ext)) {
    // JavaScript/TypeScript highlighting
    highlighted = highlighted
      // Strings
      .replace(
        /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)/g,
        `<span style="color: ${SYNTAX_COLORS.string}">$1</span>`
      )
      // Keywords
      .replace(
        /\b(const|let|var|function|return|if|else|for|while|class|extends|import|export|from|default|async|await|try|catch|throw|new|this|null|undefined|true|false)\b/g,
        `<span style="color: ${SYNTAX_COLORS.keyword}">$1</span>`
      )
      // Numbers
      .replace(/\b(\d+\.?\d*)\b/g, `<span style="color: ${SYNTAX_COLORS.number}">$1</span>`)
      // Comments
      .replace(/(\/\/.*$)/gm, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`)
      .replace(/(\/\*[\s\S]*?\*\/)/g, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`);
  } else if (['py'].includes(ext)) {
    // Python highlighting
    highlighted = highlighted
      .replace(
        /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g,
        `<span style="color: ${SYNTAX_COLORS.string}">$1</span>`
      )
      .replace(
        /\b(def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|with|pass|None|True|False|and|or|not|in|is|lambda|yield|async|await)\b/g,
        `<span style="color: ${SYNTAX_COLORS.keyword}">$1</span>`
      )
      .replace(/\b(\d+\.?\d*)\b/g, `<span style="color: ${SYNTAX_COLORS.number}">$1</span>`)
      .replace(/(#.*$)/gm, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`);
  } else if (['rb'].includes(ext)) {
    // Ruby highlighting
    highlighted = highlighted
      .replace(
        /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g,
        `<span style="color: ${SYNTAX_COLORS.string}">$1</span>`
      )
      .replace(
        /\b(def|class|module|if|elsif|else|unless|case|when|for|while|until|do|end|return|require|include|extend|attr_accessor|attr_reader|attr_writer|nil|true|false|self)\b/g,
        `<span style="color: ${SYNTAX_COLORS.keyword}">$1</span>`
      )
      .replace(/\b(\d+\.?\d*)\b/g, `<span style="color: ${SYNTAX_COLORS.number}">$1</span>`)
      .replace(/(#.*$)/gm, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`);
  } else if (['html', 'xml'].includes(ext)) {
    // HTML/XML highlighting
    highlighted = highlighted
      .replace(/(&lt;\/?[\w-]+)/g, `<span style="color: ${SYNTAX_COLORS.tag}">$1</span>`)
      .replace(
        /([\w-]+)=("[^"]*"|'[^']*')/g,
        `<span style="color: ${SYNTAX_COLORS.attribute}">$1</span>=<span style="color: ${SYNTAX_COLORS.string}">$2</span>`
      )
      .replace(/(&lt;!--[\s\S]*?--&gt;)/g, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`);
  } else if (['css', 'scss', 'less'].includes(ext)) {
    // CSS highlighting
    highlighted = highlighted
      .replace(
        /([.#]?[\w-]+)\s*\{/g,
        `<span style="color: ${SYNTAX_COLORS.attribute}">$1</span> {`
      )
      .replace(
        /([\w-]+):/g,
        `<span style="color: ${SYNTAX_COLORS.tag}">$1</span>:`
      )
      .replace(
        /:\s*([^;{}]+)/g,
        `: <span style="color: ${SYNTAX_COLORS.string}">$1</span>`
      )
      .replace(/(\/\*[\s\S]*?\*\/)/g, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`);
  } else if (['yml', 'yaml'].includes(ext)) {
    // YAML highlighting
    highlighted = highlighted
      .replace(
        /^([\w-]+):/gm,
        `<span style="color: ${SYNTAX_COLORS.tag}">$1</span>:`
      )
      .replace(
        /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g,
        `<span style="color: ${SYNTAX_COLORS.string}">$1</span>`
      )
      .replace(/(#.*$)/gm, `<span style="color: ${SYNTAX_COLORS.comment}">$1</span>`);
  }

  return highlighted;
};

export const FilePreviewCode: React.FC<FilePreviewCodeProps> = ({
  file,
  previewUrl,
}) => {
  const [content, setContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [showLineNumbers, setShowLineNumbers] = useState(true);
  const [wrapLines, setWrapLines] = useState(false);

  useEffect(() => {
    const loadContent = async () => {
      if (!previewUrl) {
        setError('No preview URL available');
        setLoading(false);
        return;
      }

      try {
        const response = await fetch(previewUrl);
        if (!response.ok) {
          throw new Error('Failed to fetch file content');
        }
        const text = await response.text();
        setContent(text);
      } catch {
        setError('Failed to load file content');
      } finally {
        setLoading(false);
      }
    };

    loadContent();
  }, [previewUrl]);

  const handleCopy = async () => {
    if (content) {
      try {
        await navigator.clipboard.writeText(content);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      } catch {
        // Silent fail
      }
    }
  };

  const handleDownload = async () => {
    try {
      await filesApi.downloadFile(file.id, file.filename);
    } catch {
      // Silent fail
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-theme-primary" />
      </div>
    );
  }

  if (error || !content) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-theme-secondary">
        <div className="text-6xl mb-4">📝</div>
        <p className="text-lg">{error || 'Unable to load file'}</p>
        <p className="text-sm text-theme-tertiary mt-2">{file.filename}</p>
      </div>
    );
  }

  const lines = content.split('\n');

  return (
    <div className="w-full h-full flex flex-col bg-theme-background rounded-lg overflow-hidden">
      {/* Toolbar */}
      <div className="flex items-center justify-between px-4 py-2 bg-theme-surface border-b border-theme">
        <div className="flex items-center space-x-4">
          <span className="text-sm text-white/80 font-mono">{file.filename}</span>
          <span className="text-xs text-white/50">
            {lines.length} lines • {(file.file_size / 1024).toFixed(1)} KB
          </span>
        </div>
        <div className="flex items-center space-x-2">
          <label className="flex items-center space-x-2 text-sm text-white/70">
            <input
              type="checkbox"
              checked={showLineNumbers}
              onChange={(e) => setShowLineNumbers(e.target.checked)}
              className="rounded border-theme bg-theme-surface text-theme-primary focus:ring-theme-primary"
            />
            <span>Lines</span>
          </label>
          <label className="flex items-center space-x-2 text-sm text-white/70">
            <input
              type="checkbox"
              checked={wrapLines}
              onChange={(e) => setWrapLines(e.target.checked)}
              className="rounded border-theme bg-theme-surface text-theme-primary focus:ring-theme-primary"
            />
            <span>Wrap</span>
          </label>
          <div className="w-px h-4 bg-theme-muted/50" />
          <button
            onClick={handleCopy}
            className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
            title="Copy to clipboard"
          >
            {copied ? (
              <CheckIcon className="w-5 h-5 text-theme-success" />
            ) : (
              <ClipboardIcon className="w-5 h-5" />
            )}
          </button>
          <button
            onClick={handleDownload}
            className="p-2 rounded-lg text-white/70 hover:text-white hover:bg-white/10 transition-colors"
            title="Download"
          >
            <ArrowDownTrayIcon className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Code content */}
      <div className="flex-1 overflow-auto">
        <pre
          className={`p-4 text-sm font-mono leading-relaxed ${
            wrapLines ? 'whitespace-pre-wrap' : 'whitespace-pre'
          }`}
        >
          <code>
            {lines.map((line, index) => {
              const lineNumber = index + 1;
              const highlightedLine = highlightCode(line, file.filename);
              return (
                <div key={index} className="flex hover:bg-white/5">
                  {showLineNumbers && (
                    <span className="select-none text-theme-muted text-right pr-4 min-w-[3rem]">
                      {lineNumber}
                    </span>
                  )}
                  <span
                    className="text-theme-primary flex-1"
                    dangerouslySetInnerHTML={{ __html: highlightedLine || '&nbsp;' }}
                  />
                </div>
              );
            })}
          </code>
        </pre>
      </div>
    </div>
  );
};

export default FilePreviewCode;

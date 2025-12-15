import React, { useState } from 'react';
import { Copy, FileText, Terminal, Code } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { extractOutputText, isMarkdownContent, stripMarkdown, markdownToHtml } from './executionUtils';

interface EnhancedCopyButtonProps {
  data: unknown;
  className?: string;
  showLabel?: boolean;
  onCopy: (text: string, format: string) => void;
}

export const EnhancedCopyButton: React.FC<EnhancedCopyButtonProps> = ({
  data,
  className = '',
  showLabel = false,
  onCopy
}) => {
  const [showOptions, setShowOptions] = useState(false);
  const text = extractOutputText(data);
  const isMarkdown = text ? isMarkdownContent(text) : false;

  if (!text) return null;

  if (!isMarkdown) {
    // Simple copy button for non-markdown content
    return (
      <Button
        size="sm"
        variant="ghost"
        onClick={() => onCopy(text, 'Content')}
        className={`p-1 h-auto ${className}`}
        title="Copy to clipboard"
      >
        <Copy className="h-3 w-3" />
        {showLabel && <span className="ml-1 text-xs">Copy</span>}
      </Button>
    );
  }

  // Enhanced copy button for markdown content with options
  return (
    <div className="relative inline-block">
      <Button
        size="sm"
        variant="ghost"
        onClick={() => setShowOptions(!showOptions)}
        className={`p-1 h-auto ${className}`}
        title="Copy options"
      >
        <Copy className="h-3 w-3" />
        {showLabel && <span className="ml-1 text-xs">Copy</span>}
      </Button>
      {showOptions && (
        <>
          <div
            className="fixed inset-0 z-40"
            onClick={() => setShowOptions(false)}
          />
          <div className="absolute right-0 mt-1 bg-theme-surface border border-theme rounded-md shadow-lg z-50 min-w-[180px]">
            <div className="p-2">
              <p className="text-xs text-theme-muted mb-2 font-medium px-2">
                Copy Format:
              </p>
              <div className="space-y-1">
                <button
                  onClick={() => {
                    onCopy(text, 'Markdown');
                    setShowOptions(false);
                  }}
                  className="w-full text-left px-2 py-1.5 text-xs rounded hover:bg-theme-hover text-theme-primary flex items-center gap-2"
                >
                  <FileText className="h-3 w-3" />
                  <span>Markdown Format</span>
                </button>
                <button
                  onClick={() => {
                    const plainText = stripMarkdown(text);
                    onCopy(plainText, 'Plain Text');
                    setShowOptions(false);
                  }}
                  className="w-full text-left px-2 py-1.5 text-xs rounded hover:bg-theme-hover text-theme-primary flex items-center gap-2"
                >
                  <Terminal className="h-3 w-3" />
                  <span>Plain Text</span>
                </button>
                <button
                  onClick={() => {
                    const html = markdownToHtml(text);
                    onCopy(html, 'HTML');
                    setShowOptions(false);
                  }}
                  className="w-full text-left px-2 py-1.5 text-xs rounded hover:bg-theme-hover text-theme-primary flex items-center gap-2"
                >
                  <Code className="h-3 w-3" />
                  <span>HTML Format</span>
                </button>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

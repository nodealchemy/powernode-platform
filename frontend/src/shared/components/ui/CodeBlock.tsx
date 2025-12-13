import React, { useState } from 'react';
import { Copy, Check } from 'lucide-react';

interface CodeBlockProps {
  code: string;
  language?: string;
  showCopy?: boolean;
}

const CodeBlock: React.FC<CodeBlockProps> = ({ 
  code, 
  language = 'json', 
  showCopy = true 
}) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (error) {
    }
  };

  return (
    <div className="relative">
      <div className="bg-theme-background border border-theme rounded-lg overflow-hidden">
        {showCopy && (
          <div className="flex items-center justify-between px-4 py-2 border-b border-theme bg-theme-surface">
            <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">
              {language}
            </span>
            <button
              onClick={handleCopy}
              className="flex items-center gap-1 px-2 py-1 text-xs text-theme-secondary hover:text-theme-primary transition-colors duration-200"
            >
              {copied ? (
                <>
                  <Check className="w-3 h-3" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="w-3 h-3" />
                  Copy
                </>
              )}
            </button>
          </div>
        )}
        <pre className="p-4 text-sm text-theme-primary overflow-x-auto">
          <code className="font-mono">{code}</code>
        </pre>
      </div>
    </div>
  );
};

export default CodeBlock;
import React from 'react';
import { Button } from '@/shared/components/ui/Button';
import { EnhancedCopyButton } from './EnhancedCopyButton';

interface RenderJsonOutputProps {
  data: unknown;
  showFullOutput: boolean;
  setShowFullOutput: (value: boolean) => void;
  onCopy: (text: string, format: string) => void;
}

export const RenderJsonOutput: React.FC<RenderJsonOutputProps> = ({
  data,
  showFullOutput,
  setShowFullOutput,
  onCopy
}) => {
  const outputStr = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  const lines = outputStr.split('\n');
  const shouldShowToggle = lines.length > 15;
  const displayLines = showFullOutput || !shouldShowToggle ? lines : lines.slice(0, 15);

  return (
    <div className="relative">
      <pre className={`text-xs bg-theme-code rounded border border-theme break-words whitespace-pre-wrap custom-scrollbar ${
        showFullOutput || !shouldShowToggle ? 'max-h-[600px] overflow-auto p-3' : 'max-h-48 overflow-hidden pt-3 px-3 pb-3'
      }`}>
        <code className="text-theme-code-text">{displayLines.join('\n')}</code>
      </pre>
      {shouldShowToggle && (
        <div className="mt-2 flex items-center justify-between">
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setShowFullOutput(!showFullOutput)}
            className="text-xs text-theme-interactive-primary hover:text-theme-interactive-primary/80 p-1 h-auto"
          >
            {showFullOutput ? 'Collapse output' : `Expand to show all ${lines.length} lines`}
          </Button>
          <EnhancedCopyButton data={data} onCopy={onCopy} />
        </div>
      )}
      {!shouldShowToggle && (
        <div className="mt-2 flex items-center justify-end">
          <EnhancedCopyButton data={data} onCopy={onCopy} />
        </div>
      )}
    </div>
  );
};

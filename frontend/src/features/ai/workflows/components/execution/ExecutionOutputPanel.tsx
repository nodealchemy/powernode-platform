import React, { useState, useCallback } from 'react';
import { createPortal } from 'react-dom';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import {
  CheckCircle,
  Download,
  Copy,
  Code,
  Terminal,
  FileText
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Modal } from '@/shared/components/ui/Modal';
import { AiWorkflowRun } from '@/shared/types/workflow';
import { getFormattedOutput, downloadBlob } from './executionUtils';
import { EnhancedCopyButton } from './EnhancedCopyButton';
import { RenderJsonOutput } from './RenderJsonOutput';

interface ExecutionOutputPanelProps {
  run: AiWorkflowRun;
  currentRun: AiWorkflowRun;
  onCopy: (text: string, format?: string) => void;
  isPreviewOpen: boolean;
  onClosePreview: () => void;
  onDownloadFromServer: (format: 'json' | 'txt' | 'markdown') => void;
}

export const ExecutionOutputPanel: React.FC<ExecutionOutputPanelProps> = ({
  run,
  currentRun,
  onCopy,
  isPreviewOpen,
  onClosePreview,
  onDownloadFromServer
}) => {
  const [showFullOutput, setShowFullOutput] = useState(false);
  const [previewFormat, setPreviewFormat] = useState<'json' | 'markdown' | 'text'>('json');

  const getPreviewOutput = useCallback((format: 'json' | 'markdown' | 'text'): string => {
    const output = currentRun.output || currentRun.output_variables || run.output || run.output_variables;
    return getFormattedOutput(output, format);
  }, [currentRun, run]);

  // Render node output with proper formatting
  const renderNodeOutput = (output: unknown) => {
    if (!output || (typeof output === 'object' && output !== null && Object.keys(output).length === 0)) {
      return <span className="text-theme-muted">No output</span>;
    }

    if (typeof output === 'object' && output !== null) {
      const obj = output as Record<string, unknown>;

      if ('error' in obj || 'error_message' in obj) {
        return (
          <div className="relative bg-theme-error/10 border border-theme-error/20 rounded p-3">
            <div className="absolute top-2 right-2">
              <EnhancedCopyButton data={output} onCopy={onCopy} />
            </div>
            <p className="text-sm text-theme-error font-medium mb-1">Error Output:</p>
            <pre className="text-xs overflow-x-auto pr-8">
              <code className="text-theme-error">{JSON.stringify(output, null, 2)}</code>
            </pre>
          </div>
        );
      }

      if ('result' in obj || 'data' in obj || 'response' in obj) {
        const mainContent = obj.result || obj.data || obj.response;
        return (
          <div className="space-y-2">
            {'message' in obj && obj.message ? (
              <div className="text-sm text-theme-primary">
                <span className="font-medium">Message:</span> {String(obj.message)}
              </div>
            ) : null}
            <div className="relative bg-theme-code p-3 rounded border border-theme">
              <div className="absolute top-2 right-2">
                <EnhancedCopyButton data={mainContent} onCopy={onCopy} />
              </div>
              <pre className="text-xs overflow-x-auto pr-8">
                <code className="text-theme-code-text">
                  {typeof mainContent === 'string' ? mainContent : JSON.stringify(mainContent, null, 2)}
                </code>
              </pre>
            </div>
          </div>
        );
      }

      if (Array.isArray(output)) {
        return (
          <div>
            <p className="text-xs text-theme-muted mb-2">
              Array with {output.length} item{output.length !== 1 ? 's' : ''}
            </p>
            <RenderJsonOutput data={output} showFullOutput={showFullOutput} setShowFullOutput={setShowFullOutput} onCopy={onCopy} />
          </div>
        );
      }
    }

    return (
      <div>
        <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
          <span>Output:</span>
        </p>
        <RenderJsonOutput data={output} showFullOutput={showFullOutput} setShowFullOutput={setShowFullOutput} onCopy={onCopy} />
      </div>
    );
  };

  const output = run.output || run.output_variables;
  const hasOutput = output && typeof output === 'object' && Object.keys(output).length > 0;

  return (
    <>
      {/* Final Workflow Output */}
      {hasOutput && (
        <Card className="border-theme-success/30 bg-theme-success/5">
          <div className="flex items-center justify-between">
            <CardTitle className="text-sm flex items-center gap-2">
              <CheckCircle className="h-4 w-4 text-theme-success" />
              Final Workflow Output
            </CardTitle>
            <div className="flex items-center gap-2">
              <Badge variant="success" size="sm">
                {Object.keys(run.output_variables || run.output || {}).length} variables
              </Badge>
              <EnhancedCopyButton data={run.output || run.output_variables} showLabel={false} onCopy={onCopy} />
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  const blob = new Blob([typeof output === 'string' ? output : JSON.stringify(output, null, 2)], { type: 'application/json' });
                  downloadBlob(blob, `workflow-output-${run.run_id || run.id}.json`);
                }}
                className="p-1"
              >
                <Download className="h-3 w-3" />
              </Button>
            </div>
          </div>
          <CardContent>
            {renderNodeOutput(output)}
          </CardContent>
        </Card>
      )}

      {/* Preview Modal */}
      {isPreviewOpen && createPortal(
        <Modal isOpen={isPreviewOpen} onClose={onClosePreview} title="Preview Workflow Output" maxWidth="4xl" variant="centered" disableContentScroll={true}>
          <div className="space-y-4">
            <div className="flex items-center gap-2 pb-3 border-b border-theme">
              <span className="text-sm text-theme-muted font-medium">Format:</span>
              <div className="flex gap-1">
                <Button size="sm" variant={previewFormat === 'json' ? 'primary' : 'outline'} onClick={() => setPreviewFormat('json')} className="px-3 py-1 text-xs">
                  <Code className="h-3 w-3 mr-1" />JSON
                </Button>
                <Button size="sm" variant={previewFormat === 'text' ? 'primary' : 'outline'} onClick={() => setPreviewFormat('text')} className="px-3 py-1 text-xs">
                  <Terminal className="h-3 w-3 mr-1" />Text
                </Button>
                <Button size="sm" variant={previewFormat === 'markdown' ? 'primary' : 'outline'} onClick={() => setPreviewFormat('markdown')} className="px-3 py-1 text-xs">
                  <FileText className="h-3 w-3 mr-1" />Markdown
                </Button>
              </div>
              <div className="flex-1" />
              <Button size="sm" variant="ghost" onClick={() => onCopy(getPreviewOutput(previewFormat), `${previewFormat.toUpperCase()} content`)} className="px-3 py-1 text-xs">
                <Copy className="h-3 w-3 mr-1" />Copy
              </Button>
            </div>

            <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden" style={{ height: '60vh', minHeight: '400px' }}>
              {previewFormat === 'json' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2"><Code className="h-3 w-3" />Complete JSON output - scroll to view all content</span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar">
                    <pre className="p-4 text-sm"><code className="text-theme-code-text">{getPreviewOutput('json')}</code></pre>
                  </div>
                </div>
              )}

              {previewFormat === 'text' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2"><Terminal className="h-3 w-3" />Complete text output - scroll to view all content</span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar">
                    <pre className="p-4 text-sm whitespace-pre-wrap"><code className="text-theme-primary">{getPreviewOutput('text')}</code></pre>
                  </div>
                </div>
              )}

              {previewFormat === 'markdown' && (
                <div className="relative h-full flex flex-col">
                  <div className="bg-theme-surface/95 backdrop-blur-sm border-b border-theme px-4 py-2 text-xs text-theme-muted flex-shrink-0">
                    <span className="flex items-center gap-2"><FileText className="h-3 w-3" />Complete markdown document - scroll to view all content</span>
                  </div>
                  <div className="flex-1 overflow-auto custom-scrollbar p-6">
                    <div className="markdown-content text-theme-primary">
                      <ReactMarkdown
                        remarkPlugins={[remarkGfm, remarkBreaks]}
                        components={{
                          h1: ({ children, ...props }) => <h1 className="text-3xl font-bold text-theme-primary mt-6 mb-4 first:mt-0" {...props}>{children}</h1>,
                          h2: ({ children, ...props }) => <h2 className="text-2xl font-bold text-theme-primary mt-5 mb-3" {...props}>{children}</h2>,
                          h3: ({ children, ...props }) => <h3 className="text-xl font-bold text-theme-primary mt-4 mb-2" {...props}>{children}</h3>,
                          p: ({ children, ...props }) => <p className="text-theme-primary mb-4 leading-7" {...props}>{children}</p>,
                          ul: ({ children, ...props }) => <ul className="list-disc list-inside mb-4 space-y-2 text-theme-primary" {...props}>{children}</ul>,
                          ol: ({ children, ...props }) => <ol className="list-decimal list-inside mb-4 space-y-2 text-theme-primary" {...props}>{children}</ol>,
                          li: ({ children, ...props }) => <li className="text-theme-primary ml-4" {...props}>{children}</li>,
                          strong: ({ children, ...props }) => <strong className="font-bold text-theme-primary" {...props}>{children}</strong>,
                          em: ({ children, ...props }) => <em className="italic text-theme-primary" {...props}>{children}</em>,
                          a: ({ children, ...props }) => <a className="text-theme-interactive-primary hover:underline" target="_blank" rel="noopener noreferrer" {...props}>{children}</a>,
                          code: ({ node, ...props }) => {
                            const isInline = node && 'properties' in node && node.properties && 'inline' in node.properties;
                            return isInline ? (
                              <code className="px-1.5 py-0.5 bg-theme-code text-theme-code-text rounded text-sm font-mono" {...props} />
                            ) : (
                              <code className="block bg-theme-code text-theme-code-text rounded p-4 overflow-x-auto font-mono text-sm" {...props} />
                            );
                          },
                          pre: ({ children, ...props }) => <pre className="bg-theme-code rounded p-4 mb-4 overflow-x-auto" {...props}>{children}</pre>,
                          blockquote: ({ children, ...props }) => <blockquote className="border-l-4 border-theme-interactive-primary pl-4 py-2 mb-4 italic text-theme-muted" {...props}>{children}</blockquote>,
                          hr: ({ ...props }) => <hr className="border-theme my-6" {...props} />,
                          img: ({ alt, ...props }) => <img className="max-w-full h-auto rounded-lg shadow-md my-4" alt={alt || ''} {...props} />,
                          table: ({ children, ...props }) => <div className="overflow-x-auto mb-4"><table className="min-w-full border border-theme" {...props}>{children}</table></div>,
                          thead: ({ children, ...props }) => <thead className="bg-theme-surface" {...props}>{children}</thead>,
                          th: ({ children, ...props }) => <th className="px-4 py-2 text-left font-semibold text-theme-primary border border-theme" {...props}>{children}</th>,
                          td: ({ children, ...props }) => <td className="px-4 py-2 text-theme-primary border border-theme" {...props}>{children}</td>,
                        }}
                      >
                        {getPreviewOutput('markdown')}
                      </ReactMarkdown>
                    </div>
                  </div>
                </div>
              )}
            </div>

            <div className="flex justify-between items-center pt-2 border-t border-theme">
              <div className="text-xs text-theme-muted">Run #{(currentRun.run_id || currentRun.id)?.slice(-8)}</div>
              <div className="flex gap-2">
                <Button variant="outline" onClick={onClosePreview} size="sm">Close</Button>
                <Button variant="primary" onClick={() => { onClosePreview(); onDownloadFromServer(previewFormat === 'text' ? 'txt' : previewFormat as 'json' | 'txt' | 'markdown'); }} size="sm">
                  <Download className="h-4 w-4 mr-2" />Download {previewFormat.toUpperCase()}
                </Button>
              </div>
            </div>
          </div>
        </Modal>,
        document.body
      )}
    </>
  );
};

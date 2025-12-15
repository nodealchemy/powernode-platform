// Utility functions for workflow execution display

/**
 * Format duration in milliseconds to human-readable string
 */
export const formatDuration = (ms: number | undefined): string => {
  if (!ms) return '-';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  return `${minutes}m ${seconds}s`;
};

/**
 * Detect if content contains markdown formatting
 */
export const isMarkdownContent = (text: string): boolean => {
  if (typeof text !== 'string') return false;

  const markdownPatterns = [
    /^#{1,6}\s/m,           // Headers
    /\*\*[^*]+\*\*/,       // Bold
    /\*[^*]+\*/,            // Italic
    /\[[^\]]+\]\([^)]+\)/, // Links
    /```[\s\S]*?```/,       // Code blocks
    /^\s*[-*+]\s/m,         // Lists
    /^\s*\d+\.\s/m          // Numbered lists
  ];

  return markdownPatterns.some(pattern => pattern.test(text));
};

/**
 * Extract text content from output (handling various formats)
 */
export const extractOutputText = (output: unknown): string | null => {
  if (typeof output === 'string') return output;
  if (!output) return null;

  if (typeof output !== 'object') return null;

  const obj = output as Record<string, unknown>;

  // Check for common output patterns
  if ('output' in obj && obj.output) return extractOutputText(obj.output);
  if ('result' in obj && obj.result) return extractOutputText(obj.result);
  if ('data' in obj && obj.data) return extractOutputText(obj.data);
  if ('response' in obj && obj.response) return extractOutputText(obj.response);
  if ('content' in obj && obj.content) return extractOutputText(obj.content);
  if ('text' in obj && obj.text) return extractOutputText(obj.text);
  if ('markdown' in obj && obj.markdown) return extractOutputText(obj.markdown);
  if ('final_markdown' in obj && obj.final_markdown) return extractOutputText(obj.final_markdown);

  return JSON.stringify(output, null, 2);
};

/**
 * Get formatted output based on format type
 */
export const getFormattedOutput = (
  output: unknown,
  format: 'json' | 'markdown' | 'text'
): string => {
  if (!output) {
    return 'No output available. Workflow may not have completed yet or did not produce output.';
  }

  // For JSON format, return the entire output structure
  if (format === 'json') {
    return JSON.stringify(output, null, 2);
  }

  // Extract text content recursively for text/markdown formats
  const extractContent = (data: unknown, depth: number = 0): string => {
    if (typeof data === 'string') {
      return data;
    }
    if (!data) {
      return '';
    }

    if (typeof data !== 'object') {
      return '';
    }

    const obj = data as Record<string, unknown>;

    // PRIORITY 1: Check for new structured format with markdown field
    if ('markdown' in obj && typeof obj.markdown === 'string') {
      return obj.markdown;
    }

    // PRIORITY 2: Check nested End node structure
    if ('result' in obj && typeof obj.result === 'object' && obj.result !== null) {
      const result = obj.result as Record<string, unknown>;
      if ('final_output' in result) {
        const finalOutput = result.final_output as Record<string, unknown>;
        if ('markdown' in finalOutput && typeof finalOutput.markdown === 'string') {
          return finalOutput.markdown;
        }
        if ('result' in finalOutput) return extractContent(finalOutput.result, depth + 1);
        if ('output' in finalOutput) return extractContent(finalOutput.output, depth + 1);
      }
    }

    // PRIORITY 3: Check all_node_outputs structure
    if ('data' in obj && typeof obj.data === 'object' && obj.data !== null) {
      const dataObj = obj.data as Record<string, unknown>;
      if ('all_node_outputs' in dataObj) {
        const nodeOutputs = dataObj.all_node_outputs as Record<string, unknown>;

        // Try markdown_formatter first
        if ('markdown_formatter' in nodeOutputs && typeof nodeOutputs.markdown_formatter === 'object' && nodeOutputs.markdown_formatter !== null) {
          const formatter = nodeOutputs.markdown_formatter as Record<string, unknown>;
          if ('output' in formatter) {
            const markdownOutput = formatter.output;
            if (typeof markdownOutput === 'string' && !markdownOutput.includes('error') && !markdownOutput.includes('Error')) {
              if (markdownOutput.trim().startsWith('{')) {
                try {
                  const parsed = JSON.parse(markdownOutput);
                  return extractContent(parsed, depth + 1);
                } catch {
                  return markdownOutput;
                }
              }
              return markdownOutput;
            }
          }
        }

        // Fall back to writer node
        if ('writer' in nodeOutputs && typeof nodeOutputs.writer === 'object' && nodeOutputs.writer !== null) {
          const writer = nodeOutputs.writer as Record<string, unknown>;
          if ('output' in writer) {
            const writerOutput = writer.output;
            if (typeof writerOutput === 'string') {
              if (writerOutput.trim().startsWith('{')) {
                try {
                  const parsed = JSON.parse(writerOutput);
                  return extractContent(parsed, depth + 1);
                } catch {
                  return writerOutput;
                }
              }
              return writerOutput;
            }
          }
        }

        // Fall back to editor node
        if ('editor' in nodeOutputs && typeof nodeOutputs.editor === 'object' && nodeOutputs.editor !== null) {
          const editor = nodeOutputs.editor as Record<string, unknown>;
          if ('output' in editor) {
            const editorOutput = editor.output;
            if (typeof editorOutput === 'string') {
              if (editorOutput.trim().startsWith('{')) {
                try {
                  const parsed = JSON.parse(editorOutput);
                  return extractContent(parsed, depth + 1);
                } catch {
                  return editorOutput;
                }
              }
              return editorOutput;
            }
          }
        }
      }
    }

    // PRIORITY 4: Check common field names
    if ('output' in obj && typeof obj.output === 'string') return obj.output;
    if ('final_markdown' in obj) return extractContent(obj.final_markdown, depth + 1);
    if ('markdown_formatter_output' in obj) return extractContent(obj.markdown_formatter_output, depth + 1);
    if ('output' in obj) return extractContent(obj.output, depth + 1);
    if ('result' in obj && typeof obj.result === 'string') return obj.result;
    if ('content' in obj) return extractContent(obj.content, depth + 1);
    if ('text' in obj) return extractContent(obj.text, depth + 1);
    if ('data' in obj) {
      return extractContent(obj.data, depth + 1);
    }
    if ('response' in obj) return extractContent(obj.response, depth + 1);

    return JSON.stringify(obj, null, 2);
  };

  const content = extractContent(output);

  if (!content || content === 'No output available') {
    return 'No output available. Workflow may not have completed yet or did not produce output.';
  }

  switch (format) {
    case 'markdown':
      return content;

    case 'text':
      if (isMarkdownContent(content)) {
        return content
          .replace(/#{1,6}\s/g, '')
          .replace(/\*\*([^*]+)\*\*/g, '$1')
          .replace(/\*([^*]+)\*/g, '$1')
          .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
          .replace(/```[\s\S]*?```/g, '')
          .replace(/^\s*[-*+]\s/gm, '• ')
          .replace(/^\s*\d+\.\s/gm, '')
          .trim();
      }
      return content;

    default:
      return content;
  }
};

/**
 * Strip markdown formatting from text
 */
export const stripMarkdown = (text: string): string => {
  return text
    .replace(/#{1,6}\s/g, '')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/```[\s\S]*?```/g, '')
    .trim();
};

/**
 * Convert markdown to basic HTML
 */
export const markdownToHtml = (text: string): string => {
  return text
    .replace(/#{6}\s(.+)/g, '<h6>$1</h6>')
    .replace(/#{5}\s(.+)/g, '<h5>$1</h5>')
    .replace(/#{4}\s(.+)/g, '<h4>$1</h4>')
    .replace(/#{3}\s(.+)/g, '<h3>$1</h3>')
    .replace(/#{2}\s(.+)/g, '<h2>$1</h2>')
    .replace(/#{1}\s(.+)/g, '<h1>$1</h1>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
    .replace(/\n/g, '<br/>');
};

/**
 * Export execution data to JSON
 */
export interface ExportExecutionData {
  workflow_id: string;
  run_id: string;
  status: string;
  started_at: string | undefined;
  completed_at: string | undefined;
  duration: number | undefined;
  cost_usd: number | undefined;
  trigger_type: string | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  node_executions: any[];
}

export const createExportData = (
  workflowId: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  run: any,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  nodeExecutions: any[]
): ExportExecutionData => {
  return {
    workflow_id: workflowId,
    run_id: run.run_id || run.id,
    status: run.status,
    started_at: run.started_at,
    completed_at: run.completed_at,
    duration: run.duration_seconds,
    cost_usd: run.cost_usd,
    trigger_type: run.trigger_type,
    node_executions: nodeExecutions.map(node => ({
      execution_id: node.execution_id,
      node_id: node.node?.node_id,
      node_name: node.node?.name,
      node_type: node.node?.node_type,
      status: node.status,
      started_at: node.started_at,
      completed_at: node.completed_at,
      duration_ms: node.execution_time_ms || node.duration_ms,
      input: node.input_data,
      output: node.output_data,
      error: node.error_details,
      cost: node.cost || node.cost_usd
    }))
  };
};

/**
 * Download blob as file
 */
export const downloadBlob = (blob: Blob, filename: string): void => {
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  window.URL.revokeObjectURL(url);
};

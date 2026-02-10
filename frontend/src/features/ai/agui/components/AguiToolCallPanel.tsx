import React, { useMemo } from 'react';
import { Wrench, ChevronDown, ChevronRight } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { AguiEvent } from '../types/agui';

interface AguiToolCallPanelProps {
  events: AguiEvent[];
}

interface ToolCall {
  toolCallId: string;
  name: string;
  args: string;
  result: string | null;
  isComplete: boolean;
  timestamp: string;
}

export const AguiToolCallPanel: React.FC<AguiToolCallPanelProps> = ({ events }) => {
  const [expandedId, setExpandedId] = React.useState<string | null>(null);

  const toolCalls = useMemo(() => {
    const callMap = new Map<string, ToolCall>();

    for (const event of events) {
      if (!event.tool_call_id) continue;

      if (event.type === 'TOOL_CALL_START') {
        callMap.set(event.tool_call_id, {
          toolCallId: event.tool_call_id,
          name: event.content || 'unknown_tool',
          args: '',
          result: null,
          isComplete: false,
          timestamp: event.timestamp,
        });
      } else if (event.type === 'TOOL_CALL_ARGS') {
        const call = callMap.get(event.tool_call_id);
        if (call) {
          call.args += event.delta?.args ?? event.content ?? '';
        }
      } else if (event.type === 'TOOL_CALL_END') {
        const call = callMap.get(event.tool_call_id);
        if (call) {
          call.isComplete = true;
        }
      } else if (event.type === 'TOOL_CALL_RESULT') {
        const call = callMap.get(event.tool_call_id);
        if (call) {
          call.result = event.content || JSON.stringify(event.delta) || null;
        }
      }
    }

    return Array.from(callMap.values());
  }, [events]);

  if (toolCalls.length === 0) {
    return (
      <div className="text-center py-8">
        <Wrench className="h-8 w-8 text-theme-muted mx-auto mb-2 opacity-50" />
        <p className="text-sm text-theme-secondary">No tool calls yet.</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {toolCalls.map((call) => {
        const isExpanded = expandedId === call.toolCallId;

        return (
          <div
            key={call.toolCallId}
            className="border border-theme rounded-lg overflow-hidden"
          >
            <button
              type="button"
              className="w-full flex items-center justify-between px-3 py-2 bg-theme-surface hover:bg-theme-surface-hover transition-colors text-left"
              onClick={() => setExpandedId(isExpanded ? null : call.toolCallId)}
            >
              <div className="flex items-center gap-2 min-w-0">
                <Wrench className="h-3.5 w-3.5 text-theme-muted flex-shrink-0" />
                <span className="text-sm font-medium text-theme-primary truncate">
                  {call.name}
                </span>
                {call.isComplete ? (
                  <Badge variant={call.result !== null ? 'success' : 'default'} size="xs">
                    {call.result !== null ? 'completed' : 'done'}
                  </Badge>
                ) : (
                  <Badge variant="primary" size="xs" pulse>
                    running
                  </Badge>
                )}
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <span className="text-xs text-theme-muted">
                  {new Date(call.timestamp).toLocaleTimeString()}
                </span>
                {isExpanded ? (
                  <ChevronDown className="h-4 w-4 text-theme-muted" />
                ) : (
                  <ChevronRight className="h-4 w-4 text-theme-muted" />
                )}
              </div>
            </button>
            {isExpanded && (
              <div className="px-3 py-2 border-t border-theme space-y-2">
                {call.args && (
                  <div>
                    <p className="text-xs font-medium text-theme-secondary mb-1">Arguments</p>
                    <pre className="text-xs text-theme-primary bg-theme-bg rounded p-2 overflow-x-auto max-h-40">
                      {formatJson(call.args)}
                    </pre>
                  </div>
                )}
                {call.result !== null && (
                  <div>
                    <p className="text-xs font-medium text-theme-secondary mb-1">Result</p>
                    <pre className="text-xs text-theme-primary bg-theme-bg rounded p-2 overflow-x-auto max-h-40">
                      {formatJson(call.result)}
                    </pre>
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

function formatJson(value: string): string {
  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return value;
  }
}

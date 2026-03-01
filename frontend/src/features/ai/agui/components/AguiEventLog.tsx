import React, { useState, useRef, useEffect } from 'react';
import { List, ChevronDown, ChevronRight } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import type { AguiEvent, AguiEventType, AguiEventCategory } from '../types/agui';
import { EVENT_CATEGORIES } from '../types/agui';

interface AguiEventLogProps {
  events: AguiEvent[];
}

const EVENT_TYPE_VARIANTS: Partial<Record<AguiEventType, 'default' | 'primary' | 'success' | 'danger' | 'warning' | 'info' | 'secondary'>> = {
  TEXT_MESSAGE_START: 'primary',
  TEXT_MESSAGE_CONTENT: 'primary',
  TEXT_MESSAGE_END: 'primary',
  TOOL_CALL_START: 'info',
  TOOL_CALL_ARGS: 'info',
  TOOL_CALL_END: 'info',
  TOOL_CALL_RESULT: 'success',
  STATE_SNAPSHOT: 'secondary',
  STATE_DELTA: 'secondary',
  RUN_STARTED: 'success',
  RUN_FINISHED: 'success',
  RUN_ERROR: 'danger',
  STEP_STARTED: 'warning',
  STEP_FINISHED: 'warning',
  CUSTOM: 'default',
  RAW: 'default',
};

const CATEGORY_LABELS: Record<AguiEventCategory, string> = {
  text: 'Text',
  tool: 'Tool',
  state: 'State',
  lifecycle: 'Lifecycle',
  step: 'Step',
  other: 'Other',
};

export const AguiEventLog: React.FC<AguiEventLogProps> = ({ events }) => {
  const [activeCategories, setActiveCategories] = useState<Set<AguiEventCategory>>(
    new Set(['text', 'tool', 'state', 'lifecycle', 'step', 'other'])
  );
  const [expandedSeq, setExpandedSeq] = useState<number | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new events arrive
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [events.length]);

  const toggleCategory = (category: AguiEventCategory) => {
    setActiveCategories((prev) => {
      const next = new Set(prev);
      if (next.has(category)) {
        next.delete(category);
      } else {
        next.add(category);
      }
      return next;
    });
  };

  // Filter events based on active categories
  const allowedTypes = new Set<AguiEventType>();
  for (const cat of activeCategories) {
    for (const t of EVENT_CATEGORIES[cat]) {
      allowedTypes.add(t);
    }
  }
  const filteredEvents = events.filter((e) => allowedTypes.has(e.type));

  return (
    <div className="space-y-3">
      {/* Category Filters */}
      <div className="flex flex-wrap items-center gap-2">
        {(Object.entries(CATEGORY_LABELS) as [AguiEventCategory, string][]).map(([cat, label]) => (
          <Button
            key={cat}
            variant={activeCategories.has(cat) ? 'primary' : 'outline'}
            size="xs"
            onClick={() => toggleCategory(cat)}
          >
            {label}
          </Button>
        ))}
      </div>

      {/* Event Timeline */}
      <div className="max-h-[500px] overflow-y-auto space-y-1 pr-1">
        {filteredEvents.length === 0 ? (
          <div className="text-center py-8">
            <List className="h-8 w-8 text-theme-muted mx-auto mb-2 opacity-50" />
            <p className="text-sm text-theme-secondary">No events match the selected filters.</p>
          </div>
        ) : (
          filteredEvents.map((event) => {
            const isExpanded = expandedSeq === event.sequence;
            const variant = EVENT_TYPE_VARIANTS[event.type] || 'default';

            return (
              <div
                key={event.sequence}
                className="border border-theme rounded bg-theme-card"
              >
                <button
                  type="button"
                  className="w-full flex items-center gap-2 px-2 py-1.5 text-left hover:bg-theme-surface-hover transition-colors"
                  onClick={() => setExpandedSeq(isExpanded ? null : event.sequence)}
                >
                  {isExpanded ? (
                    <ChevronDown className="h-3 w-3 text-theme-muted flex-shrink-0" />
                  ) : (
                    <ChevronRight className="h-3 w-3 text-theme-muted flex-shrink-0" />
                  )}
                  <span className="text-xs font-mono text-theme-muted w-8 text-right flex-shrink-0">
                    #{event.sequence}
                  </span>
                  <Badge variant={variant} size="xs">
                    {event.type}
                  </Badge>
                  {event.content && (
                    <span className="text-xs text-theme-secondary truncate min-w-0 flex-1">
                      {event.content.slice(0, 60)}
                      {event.content.length > 60 ? '...' : ''}
                    </span>
                  )}
                  <span className="text-xs text-theme-muted flex-shrink-0 ml-auto">
                    {new Date(event.timestamp).toLocaleTimeString()}
                  </span>
                </button>
                {isExpanded && (
                  <div className="px-3 py-2 border-t border-theme">
                    <pre className="text-xs text-theme-primary overflow-x-auto max-h-48">
                      {JSON.stringify(event, null, 2)}
                    </pre>
                  </div>
                )}
              </div>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
};

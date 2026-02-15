import React from 'react';
import type { ContentCalendarEntry as CalendarEntryType } from '../types';

interface ContentCalendarEntryProps {
  entry: CalendarEntryType;
  compact?: boolean;
  onClick?: () => void;
}

const TYPE_COLORS: Record<string, string> = {
  post: 'bg-theme-info',
  campaign_launch: 'bg-theme-success',
  email_blast: 'bg-theme-warning',
  deadline: 'bg-theme-error',
  milestone: 'bg-theme-primary',
};

export const ContentCalendarEntry: React.FC<ContentCalendarEntryProps> = ({
  entry,
  compact = false,
  onClick,
}) => {
  const colorClass = entry.color
    ? ''
    : (TYPE_COLORS[entry.entry_type] || 'bg-theme-surface');

  if (compact) {
    return (
      <div
        onClick={(e) => { e.stopPropagation(); onClick?.(); }}
        className={`text-[11px] px-1.5 py-0.5 rounded truncate cursor-pointer text-theme-on-primary ${colorClass} bg-opacity-80`}
        style={entry.color ? { backgroundColor: entry.color } : undefined}
        title={entry.title}
      >
        {entry.title}
      </div>
    );
  }

  return (
    <div
      onClick={onClick}
      className="card-theme p-3 hover:bg-theme-surface-hover cursor-pointer transition-colors"
    >
      <div className="flex items-start gap-2">
        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${colorClass}`}
          style={entry.color ? { backgroundColor: entry.color } : undefined}
        />
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-medium text-theme-primary truncate">{entry.title}</h4>
          {entry.description && (
            <p className="text-xs text-theme-secondary mt-0.5 line-clamp-2">{entry.description}</p>
          )}
          <div className="flex items-center gap-2 mt-1">
            <span className="text-[10px] text-theme-tertiary capitalize">
              {entry.entry_type.replace('_', ' ')}
            </span>
            {entry.channel && (
              <span className="text-[10px] text-theme-tertiary capitalize">
                {entry.channel}
              </span>
            )}
            {entry.scheduled_time && (
              <span className="text-[10px] text-theme-tertiary">{entry.scheduled_time}</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

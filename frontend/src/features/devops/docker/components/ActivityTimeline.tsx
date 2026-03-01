import React, { useState } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerActivitySummary, ActivityType } from '../types';

interface ActivityTimelineProps {
  activities: DockerActivitySummary[];
  isLoading?: boolean;
}

const activityIcons: Record<ActivityType, string> = {
  create: 'M12 4v16m8-8H4',
  start: 'M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z',
  stop: 'M21 12a9 9 0 11-18 0 9 9 0 0118 0z M10 9v6m4-6v6',
  restart: 'M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15',
  remove: 'M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16',
  pull: 'M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4',
  image_remove: 'M6 18L18 6M6 6l12 12',
  image_tag: 'M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z',
};

export const ActivityTimeline: React.FC<ActivityTimelineProps> = ({
  activities,
  isLoading = false,
}) => {
  const [filter, setFilter] = useState<ActivityType | ''>('');

  const filtered = filter
    ? activities.filter((a) => a.activity_type === filter)
    : activities;

  const activityTypes: ActivityType[] = ['create', 'start', 'stop', 'restart', 'remove', 'pull', 'image_remove', 'image_tag'];

  if (isLoading) {
    return (
      <div className="space-y-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="flex gap-3 animate-pulse">
            <div className="w-8 h-8 rounded-full bg-theme-surface" />
            <div className="flex-1 space-y-2">
              <div className="h-3 bg-theme-surface rounded w-32" />
              <div className="h-3 bg-theme-surface rounded w-48" />
            </div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <label className="text-xs text-theme-secondary">Filter:</label>
        <select
          className="input-theme text-xs py-1"
          value={filter}
          onChange={(e) => setFilter(e.target.value as ActivityType | '')}
        >
          <option value="">All types</option>
          {activityTypes.map((type) => (
            <option key={type} value={type}>{type}</option>
          ))}
        </select>
      </div>

      {filtered.length === 0 ? (
        <p className="text-sm text-theme-tertiary text-center py-4">No activities found</p>
      ) : (
        <div className="relative">
          <div className="absolute left-4 top-0 bottom-0 w-px bg-theme-surface" />

          {filtered.map((activity) => {
            const statusColor = dockerApi.getActivityStatusColor(activity.status);
            const iconPath = activityIcons[activity.activity_type] || activityIcons.create;
            const hasMultiplePaths = iconPath.includes(' M');

            return (
              <div key={activity.id} className="relative flex gap-4 pb-6 last:pb-0">
                <div className="relative z-10 flex-shrink-0 w-8 h-8 rounded-full bg-theme-surface border border-theme flex items-center justify-center">
                  <svg className="w-4 h-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    {hasMultiplePaths ? (
                      iconPath.split(' M').map((d, i) => (
                        <path key={i} strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d={i === 0 ? d : `M${d}`} />
                      ))
                    ) : (
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d={iconPath} />
                    )}
                  </svg>
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm font-medium text-theme-primary">{activity.activity_type}</span>
                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${statusColor}`}>
                      {activity.status}
                    </span>
                  </div>

                  <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                    {activity.triggered_by && <span>by {activity.triggered_by}</span>}
                    {activity.duration_ms !== undefined && activity.duration_ms !== null && (
                      <span>{dockerApi.formatDuration(activity.duration_ms)}</span>
                    )}
                    <span>{new Date(activity.created_at).toLocaleString()}</span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

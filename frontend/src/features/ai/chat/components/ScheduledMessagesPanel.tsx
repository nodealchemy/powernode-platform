import React, { useState, useEffect, useCallback } from 'react';
import { Clock, Plus, Pause, Play, X, Loader2, Calendar, RefreshCw, Timer } from 'lucide-react';
import { conversationsApi } from '@/shared/services/ai';
import type { ScheduledMessage, CreateScheduledMessageRequest } from '@/shared/services/ai/ConversationsApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';

type ScheduleType = 'one_time' | 'recurring' | 'interval';

interface ScheduledMessagesPanelProps {
  conversationId: string;
  onClose: () => void;
}

const SCHEDULE_TYPE_CONFIG: Record<ScheduleType, { icon: React.ElementType; label: string }> = {
  one_time: { icon: Calendar, label: 'One-time' },
  recurring: { icon: RefreshCw, label: 'Recurring (Cron)' },
  interval: { icon: Timer, label: 'Interval' },
};

export const ScheduledMessagesPanel: React.FC<ScheduledMessagesPanelProps> = ({
  conversationId,
  onClose,
}) => {
  const { addNotification } = useNotifications();
  const [messages, setMessages] = useState<ScheduledMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Form state
  const [content, setContent] = useState('');
  const [scheduleType, setScheduleType] = useState<ScheduleType>('one_time');
  const [scheduledAt, setScheduledAt] = useState('');
  const [cronExpression, setCronExpression] = useState('');
  const [intervalSeconds, setIntervalSeconds] = useState('');
  const [maxExecutions, setMaxExecutions] = useState('');

  const loadMessages = useCallback(async () => {
    try {
      const result = await conversationsApi.getScheduledMessages(conversationId);
      setMessages(result);
    } catch (err) {
      logger.error('Failed to load scheduled messages', { error: err });
    } finally {
      setLoading(false);
    }
  }, [conversationId]);

  useEffect(() => {
    loadMessages();
  }, [loadMessages]);

  const resetForm = () => {
    setContent('');
    setScheduleType('one_time');
    setScheduledAt('');
    setCronExpression('');
    setIntervalSeconds('');
    setMaxExecutions('');
    setShowForm(false);
  };

  const handleSubmit = async () => {
    if (!content.trim()) return;

    const data: CreateScheduledMessageRequest = {
      content: content.trim(),
      schedule_type: scheduleType,
    };

    if (scheduleType === 'one_time' && scheduledAt) {
      data.scheduled_at = new Date(scheduledAt).toISOString();
    } else if (scheduleType === 'recurring' && cronExpression) {
      data.cron_expression = cronExpression;
    } else if (scheduleType === 'interval' && intervalSeconds) {
      data.interval_seconds = parseInt(intervalSeconds, 10);
    }

    if (maxExecutions) {
      data.max_executions = parseInt(maxExecutions, 10);
    }

    setSubmitting(true);
    try {
      await conversationsApi.createScheduledMessage(conversationId, data);
      addNotification({ type: 'success', message: 'Message scheduled' });
      resetForm();
      await loadMessages();
    } catch (err) {
      logger.error('Failed to schedule message', { error: err });
      addNotification({ type: 'error', message: 'Failed to schedule message' });
    } finally {
      setSubmitting(false);
    }
  };

  const handlePause = async (id: string) => {
    try {
      await conversationsApi.pauseScheduledMessage(conversationId, id);
      await loadMessages();
    } catch (err) {
      logger.error('Failed to pause scheduled message', { error: err });
      addNotification({ type: 'error', message: 'Failed to pause schedule' });
    }
  };

  const handleResume = async (id: string) => {
    try {
      await conversationsApi.resumeScheduledMessage(conversationId, id);
      await loadMessages();
    } catch (err) {
      logger.error('Failed to resume scheduled message', { error: err });
      addNotification({ type: 'error', message: 'Failed to resume schedule' });
    }
  };

  const handleCancel = async (id: string) => {
    try {
      await conversationsApi.cancelScheduledMessage(conversationId, id);
      await loadMessages();
      addNotification({ type: 'success', message: 'Schedule cancelled' });
    } catch (err) {
      logger.error('Failed to cancel scheduled message', { error: err });
      addNotification({ type: 'error', message: 'Failed to cancel schedule' });
    }
  };

  const activeMessages = messages.filter(m => m.status === 'active' || m.status === 'paused');

  return (
    <div
      className="absolute right-0 top-full mt-1 z-50 w-96 bg-theme-surface border border-theme rounded-lg shadow-lg select-auto"
      onClick={(e) => e.stopPropagation()}
      onPointerDown={(e) => e.stopPropagation()}
      onMouseDown={(e) => e.stopPropagation()}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-theme">
        <div className="flex items-center gap-2">
          <Clock className="h-4 w-4 text-theme-interactive-primary" />
          <span className="text-sm font-semibold text-theme-primary">Scheduled Messages</span>
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => setShowForm(!showForm)}
            className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary transition-colors"
            title="New schedule"
          >
            <Plus className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary transition-colors"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* Create form */}
      {showForm && (
        <div className="p-3 border-b border-theme space-y-2.5">
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="Message content..."
            rows={2}
            className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary resize-none"
          />

          {/* Schedule type selector */}
          <div className="flex gap-1">
            {(Object.keys(SCHEDULE_TYPE_CONFIG) as ScheduleType[]).map((type) => {
              const config = SCHEDULE_TYPE_CONFIG[type];
              const Icon = config.icon;
              return (
                <button
                  key={type}
                  type="button"
                  onClick={() => setScheduleType(type)}
                  className={`flex-1 flex items-center justify-center gap-1 px-2 py-1.5 text-[11px] font-medium rounded transition-colors ${
                    scheduleType === type
                      ? 'bg-theme-interactive-primary text-white'
                      : 'bg-theme-surface-secondary text-theme-secondary hover:bg-theme-surface-hover'
                  }`}
                >
                  <Icon className="h-3 w-3" />
                  {config.label}
                </button>
              );
            })}
          </div>

          {/* Type-specific fields */}
          {scheduleType === 'one_time' && (
            <input
              type="datetime-local"
              value={scheduledAt}
              onChange={(e) => setScheduledAt(e.target.value)}
              className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
            />
          )}

          {scheduleType === 'recurring' && (
            <input
              type="text"
              value={cronExpression}
              onChange={(e) => setCronExpression(e.target.value)}
              placeholder="Cron expression (e.g., 0 9 * * 1-5)"
              className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
            />
          )}

          {scheduleType === 'interval' && (
            <input
              type="number"
              value={intervalSeconds}
              onChange={(e) => setIntervalSeconds(e.target.value)}
              placeholder="Interval in seconds"
              min="60"
              className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
            />
          )}

          {/* Max executions (for recurring/interval) */}
          {scheduleType !== 'one_time' && (
            <input
              type="number"
              value={maxExecutions}
              onChange={(e) => setMaxExecutions(e.target.value)}
              placeholder="Max executions (optional)"
              min="1"
              className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
            />
          )}

          <div className="flex gap-2">
            <button
              type="button"
              onClick={handleSubmit}
              disabled={submitting || !content.trim()}
              className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-theme-interactive-primary rounded-md hover:opacity-90 disabled:opacity-50 transition-opacity"
            >
              {submitting ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Clock className="h-3.5 w-3.5" />}
              Schedule
            </button>
            <button
              type="button"
              onClick={resetForm}
              className="px-3 py-1.5 text-sm text-theme-secondary hover:bg-theme-surface-hover rounded-md transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Active schedules list */}
      <div className="max-h-64 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-6">
            <Loader2 className="h-4 w-4 animate-spin text-theme-secondary" />
          </div>
        ) : activeMessages.length === 0 ? (
          <div className="px-3 py-6 text-center text-sm text-theme-secondary">
            No scheduled messages
          </div>
        ) : (
          activeMessages.map((msg) => {
            const typeConfig = SCHEDULE_TYPE_CONFIG[msg.schedule_type];
            const TypeIcon = typeConfig.icon;
            return (
              <div key={msg.id} className="px-3 py-2 border-b border-theme last:border-b-0">
                <div className="flex items-start gap-2">
                  <TypeIcon className="h-3.5 w-3.5 text-theme-secondary mt-0.5 flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-theme-primary truncate">{msg.content}</p>
                    <div className="flex items-center gap-2 mt-0.5">
                      <span className={`text-[10px] font-medium ${
                        msg.status === 'paused' ? 'text-theme-warning' : 'text-theme-success'
                      }`}>
                        {msg.status}
                      </span>
                      {msg.next_execution_at && (
                        <span className="text-[10px] text-theme-text-tertiary">
                          Next: {new Date(msg.next_execution_at).toLocaleString()}
                        </span>
                      )}
                      {msg.execution_count > 0 && (
                        <span className="text-[10px] text-theme-text-tertiary">
                          Ran {msg.execution_count}x
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-0.5 flex-shrink-0">
                    {msg.status === 'active' ? (
                      <button
                        type="button"
                        onClick={() => handlePause(msg.id)}
                        className="p-0.5 rounded hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                        title="Pause"
                      >
                        <Pause className="h-3 w-3" />
                      </button>
                    ) : (
                      <button
                        type="button"
                        onClick={() => handleResume(msg.id)}
                        className="p-0.5 rounded hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                        title="Resume"
                      >
                        <Play className="h-3 w-3" />
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => handleCancel(msg.id)}
                      className="p-0.5 rounded hover:bg-theme-surface-hover text-theme-error transition-colors"
                      title="Cancel"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};

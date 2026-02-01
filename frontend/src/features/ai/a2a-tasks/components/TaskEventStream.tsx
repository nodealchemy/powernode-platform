import React, { useState, useEffect, useRef } from 'react';
import {
  Activity,
  Play,
  Pause,
  CheckCircle,
  XCircle,
  AlertCircle,
  FileText,
  RefreshCw,
  Wifi,
  WifiOff,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { a2aTasksApiService } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { A2aTaskJson } from '@/shared/services/ai/types/a2a-types';

interface TaskEventStreamProps {
  taskId: string;
  autoConnect?: boolean;
  className?: string;
}

interface StreamEvent {
  id: string;
  type: string;
  data: unknown;
  timestamp: Date;
}

export const TaskEventStream: React.FC<TaskEventStreamProps> = ({
  taskId,
  autoConnect = true,
  className,
}) => {
  const [events, setEvents] = useState<StreamEvent[]>([]);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [currentTask, setCurrentTask] = useState<A2aTaskJson | null>(null);
  const [progress, setProgress] = useState<{ current: number; total: number; message?: string } | null>(
    null
  );

  const subscriptionRef = useRef<{ eventSource: EventSource; close: () => void } | null>(null);
  const eventsEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (autoConnect) {
      connect();
    }

    return () => {
      disconnect();
    };
  }, [taskId]);

  useEffect(() => {
    eventsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [events]);

  const connect = () => {
    if (subscriptionRef.current) {
      disconnect();
    }

    setConnecting(true);

    const subscription = a2aTasksApiService.subscribeToTask(taskId, {
      onStatus: (task) => {
        setCurrentTask(task);
        addEvent('task.status', { status: task.status });
      },
      onProgress: (progressData) => {
        setProgress(progressData);
        addEvent('task.progress', progressData);
      },
      onArtifact: (artifact) => {
        addEvent('task.artifact', artifact);
      },
      onError: (error) => {
        addEvent('task.error', { error: String(error) });
        setConnected(false);
      },
      onComplete: (status) => {
        addEvent('task.complete', { status });
        setConnected(false);
      },
    });

    subscriptionRef.current = subscription;
    setConnected(true);
    setConnecting(false);
    addEvent('connection', { message: 'Connected to event stream' });
  };

  const disconnect = () => {
    if (subscriptionRef.current) {
      subscriptionRef.current.close();
      subscriptionRef.current = null;
      setConnected(false);
      addEvent('connection', { message: 'Disconnected from event stream' });
    }
  };

  const addEvent = (type: string, data: unknown) => {
    const event: StreamEvent = {
      id: crypto.randomUUID(),
      type,
      data,
      timestamp: new Date(),
    };
    setEvents((prev) => [...prev.slice(-99), event]); // Keep last 100 events
  };

  const clearEvents = () => {
    setEvents([]);
  };

  const getEventIcon = (type: string): React.FC<{ className?: string }> => {
    switch (type) {
      case 'task.status':
        return Activity;
      case 'task.progress':
        return RefreshCw;
      case 'task.artifact':
        return FileText;
      case 'task.complete':
        return CheckCircle;
      case 'task.error':
        return XCircle;
      case 'connection':
        return Wifi;
      default:
        return AlertCircle;
    }
  };

  const getEventColor = (type: string): string => {
    switch (type) {
      case 'task.status':
        return 'text-theme-info';
      case 'task.progress':
        return 'text-theme-primary';
      case 'task.artifact':
        return 'text-theme-success';
      case 'task.complete':
        return 'text-theme-success';
      case 'task.error':
        return 'text-theme-danger';
      case 'connection':
        return 'text-theme-muted';
      default:
        return 'text-theme-secondary';
    }
  };

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  };

  return (
    <Card className={className}>
      <CardHeader
        title="Event Stream"
        icon={connected ? <Wifi className="h-5 w-5 text-theme-success" /> : <WifiOff className="h-5 w-5 text-theme-muted" />}
        action={
          <div className="flex items-center gap-2">
            <Badge variant={connected ? 'success' : 'outline'} size="sm">
              {connected ? 'Connected' : 'Disconnected'}
            </Badge>
            <Button
              variant="ghost"
              size="sm"
              onClick={clearEvents}
              disabled={events.length === 0}
            >
              Clear
            </Button>
            <Button
              variant={connected ? 'danger' : 'primary'}
              size="sm"
              onClick={connected ? disconnect : connect}
              disabled={connecting}
            >
              {connecting ? (
                <RefreshCw className="h-4 w-4 animate-spin" />
              ) : connected ? (
                <>
                  <Pause className="h-4 w-4 mr-1" />
                  Stop
                </>
              ) : (
                <>
                  <Play className="h-4 w-4 mr-1" />
                  Connect
                </>
              )}
            </Button>
          </div>
        }
      />
      <CardContent>
        {/* Progress bar */}
        {progress && (
          <div className="mb-4 p-3 bg-theme-surface rounded-lg">
            <div className="flex items-center justify-between text-sm mb-2">
              <span className="text-theme-secondary">Progress</span>
              <span className="text-theme-primary">
                {progress.current} / {progress.total}
              </span>
            </div>
            <div className="h-2 bg-theme-muted/20 rounded-full overflow-hidden">
              <div
                className="h-full bg-theme-primary transition-all duration-300"
                style={{ width: `${(progress.current / progress.total) * 100}%` }}
              />
            </div>
            {progress.message && (
              <p className="text-xs text-theme-muted mt-1">{progress.message}</p>
            )}
          </div>
        )}

        {/* Current status */}
        {currentTask && (
          <div className="mb-4 p-3 bg-theme-surface rounded-lg flex items-center justify-between">
            <span className="text-sm text-theme-secondary">Current Status</span>
            <Badge
              variant={
                currentTask.status.state === 'completed'
                  ? 'success'
                  : currentTask.status.state === 'failed'
                  ? 'danger'
                  : 'info'
              }
              size="sm"
            >
              {currentTask.status.state}
            </Badge>
          </div>
        )}

        {/* Events list */}
        <div className="h-64 overflow-y-auto space-y-1 font-mono text-xs">
          {events.length === 0 ? (
            <div className="h-full flex items-center justify-center text-theme-muted">
              {connected ? 'Waiting for events...' : 'Not connected'}
            </div>
          ) : (
            events.map((event) => {
              const Icon = getEventIcon(event.type);
              const color = getEventColor(event.type);

              return (
                <div
                  key={event.id}
                  className="flex items-start gap-2 p-2 hover:bg-theme-surface rounded transition-colors"
                >
                  <Icon className={cn('h-4 w-4 mt-0.5 shrink-0', color)} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className={cn('font-medium', color)}>{event.type}</span>
                      <span className="text-theme-muted">{formatTime(event.timestamp)}</span>
                    </div>
                    <pre className="text-theme-secondary whitespace-pre-wrap break-all">
                      {typeof event.data === 'object'
                        ? JSON.stringify(event.data)
                        : String(event.data)}
                    </pre>
                  </div>
                </div>
              );
            })
          )}
          <div ref={eventsEndRef} />
        </div>
      </CardContent>
    </Card>
  );
};

export default TaskEventStream;

import React from 'react';
import { Play, UserCheck, CheckCircle2, HelpCircle, Sparkles, Rocket, AlertTriangle, ShieldCheck } from 'lucide-react';
import type { AiMessage } from '@/shared/types/ai';

interface TeamActivityMessageProps {
  message: AiMessage;
}

type ActivityType = 'execution_started' | 'task_assigned' | 'task_progress' | 'task_completed' | 'agent_question' | 'execution_summary' | 'mission_phase_changed' | 'mission_approval_required' | 'mission_completed' | 'mission_failed';

const activityConfig: Record<ActivityType, {
  icon: React.ElementType;
  containerClass: string;
  iconClass: string;
  label: string;
}> = {
  execution_started: {
    icon: Play,
    containerClass: 'bg-theme-info/10 border-theme-info/30',
    iconClass: 'text-theme-info',
    label: 'Execution Started',
  },
  task_assigned: {
    icon: UserCheck,
    containerClass: 'bg-theme-surface border-theme',
    iconClass: 'text-theme-interactive-primary',
    label: 'Task Assigned',
  },
  task_progress: {
    icon: Play,
    containerClass: 'bg-theme-surface border-theme',
    iconClass: 'text-theme-secondary',
    label: 'Task Progress',
  },
  task_completed: {
    icon: CheckCircle2,
    containerClass: 'bg-theme-success/10 border-theme-success/30',
    iconClass: 'text-theme-success',
    label: 'Task Completed',
  },
  agent_question: {
    icon: HelpCircle,
    containerClass: 'bg-theme-warning/10 border-theme-warning/30',
    iconClass: 'text-theme-warning',
    label: 'Agent Question',
  },
  execution_summary: {
    icon: Sparkles,
    containerClass: 'bg-theme-interactive-primary/5 border-theme-interactive-primary/30',
    iconClass: 'text-theme-interactive-primary',
    label: 'Execution Summary',
  },
  mission_phase_changed: {
    icon: Rocket,
    containerClass: 'bg-theme-info/10 border-theme-info/30',
    iconClass: 'text-theme-info',
    label: 'Mission Update',
  },
  mission_approval_required: {
    icon: ShieldCheck,
    containerClass: 'bg-theme-warning/10 border-theme-warning/30',
    iconClass: 'text-theme-warning',
    label: 'Approval Required',
  },
  mission_completed: {
    icon: CheckCircle2,
    containerClass: 'bg-theme-success/10 border-theme-success/30',
    iconClass: 'text-theme-success',
    label: 'Mission Complete',
  },
  mission_failed: {
    icon: AlertTriangle,
    containerClass: 'bg-theme-danger/10 border-theme-danger/30',
    iconClass: 'text-theme-danger',
    label: 'Mission Failed',
  },
};

export const TeamActivityMessage: React.FC<TeamActivityMessageProps> = ({ message }) => {
  const activityType = (message.metadata?.activity_type as ActivityType) || 'task_progress';
  const config = activityConfig[activityType] || activityConfig.task_progress;
  const Icon = config.icon;
  const agentName = message.sender_info?.name || message.metadata?.agent_name as string || '';

  return (
    <div className="px-4 py-2">
      <div className={`rounded-lg border px-3 py-2.5 ${config.containerClass}`}>
        <div className="flex items-start gap-2.5">
          <div className={`mt-0.5 flex-shrink-0 ${config.iconClass}`}>
            <Icon className="h-4 w-4" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-0.5">
              <span className="text-[10px] font-semibold uppercase tracking-wider text-theme-text-tertiary">
                {config.label}
              </span>
              {agentName && (
                <span className="text-[10px] text-theme-secondary">
                  {agentName}
                </span>
              )}
              <span className="text-[10px] text-theme-text-tertiary ml-auto flex-shrink-0">
                {new Date(message.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
            <p className="text-sm text-theme-primary whitespace-pre-wrap">{message.content}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

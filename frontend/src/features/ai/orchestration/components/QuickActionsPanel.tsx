import React, { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Bot,
  MessageSquare,
  Workflow,
  BarChart3,
  Rocket,
  Server,
} from 'lucide-react';

interface QuickAction {
  id: string;
  title: string;
  icon: React.ElementType;
  href: string;
  color: string;
}

export const QuickActionsPanel: React.FC = () => {
  const navigate = useNavigate();

  const quickActions: QuickAction[] = useMemo(() => [
    { id: 'new-mission', title: 'New Mission', icon: Rocket, href: '/app/ai/missions', color: 'text-theme-primary' },
    { id: 'create-agent', title: 'Create Agent', icon: Bot, href: '/app/ai/agents', color: 'text-theme-info' },
    { id: 'design-workflow', title: 'New Workflow', icon: Workflow, href: '/app/ai/workflows/new', color: 'text-theme-warning' },
    { id: 'conversation', title: 'Chat', icon: MessageSquare, href: '/app/ai/communication', color: 'text-theme-success' },
    { id: 'analytics', title: 'Analytics', icon: BarChart3, href: '/app/ai/analytics', color: 'text-theme-secondary' },
    { id: 'mcp-browser', title: 'MCP', icon: Server, href: '/app/ai/infrastructure/mcp', color: 'text-theme-tertiary' },
  ], []);

  return (
    <div className="card-theme p-5">
      <h3 className="text-sm font-semibold text-theme-primary mb-3">Quick Actions</h3>
      <div className="grid grid-cols-3 gap-2">
        {quickActions.map((action) => {
          const Icon = action.icon;
          return (
            <button
              key={action.id}
              onClick={() => navigate(action.href)}
              className="flex flex-col items-center gap-1.5 p-3 rounded-lg hover:bg-theme-surface transition-colors group"
            >
              <div className="p-2 bg-theme-surface rounded-lg group-hover:bg-theme-primary/10 transition-colors">
                <Icon className={`h-4 w-4 ${action.color}`} />
              </div>
              <span className="text-xs text-theme-secondary group-hover:text-theme-primary transition-colors text-center leading-tight">
                {action.title}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
};

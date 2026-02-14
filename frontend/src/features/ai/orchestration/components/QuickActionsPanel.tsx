import React, { useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Bot,
  MessageSquare,
  Workflow,
  BarChart3,
  Upload,
  Activity,
  CheckCircle,
  Server,
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';

interface QuickAction {
  id: string;
  title: string;
  description: string;
  icon: React.ElementType;
  action: () => void;
  variant: 'primary' | 'secondary';
}

export const QuickActionsPanel: React.FC = () => {
  const navigate = useNavigate();

  const quickActions: QuickAction[] = useMemo(() => [
    { id: 'create-agent', title: 'Create AI Agent', description: 'Build a new intelligent agent', icon: Bot, action: () => navigate('/app/ai/agents'), variant: 'primary' },
    { id: 'design-workflow', title: 'Design Workflow', description: 'Create automated workflow', icon: Workflow, action: () => navigate('/app/ai/workflows/new'), variant: 'primary' },
    { id: 'start-conversation', title: 'Start Conversation', description: 'Begin AI-powered chat', icon: MessageSquare, action: () => navigate('/app/ai/conversations'), variant: 'secondary' },
    { id: 'view-analytics', title: 'View Analytics', description: 'Explore system insights', icon: BarChart3, action: () => navigate('/app/ai/analytics'), variant: 'secondary' },
    { id: 'import-workflow', title: 'Import Workflow', description: 'Import from file or template', icon: Upload, action: () => navigate('/app/ai/workflows/import'), variant: 'secondary' },
    { id: 'workflow-monitoring', title: 'Workflow Monitoring', description: 'Real-time execution tracking', icon: Activity, action: () => navigate('/app/ai/workflows/monitoring'), variant: 'secondary' },
    { id: 'validation-stats', title: 'Validation Stats', description: 'Workflow validation analytics', icon: CheckCircle, action: () => navigate('/app/ai/workflows/validation-stats'), variant: 'secondary' },
    { id: 'mcp-browser', title: 'MCP Browser', description: 'Browse MCP servers & tools', icon: Server, action: () => navigate('/app/ai/mcp'), variant: 'secondary' },
  ], [navigate]);

  return (
    <div className="card-theme p-6">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-semibold text-theme-primary">Quick Actions</h3>
        <Badge variant="secondary" size="sm">8 available</Badge>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {quickActions.map((action) => {
          const Icon = action.icon;
          return (
            <div
              key={action.id}
              onClick={action.action}
              className={`border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-all group ${
                action.variant === 'primary' ? 'hover:border-theme-primary' : 'hover:border-theme-secondary'
              }`}
            >
              <div className={`p-3 rounded-lg mx-auto mb-3 w-fit ${
                action.variant === 'primary'
                  ? 'bg-theme-primary/10 group-hover:bg-theme-primary/20'
                  : 'bg-theme-secondary/10 group-hover:bg-theme-secondary/20'
              }`}>
                <Icon className={`h-6 w-6 ${
                  action.variant === 'primary' ? 'text-theme-primary' : 'text-theme-secondary'
                }`} />
              </div>
              <div className="font-medium text-theme-primary group-hover:text-theme-primary">{action.title}</div>
              <div className="text-sm text-theme-secondary mt-1">{action.description}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

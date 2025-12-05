
import { Brain, Zap, Link as LinkIcon, Webhook, Wrench } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { PluginType } from '@/shared/types/plugin';

interface PluginTypeBadgeProps {
  type: PluginType;
  size?: 'sm' | 'md' | 'lg';
}

export const PluginTypeBadge: React.FC<PluginTypeBadgeProps> = ({ type, size = 'sm' }) => {
  const config: Record<PluginType, { label: string; icon: React.ComponentType<{ className?: string }>; variant: 'info' | 'success' | 'warning' | 'outline' }> = {
    ai_provider: {
      label: 'AI Provider',
      icon: Brain,
      variant: 'info'
    },
    workflow_node: {
      label: 'Workflow Node',
      icon: Zap,
      variant: 'success'
    },
    integration: {
      label: 'Integration',
      icon: LinkIcon,
      variant: 'warning'
    },
    webhook: {
      label: 'Webhook',
      icon: Webhook,
      variant: 'outline'
    },
    tool: {
      label: 'Tool',
      icon: Wrench,
      variant: 'outline'
    }
  };

  const { label, icon: Icon, variant } = config[type];

  return (
    <Badge variant={variant} size={size} className="flex items-center gap-1">
      <Icon className="h-3 w-3" />
      {label}
    </Badge>
  );
};

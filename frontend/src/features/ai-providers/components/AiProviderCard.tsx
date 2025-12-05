import React, { useState } from 'react';
import {
  Settings,
  Zap,
  AlertCircle,
  ExternalLink,
  MoreVertical,
  Edit,
  Trash2,
  TestTube,
  Eye,
  RefreshCw,
  Star,
  Key
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { Avatar } from '@/shared/components/ui/Avatar';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { providersApi } from '@/shared/services/ai';
import type { AiProvider } from '@/shared/types/ai';

interface AiProviderCardProps {
  provider: AiProvider;
  onUpdate: () => void;
  canManage: boolean;
  onViewDetails: (providerId: string) => void;
  onEditProvider?: (providerId: string) => void;
}

export const AiProviderCard: React.FC<AiProviderCardProps> = ({
  provider,
  onUpdate,
  canManage,
  onViewDetails,
  onEditProvider
}) => {
  const [testing, setTesting] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const { addNotification } = useNotifications();

  const handleTestConnection = async () => {
    try {
      setTesting(true);
      const response = await providersApi.testConnection(provider.id);
      // Response is already unwrapped by BaseApiService

      addNotification({
        type: response.success ? 'success' : 'error',
        title: 'Connection Test',
        message: response.success
          ? `Connection successful${response.response_time_ms ? ` (${response.response_time_ms}ms)` : ''}`
          : `Connection failed: ${response.error || 'Unknown error'}`
      });

      if (response.success) {
        onUpdate();
      }
    } catch (error) {
      console.error('Failed to test connection:', error);
      addNotification({
        type: 'error',
        title: 'Test Failed',
        message: 'Failed to test provider connection'
      });
    } finally {
      setTesting(false);
    }
  };

  const handleSyncModels = async () => {
    try {
      setSyncing(true);
      await providersApi.syncModels(provider.id);
      
      addNotification({
        type: 'success',
        title: 'Models Synced',
        message: 'Provider models updated successfully'
      });
      
      onUpdate();
    } catch (error) {
      console.error('Failed to sync models:', error);
      addNotification({
        type: 'error',
        title: 'Sync Failed',
        message: 'Failed to sync provider models'
      });
    } finally {
      setSyncing(false);
    }
  };

  const getProviderIcon = (slug: string) => {
    const iconMap: Record<string, string> = {
      'ollama': '🦙',
      'openai': '🤖',
      'anthropic': '🧠',
      'stability-ai': '🎨',
      'mistral': '🌪️',
      'cohere': '💫',
      'huggingface': '🤗',
      'replicate': '🔄',
      'together': '🤝'
    };
    return iconMap[slug] || '⚙️';
  };

  const getHealthStatusColor = (status: string) => {
    switch (status) {
      case 'healthy': return 'text-theme-success';
      case 'unhealthy': return 'text-theme-danger';
      case 'inactive': return 'text-theme-muted';
      default: return 'text-theme-warning';
    }
  };

  const getHealthStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy':
        return <Badge variant="success" size="sm">Healthy</Badge>;
      case 'unhealthy':
        return <Badge variant="danger" size="sm">Unhealthy</Badge>;
      case 'inactive':
        return <Badge variant="secondary" size="sm">Inactive</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getProviderTypeBadge = (type: string) => {
    const typeMap: Record<string, { label: string; variant: 'default' | 'secondary' | 'outline' }> = {
      'text_generation': { label: 'Text', variant: 'default' },
      'image_generation': { label: 'Image', variant: 'secondary' },
      'code_execution': { label: 'Code', variant: 'outline' },
      'embedding': { label: 'Embedding', variant: 'outline' },
      'multimodal': { label: 'Multimodal', variant: 'default' }
    };
    
    const config = typeMap[type] || { label: type, variant: 'outline' as const };
    return <Badge variant={config.variant} size="sm">{config.label}</Badge>;
  };

  const dropdownItems = [
    {
      icon: Eye,
      label: 'View Details',
      onClick: () => onViewDetails(provider.id)
    },
    {
      icon: TestTube,
      label: 'Test Connection',
      onClick: handleTestConnection,
      disabled: testing || (provider.credential_count ?? 0) === 0
    },
    ...(canManage ? [
      {
        icon: Edit,
        label: 'Edit Settings',
        onClick: () => onEditProvider?.(provider.id)
      },
      {
        icon: Key,
        label: 'Manage Credentials',
        onClick: () => onEditProvider?.(provider.id)
      },
      {
        icon: RefreshCw,
        label: 'Sync Models',
        onClick: handleSyncModels,
        disabled: syncing
      },
      {
        icon: Trash2,
        label: 'Delete Provider',
        onClick: () => {
          if (window.confirm(`Are you sure you want to delete ${provider.name}? This action cannot be undone.`)) {
            // TODO: Implement delete handler
            addNotification({
              type: 'info',
              title: 'Delete Provider',
              message: 'Provider deletion will be implemented soon'
            });
          }
        },
        danger: true
      }
    ] : [])
  ];

  return (
    <Card className="p-6 hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <Avatar className="h-10 w-10">
            <span className="text-lg">{getProviderIcon(provider.slug)}</span>
          </Avatar>
          
          <div>
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-theme-text-primary">{provider.name}</h3>
              {provider.priority_order <= 3 && (
                <Star className="h-4 w-4 text-yellow-500 fill-current" />
              )}
            </div>
            
            <div className="flex items-center gap-2 mt-1">
              {getProviderTypeBadge(provider.provider_type)}
              {getHealthStatusBadge(provider.health_status)}
            </div>
          </div>
        </div>

        <DropdownMenu
          trigger={
            <Button variant="ghost" size="sm">
              <MoreVertical className="h-4 w-4" />
            </Button>
          }
          items={dropdownItems}
        />
      </div>

      <p className="text-sm text-theme-text-secondary mb-4 line-clamp-2">
        {provider.description}
      </p>

      {/* Capabilities */}
      <div className="mb-4">
        <p className="text-xs font-medium text-theme-text-tertiary mb-2">CAPABILITIES</p>
        <div className="flex flex-wrap gap-1">
          {provider.capabilities.slice(0, 4).map((capability) => (
            <Badge key={capability} variant="outline" size="xs">
              {capability.replace('_', ' ')}
            </Badge>
          ))}
          {provider.capabilities.length > 4 && (
            <Badge variant="outline" size="xs">
              +{provider.capabilities.length - 4} more
            </Badge>
          )}
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-3 gap-4 mb-4">
        <div className="text-center">
          <p className="text-lg font-semibold text-theme-text-primary">{provider.model_count ?? 0}</p>
          <p className="text-xs text-theme-text-tertiary">Models</p>
        </div>

        <div className="text-center">
          <p className="text-lg font-semibold text-theme-text-primary">{provider.credential_count ?? 0}</p>
          <p className="text-xs text-theme-text-tertiary">Credentials</p>
        </div>

        <div className="text-center">
          <p className="text-lg font-semibold text-theme-text-primary">#{provider.priority_order ?? 0}</p>
          <p className="text-xs text-theme-text-tertiary">Priority</p>
        </div>
      </div>

      {/* Action Buttons */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {provider.documentation_url && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => window.open(provider.documentation_url, '_blank')}
              className="flex items-center gap-1"
            >
              <ExternalLink className="h-3 w-3" />
              Docs
            </Button>
          )}
          
          {provider.status_url && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => window.open(provider.status_url, '_blank')}
              className="flex items-center gap-1"
            >
              <AlertCircle className="h-3 w-3" />
              Status
            </Button>
          )}
        </div>

        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => onViewDetails(provider.id)}
            className="flex items-center gap-1"
          >
            <Eye className="h-3 w-3" />
            Details
          </Button>

          {(provider.credential_count ?? 0) > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={handleTestConnection}
              disabled={testing}
              className="flex items-center gap-1"
            >
              <Zap className={`h-3 w-3 ${testing ? 'animate-pulse' : ''}`} />
              {testing ? 'Testing...' : 'Test'}
            </Button>
          )}

          <Button
            variant="secondary"
            size="sm"
            className="flex items-center gap-1"
            onClick={() => onEditProvider?.(provider.id)}
          >
            <Settings className="h-3 w-3" />
            Edit Settings
          </Button>
        </div>
      </div>

      {/* Status Indicators */}
      {(!provider.is_active || provider.health_status === 'unhealthy') && (
        <div className="mt-4 p-3 bg-theme-surface-secondary rounded-lg border border-theme-border">
          <div className="flex items-center gap-2">
            <AlertCircle className={`h-4 w-4 ${getHealthStatusColor(provider.health_status)}`} />
            <span className="text-sm text-theme-text-secondary">
              {!provider.is_active 
                ? 'Provider is currently inactive'
                : 'Provider health check failed'
              }
            </span>
          </div>
        </div>
      )}

      {(provider.credential_count ?? 0) === 0 && (
        <div className="mt-4 p-3 bg-yellow-50 rounded-lg border border-yellow-200">
          <div className="flex items-center gap-2">
            <AlertCircle className="h-4 w-4 text-theme-warning" />
            <span className="text-sm text-yellow-800">
              No credentials configured. Add credentials to start using this provider.
            </span>
          </div>
        </div>
      )}
    </Card>
  );
};
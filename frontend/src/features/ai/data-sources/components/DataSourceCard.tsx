import React, { useState, useRef } from 'react';
import {
  Database,
  Zap,
  AlertCircle,
  ExternalLink,
  MoreVertical,
  Edit,
  Trash2,
  TestTube,
  Eye,
  Key,
  ShieldCheck,
  Circle
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { EntityLink } from '@/shared/components/entity';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { humanizeSourceType } from './sourceTypeLabels';
import type { AiDataSource } from '@/shared/types/ai';

interface DataSourceCardProps {
  dataSource: AiDataSource;
  onUpdate: () => void;
  canManage: boolean;
  onViewDetails: (dataSourceId: string) => void;
  onEditDataSource?: (dataSourceId: string) => void;
}

export const DataSourceCard: React.FC<DataSourceCardProps> = ({
  dataSource,
  onUpdate,
  canManage,
  onViewDetails,
  onEditDataSource
}) => {
  const [testing, setTesting] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const { addNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const testingRef = useRef(false);

  const handleDeleteDataSource = () => {
    confirm({
      title: 'Delete Data Source',
      message: `Are you sure you want to delete "${dataSource.name}"? This action cannot be undone and will remove all associated credentials.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          setDeleting(true);
          await dataSourcesApi.deleteDataSource(dataSource.id);
          addNotification({
            type: 'success',
            title: 'Data Source Deleted',
            message: `${dataSource.name} has been deleted successfully`
          });
          onUpdate();
        } catch (_error) {
          addNotification({
            type: 'error',
            title: 'Delete Failed',
            message: 'Failed to delete data source. Please try again.'
          });
        } finally {
          setDeleting(false);
        }
      }
    });
  };

  const handleTestConnection = async () => {
    if (testingRef.current) return;
    testingRef.current = true;

    try {
      setTesting(true);
      const response = await dataSourcesApi.testConnection(dataSource.id);

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
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Test Failed',
        message: 'Failed to test data source connection'
      });
    } finally {
      setTesting(false);
      testingRef.current = false;
    }
  };

  const getSourceTypeLabel = (type: string): string => humanizeSourceType(type);

  const getHealthStatusBadge = (status: string) => {
    switch (status) {
      case 'healthy':
        return <Badge variant="success" size="sm">Healthy</Badge>;
      case 'degraded':
        return <Badge variant="warning" size="sm">Degraded</Badge>;
      case 'critical':
        return <Badge variant="danger" size="sm">Critical</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getHealthStatusColor = (status: string) => {
    switch (status) {
      case 'healthy': return 'text-theme-success-fg';
      case 'degraded': return 'text-theme-warning-fg';
      case 'critical': return 'text-theme-danger-fg';
      default: return 'text-theme-tertiary';
    }
  };

  // Trust/effectiveness badge — only rendered once the backend serializer
  // surfaces effectiveness_score (Phase 2 rollout). Tier thresholds mirror the
  // effectiveness gauges used across the skills UI.
  const effectivenessScore =
    typeof dataSource.effectiveness_score === 'number' ? dataSource.effectiveness_score : null;

  const getEffectivenessTier = (
    score: number
  ): { variant: 'success' | 'info' | 'warning' | 'danger'; label: string } => {
    if (score >= 0.8) return { variant: 'success', label: 'Trusted' };
    if (score >= 0.6) return { variant: 'info', label: 'Reliable' };
    if (score >= 0.4) return { variant: 'warning', label: 'Fair' };
    return { variant: 'danger', label: 'Low Trust' };
  };

  const effectivenessTier = effectivenessScore !== null ? getEffectivenessTier(effectivenessScore) : null;
  const effectivenessPct = effectivenessScore !== null ? Math.round(effectivenessScore * 100) : null;

  const getSourceTypeIcon = (type: string): string => {
    const iconMap: Record<string, string> = {
      'noaa_ncei': '🌡️',
      'noaa_gfs': '🌤️',
      'noaa_observations': '📡',
      'open_meteo': '☁️',
      'custom': '🔧'
    };
    return iconMap[type] || '📊';
  };

  const dropdownItems = [
    {
      icon: Eye,
      label: 'View Details',
      onClick: () => onViewDetails(dataSource.id)
    },
    {
      icon: TestTube,
      label: 'Test Connection',
      onClick: handleTestConnection,
      disabled: testing || (dataSource.credential_count ?? 0) === 0
    },
    ...(canManage ? [
      {
        icon: Edit,
        label: 'Edit Settings',
        onClick: () => onEditDataSource?.(dataSource.id)
      },
      {
        icon: Key,
        label: 'Manage Credentials',
        onClick: () => onEditDataSource?.(dataSource.id)
      },
      {
        icon: Trash2,
        label: deleting ? 'Deleting...' : 'Delete Data Source',
        onClick: handleDeleteDataSource,
        disabled: deleting,
        danger: true
      }
    ] : [])
  ];

  // Calculate max quota utilization for progress bar
  const quotaUtilization = dataSource.quota?.utilization;
  const maxUtilization = quotaUtilization
    ? Math.max(
        quotaUtilization.minute_pct ?? 0,
        quotaUtilization.hour_pct ?? 0,
        quotaUtilization.day_pct ?? 0
      )
    : null;

  return (
    <Card className="p-6 hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 bg-theme-surface-secondary rounded-lg flex items-center justify-center">
            <span className="text-lg">{getSourceTypeIcon(dataSource.source_type)}</span>
          </div>

          <div>
            <div className="flex items-center gap-2">
              {/* Health indicator dot — quick at-a-glance status next to the name */}
              <Circle
                className={`h-2.5 w-2.5 shrink-0 fill-current ${getHealthStatusColor(dataSource.health_status)}`}
                aria-label={`Health: ${dataSource.health_status}`}
              />
              <h3 className="font-semibold text-theme-primary">
                <EntityLink type="data_source" id={dataSource.id} label={dataSource.name} />
              </h3>
              {!dataSource.is_active && (
                <Badge variant="secondary" size="sm">Inactive</Badge>
              )}
            </div>

            <div className="flex flex-wrap items-center gap-2 mt-1">
              <Badge variant="outline" size="sm">{getSourceTypeLabel(dataSource.source_type)}</Badge>
              {dataSource.category && (
                <Badge variant="secondary" size="sm" className="capitalize">{dataSource.category}</Badge>
              )}
              {getHealthStatusBadge(dataSource.health_status)}
              {effectivenessTier && effectivenessPct !== null && (
                <span title={`Effectiveness score: ${effectivenessPct}%`}>
                  <Badge variant={effectivenessTier.variant} size="sm" className="inline-flex items-center gap-1">
                    <ShieldCheck className="h-3 w-3" />
                    {effectivenessTier.label} · {effectivenessPct}%
                  </Badge>
                </span>
              )}
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

      <p className="text-sm text-theme-secondary mb-4 line-clamp-2">
        {dataSource.description}
      </p>

      {/* Capabilities */}
      {(dataSource.capabilities ?? []).length > 0 && (
        <div className="mb-4">
          <p className="text-xs font-medium text-theme-tertiary mb-2">CAPABILITIES</p>
          <div className="flex flex-wrap gap-1">
            {(dataSource.capabilities ?? []).slice(0, 4).map((capability) => (
              <Badge key={capability} variant="outline" size="xs">
                {capability.replace(/_/g, ' ')}
              </Badge>
            ))}
            {(dataSource.capabilities?.length ?? 0) > 4 && (
              <Badge variant="outline" size="xs">
                +{(dataSource.capabilities?.length ?? 0) - 4} more
              </Badge>
            )}
          </div>
        </div>
      )}

      {/* Stats Grid */}
      <div className="grid grid-cols-3 gap-4 mb-4">
        <div className="text-center">
          <p className="text-lg font-semibold text-theme-primary">{dataSource.credential_count ?? 0}</p>
          <p className="text-xs text-theme-tertiary">Credentials</p>
        </div>

        <div className="text-center">
          <p className="text-lg font-semibold text-theme-primary">#{dataSource.priority_order ?? 0}</p>
          <p className="text-xs text-theme-tertiary">Priority</p>
        </div>

        <div className="text-center">
          <p className="text-lg font-semibold text-theme-primary">
            {dataSource.requires_auth ? 'Yes' : 'No'}
          </p>
          <p className="text-xs text-theme-tertiary">Auth Required</p>
        </div>
      </div>

      {/* Quota Usage Bar */}
      {maxUtilization !== null && maxUtilization > 0 && (
        <div className="mb-4">
          <div className="flex items-center justify-between mb-1">
            <p className="text-xs text-theme-tertiary">Quota Usage</p>
            <p className="text-xs text-theme-tertiary">{Math.round(maxUtilization)}%</p>
          </div>
          <div className="w-full bg-theme-surface-secondary rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all ${
                maxUtilization > 90 ? 'bg-theme-danger-bg' :
                maxUtilization > 70 ? 'bg-theme-warning-bg' :
                'bg-theme-success-bg'
              }`}
              style={{ width: `${Math.min(maxUtilization, 100)}%` }}
            />
          </div>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {dataSource.documentation_url && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => window.open(dataSource.documentation_url, '_blank')}
              className="flex items-center gap-1"
            >
              <ExternalLink className="h-3 w-3" />
              Docs
            </Button>
          )}
        </div>

        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => onViewDetails(dataSource.id)}
            className="flex items-center gap-1"
          >
            <Eye className="h-3 w-3" />
            Details
          </Button>

          {(dataSource.credential_count ?? 0) > 0 && (
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

          {canManage && (
            <Button
              variant="secondary"
              size="sm"
              className="flex items-center gap-1"
              onClick={() => onEditDataSource?.(dataSource.id)}
            >
              <Database className="h-3 w-3" />
              Edit
            </Button>
          )}
        </div>
      </div>

      {/* Status Indicators */}
      {(!dataSource.is_active || dataSource.health_status === 'critical') && (
        <div className="mt-4 p-3 bg-theme-surface-secondary rounded-lg border border-theme">
          <div className="flex items-center gap-2">
            <AlertCircle className={`h-4 w-4 ${getHealthStatusColor(dataSource.health_status)}`} />
            <span className="text-sm text-theme-secondary">
              {!dataSource.is_active
                ? 'Data source is currently inactive'
                : 'Data source health check is critical'
              }
            </span>
          </div>
        </div>
      )}

      {(dataSource.credential_count ?? 0) === 0 && dataSource.requires_auth && (
        <div className="mt-4 p-3 bg-theme-warning-fg/10 rounded-lg border border-theme-warning-border/30">
          <div className="flex items-center gap-2">
            <AlertCircle className="h-4 w-4 text-theme-warning-fg" />
            <span className="text-sm text-theme-warning-fg">
              No credentials configured. Add credentials to start using this data source.
            </span>
          </div>
        </div>
      )}
      {ConfirmationDialog}
    </Card>
  );
};

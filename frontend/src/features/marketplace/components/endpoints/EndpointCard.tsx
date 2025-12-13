
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { AppEndpoint } from '../../types';
import { getHttpMethodThemeClass } from '../../utils/themeHelpers';
import { Settings, Play, Pause, TestTube, BarChart } from 'lucide-react';

interface EndpointCardProps {
  endpoint: AppEndpoint;
  onEdit?: (endpoint: AppEndpoint) => void;
  onToggleStatus?: (endpoint: AppEndpoint) => void;
  onTest?: (endpoint: AppEndpoint) => void;
  onViewAnalytics?: (endpoint: AppEndpoint) => void;
}

export const EndpointCard: React.FC<EndpointCardProps> = ({
  endpoint,
  onEdit,
  onToggleStatus,
  onTest,
  onViewAnalytics
}) => {
  return (
    <Card className="p-6">
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <div className="flex items-center space-x-3 mb-2">
            <Badge className={getHttpMethodThemeClass(endpoint.http_method)}>
              {endpoint.http_method}
            </Badge>
            <h3 className="font-semibold text-theme-primary">{endpoint.name}</h3>
            <Badge variant={endpoint.is_active ? 'success' : 'secondary'}>
              {endpoint.is_active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          
          <div className="text-sm text-theme-secondary font-mono bg-theme-surface px-3 py-1 rounded mb-2">
            {endpoint.full_path}
          </div>
          
          {endpoint.description && (
            <p className="text-theme-secondary text-sm mb-3">
              {endpoint.description}
            </p>
          )}
          
          <div className="flex items-center space-x-4 text-sm text-theme-tertiary">
            <span>🔒 {endpoint.requires_auth ? 'Auth Required' : 'Public'}</span>
            <span>📝 v{endpoint.version}</span>
            {endpoint.analytics && (
              <span>📊 {endpoint.analytics.total_calls} calls</span>
            )}
          </div>
        </div>

        <div className="flex items-center space-x-2">
          {onViewAnalytics && endpoint.analytics && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onViewAnalytics(endpoint)}
              title="View Analytics"
            >
              <BarChart className="w-4 h-4" />
            </Button>
          )}
          
          {onTest && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onTest(endpoint)}
              title="Test Endpoint"
            >
              <TestTube className="w-4 h-4" />
            </Button>
          )}
          
          {onToggleStatus && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onToggleStatus(endpoint)}
              title={endpoint.is_active ? 'Deactivate' : 'Activate'}
            >
              {endpoint.is_active ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
            </Button>
          )}
          
          {onEdit && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onEdit(endpoint)}
              title="Edit Endpoint"
            >
              <Settings className="w-4 h-4" />
            </Button>
          )}
        </div>
      </div>

      {endpoint.analytics && (
        <div className="pt-4 border-t border-theme">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <div className="text-theme-tertiary">Success Rate</div>
              <div className="font-semibold text-theme-success">
                {endpoint.analytics.success_rate.toFixed(1)}%
              </div>
            </div>
            <div>
              <div className="text-theme-tertiary">Avg Response</div>
              <div className="font-semibold text-theme-primary">
                {endpoint.analytics.average_response_time.toFixed(0)}ms
              </div>
            </div>
            <div>
              <div className="text-theme-tertiary">24h Calls</div>
              <div className="font-semibold text-theme-primary">
                {endpoint.analytics.calls_last_24h}
              </div>
            </div>
            <div>
              <div className="text-theme-tertiary">Error Rate</div>
              <div className="font-semibold text-theme-error">
                {endpoint.analytics.error_rate.toFixed(1)}%
              </div>
            </div>
          </div>
        </div>
      )}
    </Card>
  );
};
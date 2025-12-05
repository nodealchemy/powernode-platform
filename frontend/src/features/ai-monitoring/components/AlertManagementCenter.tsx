import React, { useState } from 'react';
import {
  AlertTriangle,
  Bell,
  Check,
  CheckCircle,
  Filter,
  RefreshCw,
  XCircle
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Modal } from '@/shared/components/ui/Modal';
import { Loading } from '@/shared/components/ui/Loading';
import { Alert } from '@/shared/types/monitoring';

interface AlertManagementCenterProps {
  alerts: Alert[];
  isLoading: boolean;
  canManageAlerts: boolean;
  onRefresh: () => void;
  onAcknowledgeAlert: (alertId: string, note?: string) => void;
  onResolveAlert: (alertId: string, note?: string) => void;
}

export const AlertManagementCenter: React.FC<AlertManagementCenterProps> = ({
  alerts,
  isLoading,
  canManageAlerts,
  onRefresh,
  onAcknowledgeAlert,
  onResolveAlert
}) => {
  const [selectedAlert, setSelectedAlert] = useState<Alert | null>(null);
  const [actionType, setActionType] = useState<'acknowledge' | 'resolve' | null>(null);
  const [note, setNote] = useState('');
  const [severityFilter, setSeverityFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('active');

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'text-theme-error';
      case 'high': return 'text-theme-error';
      case 'medium': return 'text-theme-warning';
      case 'low': return 'text-theme-info';
      default: return 'text-theme-muted';
    }
  };

  const getSeverityBadge = (severity: string) => {
    switch (severity) {
      case 'critical': return 'danger';
      case 'high': return 'danger';
      case 'medium': return 'warning';
      case 'low': return 'info';
      default: return 'outline';
    }
  };

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'critical':
      case 'high':
        return <XCircle className="h-4 w-4" />;
      case 'medium':
        return <AlertTriangle className="h-4 w-4" />;
      case 'low':
        return <Bell className="h-4 w-4" />;
      default:
        return <Bell className="h-4 w-4" />;
    }
  };

  const filteredAlerts = alerts.filter(alert => {
    const severityMatch = severityFilter === 'all' || alert.severity === severityFilter;
    const statusMatch = (
      statusFilter === 'all' ||
      (statusFilter === 'active' && !alert.resolved && !alert.acknowledged) ||
      (statusFilter === 'acknowledged' && alert.acknowledged && !alert.resolved) ||
      (statusFilter === 'resolved' && alert.resolved)
    );
    return severityMatch && statusMatch;
  });

  const handleAction = (alert: Alert, type: 'acknowledge' | 'resolve') => {
    setSelectedAlert(alert);
    setActionType(type);
    setNote('');
  };

  const confirmAction = () => {
    if (!selectedAlert || !actionType) return;

    if (actionType === 'acknowledge') {
      onAcknowledgeAlert(selectedAlert.id, note || undefined);
    } else {
      onResolveAlert(selectedAlert.id, note || undefined);
    }

    setSelectedAlert(null);
    setActionType(null);
    setNote('');
  };

  const closeModal = () => {
    setSelectedAlert(null);
    setActionType(null);
    setNote('');
  };

  if (isLoading && alerts.length === 0) {
    return (
      <Card>
        <CardHeader title="Alert Management" />
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="lg" message="Loading alerts..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header & Controls */}
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium text-theme-primary">Alert Management Center</h3>
        <Button
          onClick={onRefresh}
          variant="outline"
          size="sm"
          disabled={isLoading}
        >
          <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4 p-4 bg-theme-surface rounded-lg border border-theme-border">
        <div className="flex items-center gap-2">
          <Filter className="h-4 w-4 text-theme-muted" />
          <span className="text-sm text-theme-muted">Filters:</span>
        </div>
        
        <Select
          value={severityFilter}
          onValueChange={setSeverityFilter}
        >
          <option value="all">All Severities</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </Select>

        <Select
          value={statusFilter}
          onValueChange={setStatusFilter}
        >
          <option value="all">All Status</option>
          <option value="active">Active</option>
          <option value="acknowledged">Acknowledged</option>
          <option value="resolved">Resolved</option>
        </Select>

        <div className="ml-auto text-sm text-theme-muted">
          Showing {filteredAlerts.length} of {alerts.length} alerts
        </div>
      </div>

      {/* Alerts List */}
      <div className="space-y-3">
        {filteredAlerts.map((alert) => (
          <Card key={alert.id} className={`${
            alert.severity === 'critical' ? 'border-theme-error' :
            alert.severity === 'high' ? 'border-theme-error' :
            alert.severity === 'medium' ? 'border-theme-warning' :
            'border-theme-border'
          }`}>
            <CardContent className="p-4">
              <div className="flex items-start gap-3">
                {/* Severity Icon */}
                <div className={`p-2 rounded-full ${alert.severity === 'critical' || alert.severity === 'high' ? 'bg-theme-error/10' : alert.severity === 'medium' ? 'bg-theme-warning/10' : 'bg-theme-info/10'}`}>
                  <div className={getSeverityColor(alert.severity)}>
                    {getSeverityIcon(alert.severity)}
                  </div>
                </div>

                {/* Alert Content */}
                <div className="flex-1 space-y-2">
                  <div className="flex items-start justify-between">
                    <div>
                      <h4 className="font-medium text-theme-primary">{alert.title}</h4>
                      <p className="text-sm text-theme-muted mt-1">{alert.message}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant={getSeverityBadge(alert.severity)}>
                        {alert.severity}
                      </Badge>
                      {alert.acknowledged && (
                        <Badge variant="info">Acknowledged</Badge>
                      )}
                      {alert.resolved && (
                        <Badge variant="success">Resolved</Badge>
                      )}
                    </div>
                  </div>

                  {/* Alert Metadata */}
                  <div className="flex items-center gap-4 text-xs text-theme-muted">
                    <span>Component: {alert.component}</span>
                    <span>•</span>
                    <span>Created: {new Date(alert.created_at).toLocaleString()}</span>
                    {alert.acknowledged && alert.acknowledged_at && (
                      <>
                        <span>•</span>
                        <span>Acknowledged: {new Date(alert.acknowledged_at).toLocaleString()}</span>
                      </>
                    )}
                    {alert.resolved && alert.resolved_at && (
                      <>
                        <span>•</span>
                        <span>Resolved: {new Date(alert.resolved_at).toLocaleString()}</span>
                      </>
                    )}
                  </div>

                  {/* Actions */}
                  {canManageAlerts && !alert.resolved && (
                    <div className="flex items-center gap-2 pt-2">
                      {!alert.acknowledged && (
                        <Button
                          onClick={() => handleAction(alert, 'acknowledge')}
                          variant="outline"
                          size="sm"
                        >
                          <Check className="h-4 w-4 mr-1" />
                          Acknowledge
                        </Button>
                      )}
                      <Button
                        onClick={() => handleAction(alert, 'resolve')}
                        variant="outline"
                        size="sm"
                      >
                        <CheckCircle className="h-4 w-4 mr-1" />
                        Resolve
                      </Button>
                    </div>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {filteredAlerts.length === 0 && !isLoading && (
        <Card>
          <CardContent className="py-8 text-center">
            <Bell className="h-12 w-12 text-theme-muted mx-auto mb-4" />
            <p className="text-theme-muted">
              {alerts.length === 0 ? 'No alerts found' : 'No alerts match the selected filters'}
            </p>
          </CardContent>
        </Card>
      )}

      {/* Action Modal */}
      {selectedAlert && actionType && (
        <Modal
          isOpen={true}
          onClose={closeModal}
          title={`${actionType === 'acknowledge' ? 'Acknowledge' : 'Resolve'} Alert`}
        >
          <div className="space-y-4">
            <div className="p-4 bg-theme-surface rounded border border-theme-border">
              <h4 className="font-medium text-theme-primary mb-2">{selectedAlert.title}</h4>
              <p className="text-sm text-theme-muted">{selectedAlert.message}</p>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium text-theme-primary">
                {actionType === 'acknowledge' ? 'Acknowledgment' : 'Resolution'} Note (Optional)
              </label>
              <Textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder={`Add a note about this ${actionType}...`}
                rows={3}
              />
            </div>

            <div className="flex items-center justify-end gap-2">
              <Button
                onClick={closeModal}
                variant="outline"
              >
                Cancel
              </Button>
              <Button
                onClick={confirmAction}
                variant={actionType === 'resolve' ? 'primary' : 'outline'}
              >
                {actionType === 'acknowledge' ? 'Acknowledge' : 'Resolve'} Alert
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};
import React, { useState } from 'react';
import { 
  ChevronDown, 
  ChevronRight, 
  Eye, 
  AlertTriangle, 
  Shield, 
  User,
  Clock,
  MapPin,
  Monitor,
  Smartphone,
  ExternalLink
} from 'lucide-react';
import { AuditLog } from '@/features/system/audit-logs/services/auditLogsApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface AuditLogTableProps {
  logs: AuditLog[];
  loading?: boolean;
  onLogSelect?: (log: AuditLog) => void;
  selectedLogId?: string;
}

export const AuditLogTable: React.FC<AuditLogTableProps> = ({
  logs,
  loading = false,
  onLogSelect,
  selectedLogId
}) => {
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());

  const toggleRowExpansion = (logId: string) => {
    const newExpanded = new Set(expandedRows);
    if (newExpanded.has(logId)) {
      newExpanded.delete(logId);
    } else {
      newExpanded.add(logId);
    }
    setExpandedRows(newExpanded);
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'bg-theme-error-background text-theme-error';
      case 'high': return 'bg-theme-error-background text-theme-error';
      case 'medium': return 'bg-theme-warning-background text-theme-warning';
      case 'low': return 'bg-theme-success-background text-theme-success';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'success': return 'bg-theme-success-background text-theme-success';
      case 'warning': return 'bg-theme-warning-background text-theme-warning';
      case 'error': return 'bg-theme-error-background text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getRiskLevelIcon = (level: string) => {
    switch (level) {
      case 'critical': return <AlertTriangle className="w-4 h-4 text-theme-error" />;
      case 'high': return <Shield className="w-4 h-4 text-theme-error" />;
      case 'medium': return <Eye className="w-4 h-4 text-theme-warning" />;
      case 'low': return <User className="w-4 h-4 text-theme-success" />;
      default: return <User className="w-4 h-4 text-theme-secondary" />;
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return {
      date: date.toLocaleDateString(),
      time: date.toLocaleTimeString()
    };
  };

  const formatAction = (action: string) => {
    return action.split('_').map(word => 
      word.charAt(0).toUpperCase() + word.slice(1)
    ).join(' ');
  };

  const getDeviceIcon = (userAgent?: string) => {
    if (!userAgent) return <Monitor className="w-4 h-4" />;
    
    if (userAgent.includes('Mobile') || userAgent.includes('iPhone') || userAgent.includes('Android')) {
      return <Smartphone className="w-4 h-4" />;
    }
    
    return <Monitor className="w-4 h-4" />;
  };

  if (loading) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8">
        <div className="flex justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (logs.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8">
        <div className="text-center">
          <Shield className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Audit Logs Found</h3>
          <p className="text-theme-secondary">
            No audit logs match your current filters. Try adjusting your search criteria.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-theme-background border-b border-theme">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                <div className="flex items-center gap-2">
                  <Shield className="w-4 h-4" />
                  Event
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                <div className="flex items-center gap-2">
                  <User className="w-4 h-4" />
                  User
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                <div className="flex items-center gap-2">
                  <Clock className="w-4 h-4" />
                  Time
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                Source
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                Status
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                Risk
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {logs.map((log) => {
              const isExpanded = expandedRows.has(log.id);
              const isSelected = selectedLogId === log.id;
              const formatted = formatDate(log.created_at);
              
              return (
                <React.Fragment key={log.id}>
                  <tr 
                    className={`hover:bg-theme-surface-hover transition-colors duration-200 ${
                      isSelected ? 'bg-theme-interactive-primary bg-opacity-5' : ''
                    }`}
                  >
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <button
                          onClick={() => toggleRowExpansion(log.id)}
                          className="text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                        >
                          {isExpanded ? (
                            <ChevronDown className="w-4 h-4" />
                          ) : (
                            <ChevronRight className="w-4 h-4" />
                          )}
                        </button>
                        
                        <div className="flex items-center gap-2">
                          {getRiskLevelIcon(log.level)}
                          <div>
                            <div className="font-medium text-theme-primary text-sm">
                              {formatAction(log.action)}
                            </div>
                            <div className="text-xs text-theme-secondary">
                              {log.resource_type}#{log.resource_id}
                            </div>
                          </div>
                        </div>
                      </div>
                    </td>
                    
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        {getDeviceIcon(log.user_agent)}
                        <div>
                          <div className="text-sm font-medium text-theme-primary">
                            {log.user?.email || 'System'}
                          </div>
                          {log.user?.full_name && (
                            <div className="text-xs text-theme-secondary">
                              {log.user.full_name}
                            </div>
                          )}
                        </div>
                      </div>
                    </td>
                    
                    <td className="px-4 py-3">
                      <div className="text-sm text-theme-primary">{formatted.time}</div>
                      <div className="text-xs text-theme-secondary">{formatted.date}</div>
                    </td>
                    
                    <td className="px-4 py-3">
                      <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-background text-theme-primary">
                        {log.source}
                      </span>
                    </td>
                    
                    <td className="px-4 py-3">
                      <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(log.status)}`}>
                        {log.status}
                      </span>
                    </td>
                    
                    <td className="px-4 py-3">
                      <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${getSeverityColor(log.level)}`}>
                        {log.level}
                      </span>
                    </td>
                    
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => onLogSelect?.(log)}
                          className="text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                          title="View Details"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        
                        {log.ip_address && (
                          <div className="flex items-center gap-1 text-xs text-theme-secondary">
                            <MapPin className="w-3 h-3" />
                            <span className="font-mono">{log.ip_address}</span>
                          </div>
                        )}
                      </div>
                    </td>
                  </tr>
                  
                  {/* Expanded Row Content */}
                  {isExpanded && (
                    <tr className="bg-theme-background">
                      <td colSpan={7} className="px-4 py-4">
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          {/* Message and Details */}
                          <div>
                            <h4 className="text-sm font-medium text-theme-primary mb-2">Event Details</h4>
                            <div className="space-y-2 text-sm">
                              <div>
                                <span className="text-theme-secondary">Message:</span>
                                <p className="text-theme-primary">{log.message}</p>
                              </div>
                              
                              {log.account && (
                                <div>
                                  <span className="text-theme-secondary">Account:</span>
                                  <span className="text-theme-primary ml-1">{log.account.name}</span>
                                </div>
                              )}
                              
                              {log.user_agent && (
                                <div>
                                  <span className="text-theme-secondary">User Agent:</span>
                                  <p className="text-theme-primary font-mono text-xs break-all">
                                    {log.user_agent}
                                  </p>
                                </div>
                              )}
                            </div>
                          </div>
                          
                          {/* Metadata */}
                          <div>
                            <h4 className="text-sm font-medium text-theme-primary mb-2">Metadata</h4>
                            <div className="space-y-1 text-sm">
                              {Object.keys(log.metadata).length > 0 ? (
                                Object.entries(log.metadata).map(([key, value]) => (
                                  <div key={key} className="flex justify-between">
                                    <span className="text-theme-secondary">{key}:</span>
                                    <span className="text-theme-primary font-mono text-xs">
                                      {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                                    </span>
                                  </div>
                                ))
                              ) : (
                                <p className="text-theme-tertiary text-xs">No additional metadata</p>
                              )}
                            </div>
                          </div>
                        </div>
                        
                        {/* Actions */}
                        <div className="mt-4 pt-4 border-t border-theme">
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => onLogSelect?.(log)}
                              className="flex items-center gap-1 px-3 py-1 text-xs bg-theme-interactive-primary text-white rounded hover:bg-theme-interactive-primary-hover transition-colors duration-200"
                            >
                              <ExternalLink className="w-3 h-3" />
                              View Full Details
                            </button>
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
};
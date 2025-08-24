import React, { useState } from 'react';
import { 
  Play, 
  Pause, 
  X, 
  ArrowUp, 
  ArrowDown, 
  BarChart3, 
  Settings,
  Calendar,
  DollarSign,
  AlertTriangle,
  CheckCircle
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import type { AppSubscription } from '../services/appSubscriptionsApi';

interface SubscriptionCardProps {
  subscription: AppSubscription;
  onPause?: (id: string, reason?: string) => Promise<void>;
  onResume?: (id: string) => Promise<void>;
  onCancel?: (id: string, reason?: string) => Promise<void>;
  onUpgrade?: (id: string, newPlanId: string) => Promise<void>;
  onDowngrade?: (id: string, newPlanId: string) => Promise<void>;
  onViewUsage?: (id: string) => void;
  onViewAnalytics?: (id: string) => void;
  onConfigure?: (id: string) => void;
  isLoading?: boolean;
  className?: string;
}

export const SubscriptionCard: React.FC<SubscriptionCardProps> = ({
  subscription,
  onPause,
  onResume,
  onCancel,
  onUpgrade,
  onDowngrade,
  onViewUsage,
  onViewAnalytics,
  onConfigure,
  isLoading = false,
  className = ''
}) => {
  const [showActions, setShowActions] = useState(false);

  const getStatusVariant = (status: string) => {
    switch (status) {
      case 'active':
        return 'success';
      case 'paused':
        return 'warning';
      case 'cancelled':
      case 'expired':
        return 'danger';
      default:
        return 'default';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'active':
        return <CheckCircle className="w-4 h-4" />;
      case 'paused':
        return <Pause className="w-4 h-4" />;
      case 'cancelled':
      case 'expired':
        return <AlertTriangle className="w-4 h-4" />;
      default:
        return null;
    }
  };

  const formatDate = (dateString: string | null) => {
    if (!dateString) return 'N/A';
    return new Date(dateString).toLocaleDateString();
  };

  const formatBillingInfo = () => {
    if (!subscription.next_billing_at) return 'One-time payment';
    
    const daysUntilBilling = subscription.days_until_billing;
    if (daysUntilBilling === null || daysUntilBilling === undefined) return 'N/A';
    
    if (daysUntilBilling < 0) {
      return `Overdue by ${Math.abs(daysUntilBilling)} days`;
    } else if (daysUntilBilling === 0) {
      return 'Bills today';
    } else if (daysUntilBilling === 1) {
      return 'Bills tomorrow';
    } else {
      return `Bills in ${daysUntilBilling} days`;
    }
  };

  return (
    <Card className={`p-6 hover:border-theme-interactive-primary transition-colors ${className}`}>
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center space-x-3">
          {subscription.app.icon ? (
            <img 
              src={subscription.app.icon} 
              alt={subscription.app.name}
              className="w-12 h-12 rounded-lg object-cover"
            />
          ) : (
            <div className="w-12 h-12 rounded-lg bg-theme-interactive-primary/10 flex items-center justify-center">
              <span className="text-2xl">{subscription.app.name.charAt(0)}</span>
            </div>
          )}
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">{subscription.app.name}</h3>
            <p className="text-sm text-theme-secondary">{subscription.app_plan.name}</p>
          </div>
        </div>
        
        <div className="flex items-center space-x-2">
          <Badge 
            variant={getStatusVariant(subscription.status)}
            className="flex items-center space-x-1"
          >
            {getStatusIcon(subscription.status)}
            <span className="capitalize">{subscription.status}</span>
          </Badge>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="space-y-2">
          <div className="flex items-center space-x-2 text-sm text-theme-secondary">
            <DollarSign className="w-4 h-4" />
            <span>{subscription.app_plan.formatted_price}/{subscription.app_plan.billing_interval}</span>
          </div>
          <div className="flex items-center space-x-2 text-sm text-theme-secondary">
            <Calendar className="w-4 h-4" />
            <span>Subscribed {formatDate(subscription.subscribed_at)}</span>
          </div>
        </div>
        
        <div className="space-y-2">
          {subscription.next_billing_at && (
            <div className="text-sm text-theme-secondary">
              <strong className="text-theme-primary">{subscription.next_billing_amount || '$0.00'}</strong> - {formatBillingInfo()}
            </div>
          )}
          {subscription.usage_within_limits === false && (
            <div className="flex items-center space-x-1 text-sm text-theme-warning">
              <AlertTriangle className="w-4 h-4" />
              <span>Usage limit exceeded</span>
            </div>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between pt-4 border-t border-theme">
        <div className="flex space-x-2">
          {subscription.status === 'active' && onPause && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onPause(subscription.id)}
              disabled={isLoading}
              className="flex items-center space-x-1"
            >
              <Pause className="w-4 h-4" />
              <span>Pause</span>
            </Button>
          )}
          
          {subscription.status === 'paused' && onResume && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onResume(subscription.id)}
              disabled={isLoading}
              className="flex items-center space-x-1"
            >
              <Play className="w-4 h-4" />
              <span>Resume</span>
            </Button>
          )}
          
          {(subscription.status === 'active' || subscription.status === 'paused') && onCancel && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onCancel(subscription.id)}
              disabled={isLoading}
              className="flex items-center space-x-1 text-theme-error hover:text-theme-error"
            >
              <X className="w-4 h-4" />
              <span>Cancel</span>
            </Button>
          )}
        </div>

        <div className="flex space-x-2">
          {onViewUsage && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onViewUsage(subscription.id)}
              disabled={isLoading}
              title="View Usage"
            >
              <BarChart3 className="w-4 h-4" />
            </Button>
          )}
          
          {onViewAnalytics && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onViewAnalytics(subscription.id)}
              disabled={isLoading}
              title="View Analytics"
            >
              <BarChart3 className="w-4 h-4" />
            </Button>
          )}
          
          {onConfigure && subscription.status === 'active' && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onConfigure(subscription.id)}
              disabled={isLoading}
              title="Configure"
            >
              <Settings className="w-4 h-4" />
            </Button>
          )}
          
          {subscription.status === 'active' && (onUpgrade || onDowngrade) && (
            <div className="relative">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowActions(!showActions)}
                disabled={isLoading}
                title="Plan Management"
              >
                <ArrowUp className="w-4 h-4" />
              </Button>
              
              {showActions && (
                <div className="absolute right-0 top-full mt-2 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                  <div className="p-2 space-y-1">
                    {onUpgrade && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          onUpgrade(subscription.id, 'upgrade-plan-id');
                          setShowActions(false);
                        }}
                        disabled={isLoading}
                        className="w-full justify-start"
                      >
                        <ArrowUp className="w-4 h-4 mr-2" />
                        Upgrade Plan
                      </Button>
                    )}
                    {onDowngrade && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          onDowngrade(subscription.id, 'downgrade-plan-id');
                          setShowActions(false);
                        }}
                        disabled={isLoading}
                        className="w-full justify-start"
                      >
                        <ArrowDown className="w-4 h-4 mr-2" />
                        Downgrade Plan
                      </Button>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </Card>
  );
};
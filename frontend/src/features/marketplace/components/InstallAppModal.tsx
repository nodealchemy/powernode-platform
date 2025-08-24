import React, { useState, useEffect } from 'react';
import { Check, AlertTriangle, DollarSign, Calendar, Settings } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Modal } from '@/shared/components/ui/Modal';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { App, AppPlan } from '../types';
import { useAppPlans } from '../hooks/useAppPlans';
import { useAppSubscriptions } from '../hooks/useAppSubscriptions';

interface InstallAppModalProps {
  isOpen: boolean;
  onClose: () => void;
  app: App | null;
  onInstallSuccess?: (subscriptionId: string) => void;
}

export const InstallAppModal: React.FC<InstallAppModalProps> = ({
InstallAppModal.displayName = 'InstallAppModal';
  isOpen,
  onClose,
  app,
  onInstallSuccess
}) => {
  const [selectedPlan, setSelectedPlan] = useState<AppPlan | null>(null);
  const [configuration, setConfiguration] = useState<Record<string, any>>({});
  const [installing, setInstalling] = useState(false);

  const { plans, loading: plansLoading } = useAppPlans(app?.id, isOpen && !!app?.id);
  const { createSubscription } = useAppSubscriptions(undefined, false);

  // Reset state when modal opens/closes
  useEffect(() => {
    if (!isOpen) {
      setSelectedPlan(null);
      setConfiguration({});
      setInstalling(false);
    }
  }, [isOpen]);

  // Auto-select first available plan
  useEffect(() => {
    if (plans.length > 0 && !selectedPlan) {
      setSelectedPlan(plans[0]);
    }
  }, [plans, selectedPlan]);

  const handleInstall = async () => {
    if (!app || !selectedPlan) return;

    try {
      setInstalling(true);
      const subscription = await createSubscription(app.id, selectedPlan.id, configuration);
      
      if (subscription) {
        onInstallSuccess?.(subscription.id);
        onClose();
      }
    } catch (error) {
      console.error('Failed to install app:', error);
    } finally {
      setInstalling(false);
    }
  };

  const handleConfigurationChange = (key: string, value: any) => {
    setConfiguration(prev => ({
      ...prev,
      [key]: value
    }));
  };

  const getPlanBadgeVariant = (plan: AppPlan) => {
    if (plan.price_cents === 0) return 'success';
    if (plan.is_featured) return 'primary';
    return 'secondary';
  };

  if (!app) return null;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Install ${app.name}`} maxWidth="lg">
      <div className="space-y-6">
        {/* App Info */}
        <div className="flex items-start space-x-4 pb-4 border-b border-theme">
          {app.icon ? (
            <img 
              src={app.icon} 
              alt={app.name}
              className="w-16 h-16 rounded-lg object-cover"
            />
          ) : (
            <div className="w-16 h-16 rounded-lg bg-theme-interactive-primary/10 flex items-center justify-center">
              <span className="text-2xl">{app.name.charAt(0)}</span>
            </div>
          )}
          
          <div className="flex-1">
            <h3 className="text-xl font-bold text-theme-primary mb-2">{app.name}</h3>
            <p className="text-theme-secondary mb-3">{app.description}</p>
            
            <div className="flex flex-wrap gap-2">
              <Badge variant="outline">{app.category}</Badge>
              <Badge variant="secondary">v{app.version}</Badge>
              {app.status === 'published' && (
                <Badge variant="success" className="flex items-center space-x-1">
                  <Check className="w-3 h-3" />
                  <span>Published</span>
                </Badge>
              )}
            </div>
          </div>
        </div>

        {/* Plan Selection */}
        {plansLoading ? (
          <div className="flex justify-center py-8">
            <LoadingSpinner size="lg" />
          </div>
        ) : (
          <div className="space-y-4">
            <h4 className="text-lg font-semibold text-theme-primary">Choose a Plan</h4>
            
            <div className="grid gap-4">
              {plans.map((plan) => (
                <div
                  key={plan.id}
                  onClick={() => setSelectedPlan(plan)}
                  className={`p-4 border-2 rounded-lg cursor-pointer transition-all ${
                    selectedPlan?.id === plan.id
                      ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                      : 'border-theme hover:border-theme-interactive-primary/50'
                  }`}
                >
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center space-x-3">
                      <div className="flex items-center space-x-2">
                        <h5 className="font-semibold text-theme-primary">{plan.name}</h5>
                        <Badge variant={getPlanBadgeVariant(plan)}>
                          {plan.price_cents === 0 ? 'Free' : plan.formatted_price}
                        </Badge>
                      </div>
                    </div>
                    
                    <div className="flex items-center space-x-2 text-sm text-theme-secondary">
                      {plan.price_cents > 0 && (
                        <>
                          <DollarSign className="w-4 h-4" />
                          <span>{plan.formatted_price}</span>
                          <span>/</span>
                          <Calendar className="w-4 h-4" />
                          <span>{plan.billing_interval}</span>
                        </>
                      )}
                    </div>
                  </div>
                  
                  <p className="text-theme-secondary text-sm mb-3">{plan.description}</p>
                  
                  {/* Features */}
                  {plan.features && plan.features.length > 0 && (
                    <div className="space-y-2">
                      <h6 className="text-sm font-medium text-theme-primary">Features:</h6>
                      <div className="flex flex-wrap gap-1">
                        {plan.features.map((feature: string, index: number) => (
                          <Badge key={index} variant="outline" className="text-xs">
                            {feature}
                          </Badge>
                        ))}
                      </div>
                    </div>
                  )}
                  
                  {/* Limits */}
                  {plan.limits && Object.keys(plan.limits).length > 0 && (
                    <div className="mt-3 space-y-1">
                      <h6 className="text-sm font-medium text-theme-primary">Limits:</h6>
                      <div className="text-xs text-theme-secondary space-y-1">
                        {Object.entries(plan.limits).map(([key, value]) => (
                          <div key={key} className="flex justify-between">
                            <span className="capitalize">{key.replace('_', ' ')}:</span>
                            <span>{typeof value === 'number' && value === -1 ? 'Unlimited' : (value as number).toLocaleString()}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Configuration */}
        {selectedPlan && (
          <div className="space-y-4">
            <h4 className="text-lg font-semibold text-theme-primary flex items-center space-x-2">
              <Settings className="w-5 h-5" />
              <span>Configuration</span>
            </h4>
            
            <div className="bg-theme-surface/50 rounded-lg p-4">
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    App Name (optional)
                  </label>
                  <input
                    type="text"
                    placeholder="Custom name for this installation"
                    value={configuration.name || ''}
                    onChange={(e) => handleConfigurationChange('name', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Environment
                  </label>
                  <select
                    value={configuration.environment || 'production'}
                    onChange={(e) => handleConfigurationChange('environment', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  >
                    <option value="production">Production</option>
                    <option value="staging">Staging</option>
                    <option value="development">Development</option>
                  </select>
                </div>
                
                <div className="flex items-center space-x-3">
                  <input
                    type="checkbox"
                    id="auto-updates"
                    checked={configuration.auto_updates !== false}
                    onChange={(e) => handleConfigurationChange('auto_updates', e.target.checked)}
                    className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                  />
                  <label htmlFor="auto-updates" className="text-sm text-theme-primary">
                    Enable automatic updates
                  </label>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Terms and Warnings */}
        {selectedPlan && (
          <div className="space-y-3">
            {selectedPlan.price_cents > 0 && (
              <div className="flex items-start space-x-3 p-3 bg-theme-warning-background border border-theme-warning-border rounded-lg">
                <AlertTriangle className="w-5 h-5 text-theme-warning mt-0.5" />
                <div className="text-sm">
                  <p className="text-theme-warning font-medium mb-1">Billing Information</p>
                  <p className="text-theme-secondary">
                    You will be charged {selectedPlan.formatted_price} {selectedPlan.billing_interval === 'monthly' ? 'every month' : 'every year'}.
                    You can cancel at any time from your subscriptions page.
                  </p>
                </div>
              </div>
            )}
            
            <div className="text-xs text-theme-tertiary">
              By installing this app, you agree to the{' '}
              <button className="text-theme-link hover:underline">Terms of Service</button>
              {' '}and{' '}
              <button className="text-theme-link hover:underline">Privacy Policy</button>.
            </div>
          </div>
        )}

        {/* Actions */}
        <div className="flex space-x-3 pt-4 border-t border-theme">
          <Button variant="outline" onClick={onClose} className="flex-1">
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleInstall}
            disabled={!selectedPlan || installing || plansLoading}
            className="flex-1 flex items-center justify-center space-x-2"
          >
            {installing ? (
              <>
                <LoadingSpinner size="sm" />
                <span>Installing...</span>
              </>
            ) : (
              <>
                <span>Install {selectedPlan?.price_cents === 0 ? 'Free' : `for ${selectedPlan?.formatted_price}`}</span>
              </>
            )}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
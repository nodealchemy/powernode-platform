import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { useNotification } from '@/shared/hooks/useNotification';
import { App } from '../../types';
import { Plus, CreditCard, AlertCircle, Check, Star, CheckCircle } from 'lucide-react';

interface AppSubscriptionModalProps {
  isOpen: boolean;
  onClose: () => void;
  app: App | null;
  onSubscribe?: (app: App, planId?: string) => Promise<void>;
  loading?: boolean;
}

interface ModalPlan {
  id: string;
  name: string;
  price: string;
  billing: string;
  description: string;
  features: string[];
  popular: boolean;
  disabled: boolean;
}

// Mock plans data as fallback
const mockPlans: ModalPlan[] = [
  {
    id: 'free',
    name: 'Free',
    price: '$0',
    billing: 'forever',
    description: 'Perfect for getting started',
    features: [
      'Up to 1,000 API calls/month',
      'Basic webhooks',
      'Community support',
      'Standard features'
    ],
    popular: false,
    disabled: false
  },
  {
    id: 'pro',
    name: 'Professional',
    price: '$29',
    billing: 'per month',
    description: 'For growing businesses',
    features: [
      'Up to 50,000 API calls/month',
      'Advanced webhooks',
      'Priority support',
      'Premium features',
      'Analytics dashboard',
      'Custom integrations'
    ],
    popular: true,
    disabled: false
  },
  {
    id: 'enterprise',
    name: 'Enterprise',
    price: '$99',
    billing: 'per month',
    description: 'For large organizations',
    features: [
      'Unlimited API calls',
      'Advanced webhooks',
      'White-label support',
      'All premium features',
      'Advanced analytics',
      'Custom integrations',
      'Dedicated account manager',
      'SLA guarantee'
    ],
    popular: false,
    disabled: false
  }
];

// Helper function to format app plan data for the modal
const formatAppPlanForModal = (plan: any): ModalPlan => ({
  id: plan.id,
  name: plan.name,
  price: plan.formatted_price || `$${(plan.price_cents / 100).toFixed(2)}`,
  billing: plan.billing_interval || 'per month',
  description: plan.description || 'App subscription plan',
  features: plan.features || ['Full app access', 'API integration', 'Support included'],
  popular: plan.is_popular || false,
  disabled: !plan.is_active
});

export const AppSubscriptionModal: React.FC<AppSubscriptionModalProps> = ({
  isOpen,
  onClose,
  app,
  onSubscribe,
  loading = false
}) => {
  // Use real app plans if available, otherwise fall back to mock plans
  const availablePlans = app?.plans && app.plans.length > 0 
    ? app.plans.filter(plan => plan.is_active).map(formatAppPlanForModal)
    : mockPlans;
    
  const [selectedPlanId, setSelectedPlanId] = useState<string>(availablePlans[0]?.id || 'free');
  const [subscribing, setSubscribing] = useState(false);
  const { showNotification } = useNotification();

  const handleSubscribe = async () => {
    if (!app) return;

    setSubscribing(true);
    try {
      await onSubscribe?.(app, selectedPlanId);
      showNotification(`Successfully subscribed to ${app.name}!`, 'success');
      onClose();
    } catch (error: any) {
      showNotification(error.message || 'Failed to subscribe to app', 'error');
    } finally {
      setSubscribing(false);
    }
  };

  const selectedPlan = availablePlans.find(plan => plan.id === selectedPlanId);

  if (!app) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Subscribe to ${app.name}`}
      maxWidth="2xl"
    >
      <div className="space-y-6">
        {/* App Info */}
        <div className="flex items-center space-x-4 p-4 bg-theme-surface rounded-lg">
          <div className="w-16 h-16 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-2xl">
            {app.icon || '📱'}
          </div>
          <div className="flex-1">
            <h3 className="text-xl font-semibold text-theme-primary">{app.name}</h3>
            <p className="text-theme-secondary">{app.short_description || app.description}</p>
            <div className="flex items-center space-x-2 mt-2">
              <Badge variant="outline">{app.category}</Badge>
              <span className="text-sm text-theme-tertiary">v{app.version}</span>
            </div>
          </div>
        </div>

        {/* Plans */}
        <div>
          <h4 className="text-lg font-semibold text-theme-primary mb-4">Choose Your Plan</h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {availablePlans.map((plan) => (
              <Card
                key={plan.id}
                className={`p-4 sm:p-6 cursor-pointer transition-all duration-200 border-2 ${
                  selectedPlanId === plan.id
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary/10 ring-2 ring-theme-interactive-primary/20'
                    : 'border-theme hover:border-theme-interactive-primary/50'
                } ${plan.popular ? 'ring-2 ring-theme-warning/20' : ''}`}
                onClick={() => setSelectedPlanId(plan.id)}
              >
                <div className="text-center relative">
                  {/* Selection indicator */}
                  {selectedPlanId === plan.id && (
                    <div className="absolute -top-2 -right-2">
                      <CheckCircle className="w-6 h-6 text-theme-success bg-white rounded-full" />
                    </div>
                  )}
                  
                  {plan.popular && (
                    <Badge variant="warning" className="mb-3 flex items-center space-x-1 w-fit mx-auto">
                      <Star className="w-3 h-3" />
                      <span>Most Popular</span>
                    </Badge>
                  )}
                  
                  <h5 className="text-lg font-semibold text-theme-primary mb-2">{plan.name}</h5>
                  <div className="mb-2">
                    <span className="text-3xl font-bold text-theme-primary">{plan.price}</span>
                    {plan.billing !== 'forever' && (
                      <span className="text-theme-secondary">/{plan.billing.split(' ')[1]}</span>
                    )}
                  </div>
                  <p className="text-sm text-theme-secondary mb-4">{plan.description}</p>
                  
                  <ul className="text-sm space-y-2 text-left">
                    {plan.features.map((feature, index) => (
                      <li key={index} className="flex items-center space-x-2">
                        <Check className="w-4 h-4 text-theme-success flex-shrink-0" />
                        <span className="text-theme-secondary">{feature}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </Card>
            ))}
          </div>
        </div>

        {/* Selected Plan Summary */}
        {selectedPlan && (
          <div className="p-4 bg-theme-surface rounded-lg">
            <h5 className="font-semibold text-theme-primary mb-2">Selected Plan: {selectedPlan.name}</h5>
            <div className="flex items-center justify-between">
              <span className="text-theme-secondary">
                You'll be charged {selectedPlan.price} {selectedPlan.billing !== 'forever' ? selectedPlan.billing : ''}
              </span>
              {selectedPlan.id === 'free' && (
                <Badge variant="success">No Payment Required</Badge>
              )}
            </div>
          </div>
        )}

        {/* Terms */}
        <div className="text-sm text-theme-tertiary space-y-2">
          <p className="flex items-start space-x-2">
            <AlertCircle className="w-4 h-4 mt-0.5 text-theme-warning flex-shrink-0" />
            <span>
              By subscribing, you agree to the app's terms of service and privacy policy. 
              You can cancel your subscription at any time.
            </span>
          </p>
        </div>

        {/* Actions */}
        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button variant="outline" onClick={onClose} disabled={subscribing}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSubscribe}
            disabled={subscribing || loading}
            className="flex items-center space-x-2"
          >
            {subscribing ? (
              <>
                <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                <span>Subscribing...</span>
              </>
            ) : selectedPlan?.id === 'free' ? (
              <>
                <Plus className="w-4 h-4" />
                <span>Subscribe for Free</span>
              </>
            ) : (
              <>
                <CreditCard className="w-4 h-4" />
                <span>Subscribe for {selectedPlan?.price}</span>
              </>
            )}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
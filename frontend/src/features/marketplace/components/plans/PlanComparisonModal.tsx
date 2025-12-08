import React, { useState, useMemo } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { App, AppPlan } from '../../types';
import { formatPriceCents, formatBillingInterval, getPriorityBadgeClass } from '../../utils/themeHelpers';
import { Check, X, Star, TrendingUp, Shield, Zap, Users, Crown } from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { getErrorMessage } from '@/shared/utils/errorHandling';

interface PlanComparisonModalProps {
  isOpen: boolean;
  onClose: () => void;
  app: App | null;
  currentUserPlan?: AppPlan | null;
  onSelectPlan: (planId: string) => Promise<void>;
  loading?: boolean;
}

interface ComparisonFeature {
  slug: string;
  name: string;
  description?: string;
  category: string;
  planAvailability: Record<string, boolean | string | number>; // planId -> availability
}

interface PlanHighlight {
  icon: React.ComponentType<{ className?: string }>;
  text: string;
  color: string;
}

const PLAN_HIGHLIGHTS: Record<string, PlanHighlight> = {
  'free': { icon: Star, text: 'Best Value', color: 'text-theme-success' },
  'starter': { icon: TrendingUp, text: 'Most Popular', color: 'text-theme-warning' },
  'pro': { icon: Zap, text: 'Best Features', color: 'text-theme-interactive-primary' },
  'enterprise': { icon: Crown, text: 'Premium', color: 'text-theme-error' },
  'team': { icon: Users, text: 'Team Plan', color: 'text-theme-info' },
  'premium': { icon: Shield, text: 'Pro Choice', color: 'text-theme-success' }
};

export const PlanComparisonModal: React.FC<PlanComparisonModalProps> = ({
  isOpen,
  onClose,
  app,
  currentUserPlan,
  onSelectPlan,
  loading = false
}) => {
  const [selectedPlanId, setSelectedPlanId] = useState<string>('');
  const [subscribing, setSubscribing] = useState(false);
  const { showNotification } = useNotifications();

  const plans = useMemo(() => app?.plans || [], [app?.plans]);
  const activePlans = useMemo(() => plans.filter(plan => plan.is_active), [plans]);

  // Extract and categorize features from all plans
  const comparisonFeatures = useMemo(() => {
    if (!plans.length) return [];

    const featureMap = new Map<string, ComparisonFeature>();

    plans.forEach(plan => {
      // Process features from plan.features array (strings)
      if (plan.features) {
        plan.features.forEach(feature => {
          // feature is a string, so we need to create a slug from it
          const key = feature.toLowerCase().replace(/\s+/g, '-');
          if (!featureMap.has(key)) {
            featureMap.set(key, {
              slug: key,
              name: feature, // feature is the name string
              description: undefined,
              category: 'Features',
              planAvailability: {}
            });
          }
          const featureItem = featureMap.get(key);
          if (featureItem) {
            featureItem.planAvailability[plan.id] = true; // If feature is included in plan, it's available
          }
        });
      }

      // Process limits as features
      if (plan.limits) {
        Object.entries(plan.limits).forEach(([limitKey, limitValue]) => {
          const key = `limit-${limitKey}`;
          if (!featureMap.has(key)) {
            featureMap.set(key, {
              slug: key,
              name: limitKey.charAt(0).toUpperCase() + limitKey.slice(1).replace(/_/g, ' '),
              category: 'Limits',
              planAvailability: {}
            });
          }
          const featureItem = featureMap.get(key);
          if (featureItem) {
            featureItem.planAvailability[plan.id] = limitValue;
          }
        });
      }
    });

    // Group features by category
    const features = Array.from(featureMap.values());
    const grouped = features.reduce((acc, feature) => {
      if (!acc[feature.category]) acc[feature.category] = [];
      acc[feature.category].push(feature);
      return acc;
    }, {} as Record<string, ComparisonFeature[]>);

    return grouped;
  }, [plans]);

  const handlePlanSelect = async () => {
    if (!selectedPlanId) return;

    setSubscribing(true);
    try {
      await onSelectPlan(selectedPlanId);
      showNotification('Successfully subscribed to plan!', 'success');
      onClose();
    } catch (error: unknown) {
      showNotification(getErrorMessage(error) || 'Failed to subscribe to plan', 'error');
    } finally {
      setSubscribing(false);
    }
  };

  const getPlanHighlight = (plan: AppPlan): PlanHighlight | null => {
    const highlight = PLAN_HIGHLIGHTS[plan.slug] || PLAN_HIGHLIGHTS[plan.name.toLowerCase()];
    return highlight || null;
  };

  const renderFeatureValue = (feature: ComparisonFeature, planId: string) => {
    const value = Object.prototype.hasOwnProperty.call(feature.planAvailability, planId) ? feature.planAvailability[planId as keyof typeof feature.planAvailability] : undefined;
    
    if (value === undefined || value === null) {
      return <span className="text-theme-tertiary">—</span>;
    }
    
    if (typeof value === 'boolean') {
      return value ? (
        <Check className="w-5 h-5 text-theme-success" />
      ) : (
        <X className="w-5 h-5 text-theme-error" />
      );
    }
    
    if (typeof value === 'number') {
      if (value === -1 || value === Infinity) {
        return <span className="text-theme-success font-medium">Unlimited</span>;
      }
      return <span className="font-medium text-theme-primary">{value.toLocaleString()}</span>;
    }
    
    return <span className="text-sm text-theme-primary">{String(value)}</span>;
  };

  if (!app) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Compare Plans - ${app.name}`}
      maxWidth="4xl"
      className="max-h-[90vh] overflow-y-auto"
    >
      <div className="space-y-6">
        {/* Plan Overview Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {activePlans.map((plan) => {
            const highlight = getPlanHighlight(plan);
            const isCurrentPlan = currentUserPlan?.id === plan.id;
            const isSelected = selectedPlanId === plan.id;
            
            return (
              <Card
                key={plan.id}
                className={`p-4 cursor-pointer transition-all duration-200 border-2 ${
                  isSelected
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                    : isCurrentPlan
                    ? 'border-theme-success bg-theme-success/5'
                    : 'border-theme hover:border-theme-interactive-primary/50'
                }`}
                onClick={() => setSelectedPlanId(plan.id)}
              >
                <div className="text-center space-y-3">
                  {/* Plan highlight badge */}
                  {highlight && (
                    <div className="flex items-center justify-center">
                      <Badge className={getPriorityBadgeClass('popular')} variant="warning">
                        <highlight.icon className="w-3 h-3 mr-1" />
                        {highlight.text}
                      </Badge>
                    </div>
                  )}
                  
                  {/* Plan name and current plan indicator */}
                  <div>
                    <h3 className="font-semibold text-lg text-theme-primary">{plan.name}</h3>
                    {isCurrentPlan && (
                      <Badge variant="success" className="mt-1">Current Plan</Badge>
                    )}
                  </div>

                  {/* Pricing */}
                  <div className="space-y-1">
                    <div className="text-3xl font-bold text-theme-primary">
                      {formatPriceCents(plan.price_cents)}
                    </div>
                    {plan.price_cents > 0 && (
                      <div className="text-sm text-theme-secondary">
                        {formatBillingInterval(plan.billing_interval)}
                      </div>
                    )}
                  </div>

                  {/* Description */}
                  {plan.description && (
                    <p className="text-sm text-theme-secondary">{plan.description}</p>
                  )}

                  {/* Key features preview */}
                  <div className="space-y-2">
                    <div className="text-xs font-medium text-theme-tertiary uppercase tracking-wide">
                      Key Features
                    </div>
                    <div className="space-y-1">
                      {plan.features?.slice(0, 3).map((feature, index) => (
                        <div key={index} className="flex items-center text-sm text-theme-secondary">
                          <Check className="w-3 h-3 text-theme-success mr-2 flex-shrink-0" />
                          <span>{feature}</span>
                        </div>
                      ))}
                      {(plan.features?.length || 0) > 3 && (
                        <div className="text-xs text-theme-tertiary">
                          +{(plan.features?.length || 0) - 3} more features
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>

        {/* Detailed Feature Comparison Matrix */}
        {Object.keys(comparisonFeatures).length > 0 && (
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-theme-primary">Detailed Feature Comparison</h3>
            
            <div className="overflow-x-auto">
              <table className="w-full border-collapse">
                <thead>
                  <tr className="border-b border-theme">
                    <th className="text-left py-3 px-4 font-medium text-theme-secondary">Feature</th>
                    {activePlans.map((plan) => (
                      <th key={plan.id} className="text-center py-3 px-4 min-w-[120px]">
                        <div className="space-y-1">
                          <div className="font-medium text-theme-primary">{plan.name}</div>
                          <div className="text-xs text-theme-secondary">
                            {formatPriceCents(plan.price_cents)}
                            {plan.price_cents > 0 && (
                              <>/{formatBillingInterval(plan.billing_interval).split(' ')[1]}</>
                            )}
                          </div>
                        </div>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(comparisonFeatures).map(([category, features]) => (
                    <React.Fragment key={category}>
                      {/* Category Header */}
                      <tr>
                        <td
                          colSpan={activePlans.length + 1}
                          className="py-3 px-4 bg-theme-surface font-semibold text-theme-primary border-t border-theme"
                        >
                          {category}
                        </td>
                      </tr>
                      
                      {/* Features in Category */}
                      {features.map((feature) => (
                        <tr key={feature.slug} className="border-b border-theme/50 hover:bg-theme-surface/50">
                          <td className="py-3 px-4">
                            <div>
                              <div className="font-medium text-theme-primary">{feature.name}</div>
                              {feature.description && (
                                <div className="text-sm text-theme-secondary mt-1">{feature.description}</div>
                              )}
                            </div>
                          </td>
                          {activePlans.map((plan) => (
                            <td key={`${feature.slug}-${plan.id}`} className="py-3 px-4 text-center">
                              {renderFeatureValue(feature, plan.id)}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </React.Fragment>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* Action Buttons */}
        <div className="flex items-center justify-between pt-4 border-t border-theme">
          <div className="text-sm text-theme-secondary">
            {selectedPlanId ? (
              <>
                Selected: <span className="font-medium text-theme-primary">
                  {activePlans.find(p => p.id === selectedPlanId)?.name}
                </span>
              </>
            ) : (
              'Select a plan to continue'
            )}
          </div>

          <div className="flex items-center space-x-3">
            <Button variant="outline" onClick={onClose} disabled={subscribing}>
              Compare Later
            </Button>
            <Button
              variant="primary"
              onClick={handlePlanSelect}
              disabled={!selectedPlanId || subscribing || loading}
              className="flex items-center space-x-2"
            >
              {subscribing ? (
                <>
                  <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  <span>Processing...</span>
                </>
              ) : (
                <>
                  <TrendingUp className="w-4 h-4" />
                  <span>Select Plan</span>
                </>
              )}
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  );
};
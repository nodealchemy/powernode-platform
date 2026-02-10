import React from 'react';
import { useNavigate } from 'react-router-dom';
import { CheckIcon, XMarkIcon } from '@heroicons/react/24/outline';
import { Plan } from '@/features/business/plans/services/plansApi';

interface PlanComparisonModalProps {
  isOpen: boolean;
  onClose: () => void;
  plansToCompare: string[];
  availablePlans: Plan[];
  billingCycle: 'monthly' | 'yearly';
  calculatePlanPrice: (plan: Plan, cycle: 'monthly' | 'yearly') => string;
  getMonthlyPrice: (plan: Plan) => string;
  getAllPlanFeatures: () => string[];
  planHasFeature: (plan: Plan, feature: string) => boolean;
}

export const PlanComparisonModal: React.FC<PlanComparisonModalProps> = ({
  isOpen,
  onClose,
  plansToCompare,
  availablePlans,
  billingCycle,
  calculatePlanPrice,
  getMonthlyPrice,
  getAllPlanFeatures,
  planHasFeature
}) => {
  const navigate = useNavigate();

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 flex items-center justify-center p-4 z-50">
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-0 animate-in fade-in duration-300" onClick={onClose} />
      {/* Modal */}
      <div className="relative z-10 bg-theme-surface rounded-2xl shadow-2xl max-w-6xl w-full max-h-[90vh] overflow-hidden border border-theme animate-in slide-in-from-bottom-4 duration-300">
        {/* Modal Header */}
        <div className="px-8 py-6 border-b border-theme bg-theme-background-secondary">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-2xl font-bold text-theme-primary">Compare Plans</h3>
              <p className="text-sm text-theme-secondary mt-1">Side-by-side feature comparison</p>
            </div>
            <button
              onClick={onClose}
              className="w-10 h-10 rounded-xl bg-theme-surface border border-theme flex items-center justify-center text-theme-tertiary hover:text-theme-primary transition-all duration-200 hover:shadow-md"
            >
              <XMarkIcon className="h-5 w-5" />
            </button>
          </div>
        </div>

        {/* Comparison Content */}
        <div className="overflow-auto max-h-[calc(90vh-80px)]">
          <div className="p-6">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr>
                    <th className="text-left py-3 px-4 font-medium text-theme-primary w-1/4">Features</th>
                    {plansToCompare.map(planId => {
                      const plan = availablePlans.find(p => p.id === planId);
                      if (!plan) return null;
                      return (
                        <th key={planId} className="text-center py-3 px-4 w-1/4">
                          <div className="space-y-2">
                            <div className="font-semibold text-theme-primary">{plan.name}</div>
                            <div className="text-2xl font-bold text-theme-info">
                              {calculatePlanPrice(plan, billingCycle)}
                            </div>
                            <div className="text-sm text-theme-secondary">
                              per {billingCycle === 'yearly' ? 'year' : 'month'}
                            </div>
                            <button
                              onClick={() => {
                                onClose();
                                navigate(`/register?plan=${planId}&billing=${billingCycle}`);
                              }}
                              className="w-full bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold px-4 py-2 rounded-lg transition-colors duration-200 text-sm"
                            >
                              Select Plan
                            </button>
                          </div>
                        </th>
                      );
                    })}
                  </tr>
                </thead>
                <tbody className="divide-y divide-theme">
                  {/* Pricing Row */}
                  <tr className="bg-theme-background-secondary">
                    <td className="py-3 px-4 font-medium text-theme-primary">Pricing</td>
                    {plansToCompare.map(planId => {
                      const plan = availablePlans.find(p => p.id === planId);
                      if (!plan) return null;
                      return (
                        <td key={planId} className="text-center py-3 px-4">
                          <div className="text-lg font-semibold text-theme-primary">
                            {calculatePlanPrice(plan, billingCycle)}
                          </div>
                          {billingCycle === 'yearly' && plan.price_cents > 0 && (
                            <div className="text-xs text-theme-secondary">
                              {getMonthlyPrice(plan)}/month
                            </div>
                          )}
                        </td>
                      );
                    })}
                  </tr>

                  {/* Trial Period Row */}
                  <tr className="bg-theme-surface">
                    <td className="py-4 px-4 font-bold text-theme-primary">Free Trial</td>
                    {plansToCompare.map(planId => {
                      const plan = availablePlans.find(p => p.id === planId);
                      if (!plan) return null;
                      return (
                        <td key={planId} className="text-center py-4 px-4">
                          {(plan.trial_days && plan.trial_days > 0) ? (
                            <div className="inline-flex items-center justify-center px-3 py-1.5 bg-theme-success/10 text-theme-success rounded-full border border-theme-success/20 font-semibold text-sm">
                              {plan.trial_days} days free
                            </div>
                          ) : (
                            <div className="inline-flex items-center justify-center px-3 py-1.5 bg-theme-surface text-theme-muted rounded-full border border-theme font-medium text-sm">
                              No trial
                            </div>
                          )}
                        </td>
                      );
                    })}
                  </tr>

                  {/* Features Rows */}
                  {getAllPlanFeatures().map((feature, index) => (
                    <tr key={index} className={`${index % 2 === 0 ? 'bg-theme-background-secondary' : 'bg-theme-surface'} hover:bg-theme-background-tertiary`}>
                      <td className="py-3 px-4 font-medium text-theme-primary">{feature}</td>
                      {plansToCompare.map(planId => {
                        const plan = availablePlans.find(p => p.id === planId);
                        if (!plan) return null;
                        const hasFeature = planHasFeature(plan, feature);
                        return (
                          <td key={planId} className="text-center py-3 px-4">
                            {hasFeature ? (
                              <CheckIcon className="h-5 w-5 text-theme-success mx-auto" />
                            ) : (
                              <span className="text-theme-tertiary">—</span>
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* Modal Footer */}
        <div className="px-8 py-6 border-t border-theme bg-theme-background-secondary">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="text-center sm:text-left">
              <p className="text-sm font-medium text-theme-primary">
                Select a plan to continue with your registration
              </p>
              <p className="text-xs text-theme-tertiary">
                Compare features and pricing across different plans
              </p>
            </div>
            <button
              onClick={onClose}
              className="inline-flex items-center space-x-2 px-6 py-3 bg-theme-background-secondary hover:bg-theme-background-tertiary text-theme-primary font-medium rounded-xl transition-all duration-200 transform hover:scale-105"
            >
              <span>Close Comparison</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

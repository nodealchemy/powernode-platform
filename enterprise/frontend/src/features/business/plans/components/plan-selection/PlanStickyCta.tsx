import React from 'react';
import { CheckIcon, ArrowRightIcon } from '@heroicons/react/24/outline';
import { Plan } from '@/features/business/plans/services/plansApi';

interface PlanStickyCtaProps {
  selectedPlan: Plan | null;
  billingCycle: 'monthly' | 'yearly';
  calculatePlanPrice: (plan: Plan, cycle: 'monthly' | 'yearly') => string;
  onContinue: () => void;
}

export const PlanStickyCta: React.FC<PlanStickyCtaProps> = ({
  selectedPlan,
  billingCycle,
  calculatePlanPrice,
  onContinue
}) => {
  if (!selectedPlan) return null;

  return (
    <div className="sticky bottom-0 z-40 bg-theme-surface/95 backdrop-blur-lg border-t border-theme mt-20">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div className="flex flex-col lg:flex-row items-center justify-between gap-6">
          {/* Plan Summary */}
          <div className="flex items-center space-x-6">
            <div className="flex items-center space-x-4">
              <div className="w-12 h-12 rounded-xl flex items-center justify-center bg-theme-success-solid">
                <CheckIcon className="h-6 w-6 text-white" />
              </div>
              <div>
                <div className="font-semibold text-theme-primary">
                  {selectedPlan.name} Plan Selected
                </div>
                <div className="text-sm text-theme-secondary">
                  Billed {billingCycle}
                  {selectedPlan.trial_days && selectedPlan.trial_days > 0 && (
                    <span className="ml-2 px-2 py-0.5 bg-theme-success-solid text-white rounded-full text-xs font-bold shadow-sm">
                      {selectedPlan.trial_days} day trial
                    </span>
                  )}
                </div>
              </div>
            </div>

            <div className="hidden sm:block w-px h-12 bg-theme-border"></div>

            <div className="text-center sm:text-left">
              <div className="text-2xl font-bold text-theme-primary">
                {calculatePlanPrice(selectedPlan, billingCycle)}
              </div>
              <div className="text-sm text-theme-tertiary">
                per {billingCycle === 'yearly' ? 'year' : 'month'}
              </div>
            </div>
          </div>

          {/* CTA Button */}
          <div className="flex flex-col items-center space-y-3">
            <button
              onClick={onContinue}
              data-testid="continue-to-registration"
              className="inline-flex items-center justify-center space-x-3 text-white font-semibold px-8 py-4 rounded-xl transition-all duration-200 transform hover:scale-105 min-w-[200px] bg-theme-interactive-primary hover:bg-theme-interactive-primary-hover shadow-lg"
            >
              <span>Get Started</span>
              <ArrowRightIcon className="h-5 w-5" />
            </button>

            <div className="flex items-center space-x-4 text-xs text-theme-tertiary">
              <span className="flex items-center space-x-1">
                <CheckIcon className="h-3 w-3" />
                <span>No credit card required</span>
              </span>
              <span className="flex items-center space-x-1">
                <CheckIcon className="h-3 w-3" />
                <span>Cancel anytime</span>
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

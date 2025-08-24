import React, { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { 
  CalendarIcon, 
  PercentBadgeIcon, 
  PlusIcon, 
  TrashIcon,
  InformationCircleIcon
} from '@heroicons/react/24/outline';

interface VolumeDiscountTier {
  min_quantity: number;
  discount_percent: number;
}

interface PlanDiscountConfigProps {
  // Annual Discount
  hasAnnualDiscount: boolean;
  annualDiscountPercent: number;
  
  // Volume Discount  
  hasVolumeDiscount: boolean;
  volumeDiscountTiers: VolumeDiscountTier[];
  
  // Promotional Discount
  hasPromotionalDiscount: boolean;
  promotionalDiscountPercent: number;
  promotionalDiscountStart: string;
  promotionalDiscountEnd: string;
  promotionalDiscountCode: string;
  
  // Change handlers
  onDiscountChange: (field: string, value: any) => void;
  disabled?: boolean;
}

export const PlanDiscountConfig: React.FC<PlanDiscountConfigProps> = ({
  hasAnnualDiscount,
  annualDiscountPercent,
  hasVolumeDiscount,
  volumeDiscountTiers,
  hasPromotionalDiscount,
  promotionalDiscountPercent,
  promotionalDiscountStart,
  promotionalDiscountEnd,
  promotionalDiscountCode,
  onDiscountChange,
  disabled = false
}) => {
  const [expandedSections, setExpandedSections] = useState<{[key: string]: boolean}>({
    annual: hasAnnualDiscount,
    volume: hasVolumeDiscount,
    promotional: hasPromotionalDiscount
  });

  const toggleSection = (section: string) => {
    const validSections = ['annual', 'volume', 'promotional'];
    if (!validSections.includes(section)) return;
    
    setExpandedSections(prev => ({
      ...prev,
      [section]: !prev[section as keyof typeof prev]
    }));
  };

  const addVolumeDiscountTier = () => {
    const newTiers = [...volumeDiscountTiers, { min_quantity: 1, discount_percent: 0 }];
    onDiscountChange('volume_discount_tiers', newTiers);
  };

  const updateVolumeDiscountTier = (index: number, field: string, value: number) => {
    const validFields = ['min_quantity', 'discount_percent'];
    if (!validFields.includes(field) || index < 0 || index >= volumeDiscountTiers.length) return;
    
    const newTiers = [...volumeDiscountTiers];
    // eslint-disable-next-line security/detect-object-injection
    const currentTier = newTiers[index];
    if (!currentTier) return;
    
    if (field === 'min_quantity') {
      // eslint-disable-next-line security/detect-object-injection
      newTiers[index] = { ...currentTier, min_quantity: value };
    } else if (field === 'discount_percent') {
      // eslint-disable-next-line security/detect-object-injection
      newTiers[index] = { ...currentTier, discount_percent: value };
    }
    onDiscountChange('volume_discount_tiers', newTiers);
  };

  const removeVolumeDiscountTier = (index: number) => {
    const newTiers = volumeDiscountTiers.filter((_, i) => i !== index);
    onDiscountChange('volume_discount_tiers', newTiers);
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium text-theme-primary mb-4">Discount Configuration</h3>
        <p className="text-sm text-theme-secondary mb-6">
          Configure different types of discounts for this plan to encourage longer commitments and larger purchases.
        </p>
      </div>

      {/* Annual Discount Section */}
      <div className="border border-theme rounded-lg">
        <div 
          className="flex items-center justify-between p-4 cursor-pointer hover:bg-theme-surface-hover"
          onClick={() => toggleSection('annual')}
        >
          <div className="flex items-center space-x-3">
            <PercentBadgeIcon className="w-5 h-5 text-theme-interactive-primary" />
            <div>
              <h4 className="font-medium text-theme-primary">Annual Discount</h4>
              <p className="text-sm text-theme-secondary">Discount for annual billing</p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={hasAnnualDiscount}
                onChange={(e) => {
                  onDiscountChange('has_annual_discount', e.target.checked);
                  if (e.target.checked) {
                    setExpandedSections(prev => ({ ...prev, annual: true }));
                  }
                }}
                disabled={disabled}
                className="h-4 w-4 text-theme-interactive-primary rounded border-theme focus:ring-theme-interactive-primary"
              />
              <span className="ml-2 text-sm">Enable</span>
            </label>
          </div>
        </div>
        
        {(hasAnnualDiscount || expandedSections.annual) && (
          <div className="px-4 pb-4 border-t border-theme-light">
            <div className="mt-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Annual Discount Percentage
                </label>
                <div className="relative">
                  <input
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    value={annualDiscountPercent}
                    onChange={(e) => onDiscountChange('annual_discount_percent', parseFloat(e.target.value))}
                    disabled={disabled || !hasAnnualDiscount}
                    className="input-theme pr-8"
                    placeholder="0.00"
                  />
                  <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                    <span className="text-theme-secondary text-sm">%</span>
                  </div>
                </div>
                <p className="text-xs text-theme-secondary mt-1">
                  Customers save this percentage when paying annually vs monthly
                </p>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Volume Discount Section */}
      <div className="border border-theme rounded-lg">
        <div 
          className="flex items-center justify-between p-4 cursor-pointer hover:bg-theme-surface-hover"
          onClick={() => toggleSection('volume')}
        >
          <div className="flex items-center space-x-3">
            <InformationCircleIcon className="w-5 h-5 text-theme-success" />
            <div>
              <h4 className="font-medium text-theme-primary">Volume Discount</h4>
              <p className="text-sm text-theme-secondary">Quantity-based discounts</p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={hasVolumeDiscount}
                onChange={(e) => {
                  onDiscountChange('has_volume_discount', e.target.checked);
                  if (e.target.checked) {
                    setExpandedSections(prev => ({ ...prev, volume: true }));
                  }
                }}
                disabled={disabled}
                className="h-4 w-4 text-theme-interactive-primary rounded border-theme focus:ring-theme-interactive-primary"
              />
              <span className="ml-2 text-sm">Enable</span>
            </label>
          </div>
        </div>
        
        {(hasVolumeDiscount || expandedSections.volume) && (
          <div className="px-4 pb-4 border-t border-theme-light">
            <div className="mt-4">
              <div className="flex items-center justify-between mb-3">
                <h5 className="text-sm font-medium text-theme-primary">Discount Tiers</h5>
                <Button onClick={addVolumeDiscountTier} disabled={disabled || !hasVolumeDiscount} type="button" variant="primary" size="sm">
                  <PlusIcon className="w-4 h-4 mr-1" />
                  Add Tier
                </Button>
              </div>
              
              <div className="space-y-3">
                {volumeDiscountTiers.map((tier, index) => (
                  <div key={index} className="flex items-center space-x-3 p-3 bg-theme-surface-hover rounded-lg">
                    <div className="flex-1">
                      <label className="block text-xs font-medium text-theme-primary mb-1">
                        Min Quantity
                      </label>
                      <input
                        type="number"
                        min="1"
                        value={tier.min_quantity}
                        onChange={(e) => updateVolumeDiscountTier(index, 'min_quantity', parseInt(e.target.value))}
                        disabled={disabled || !hasVolumeDiscount}
                        className="input-theme text-sm"
                      />
                    </div>
                    <div className="flex-1">
                      <label className="block text-xs font-medium text-theme-primary mb-1">
                        Discount %
                      </label>
                      <div className="relative">
                        <input
                          type="number"
                          min="0"
                          max="100"
                          step="0.01"
                          value={tier.discount_percent}
                          onChange={(e) => updateVolumeDiscountTier(index, 'discount_percent', parseFloat(e.target.value))}
                          disabled={disabled || !hasVolumeDiscount}
                          className="input-theme text-sm pr-6"
                        />
                        <div className="absolute inset-y-0 right-0 pr-2 flex items-center pointer-events-none">
                          <span className="text-theme-secondary text-xs">%</span>
                        </div>
                      </div>
                    </div>
                    <Button type="button" variant="outline" onClick={() => removeVolumeDiscountTier(index)}
                      disabled={disabled || !hasVolumeDiscount}
                      className="p-2 text-theme-error hover:text-theme-error-hover disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <TrashIcon className="w-4 h-4" />
                    </Button>
                  </div>
                ))}
                
                {volumeDiscountTiers.length === 0 && (
                  <p className="text-sm text-theme-secondary italic text-center py-4">
                    No volume discount tiers configured
                  </p>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Promotional Discount Section */}
      <div className="border border-theme rounded-lg">
        <div 
          className="flex items-center justify-between p-4 cursor-pointer hover:bg-theme-surface-hover"
          onClick={() => toggleSection('promotional')}
        >
          <div className="flex items-center space-x-3">
            <CalendarIcon className="w-5 h-5 text-purple-600" />
            <div>
              <h4 className="font-medium text-theme-primary">Promotional Discount</h4>
              <p className="text-sm text-theme-secondary">Time-limited promotional offers</p>
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={hasPromotionalDiscount}
                onChange={(e) => {
                  onDiscountChange('has_promotional_discount', e.target.checked);
                  if (e.target.checked) {
                    setExpandedSections(prev => ({ ...prev, promotional: true }));
                  }
                }}
                disabled={disabled}
                className="h-4 w-4 text-theme-interactive-primary rounded border-theme focus:ring-theme-interactive-primary"
              />
              <span className="ml-2 text-sm">Enable</span>
            </label>
          </div>
        </div>
        
        {(hasPromotionalDiscount || expandedSections.promotional) && (
          <div className="px-4 pb-4 border-t border-theme-light">
            <div className="mt-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Discount Percentage
                </label>
                <div className="relative">
                  <input
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    value={promotionalDiscountPercent}
                    onChange={(e) => onDiscountChange('promotional_discount_percent', parseFloat(e.target.value))}
                    disabled={disabled || !hasPromotionalDiscount}
                    className="input-theme pr-8"
                    placeholder="0.00"
                  />
                  <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                    <span className="text-theme-secondary text-sm">%</span>
                  </div>
                </div>
              </div>
              
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Promotional Code (Optional)
                </label>
                <input
                  type="text"
                  value={promotionalDiscountCode}
                  onChange={(e) => onDiscountChange('promotional_discount_code', e.target.value)}
                  disabled={disabled || !hasPromotionalDiscount}
                  className="input-theme"
                  placeholder="e.g. SAVE20"
                  maxLength={50}
                />
                <p className="text-xs text-theme-secondary mt-1">
                  Leave empty for automatic discount, or add a code for customer entry
                </p>
              </div>
              
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Start Date & Time
                  </label>
                  <input
                    type="datetime-local"
                    value={promotionalDiscountStart}
                    onChange={(e) => onDiscountChange('promotional_discount_start', e.target.value)}
                    disabled={disabled || !hasPromotionalDiscount}
                    className="input-theme"
                  />
                </div>
                
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    End Date & Time
                  </label>
                  <input
                    type="datetime-local"
                    value={promotionalDiscountEnd}
                    onChange={(e) => onDiscountChange('promotional_discount_end', e.target.value)}
                    disabled={disabled || !hasPromotionalDiscount}
                    className="input-theme"
                  />
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
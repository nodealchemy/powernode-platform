import React, { useState, useEffect, useCallback } from 'react';
import { CreditCard, Plus, Trash2, Check, AlertTriangle, Star } from 'lucide-react';
import { paymentMethodsApi, PaymentMethod } from '@/shared/services/paymentMethodsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';

interface PaymentMethodsManagerProps {
  onMethodAdded?: (method: PaymentMethod) => void;
  onMethodDeleted?: (method_id: string) => void;
  showAddButton?: boolean;
}

export const PaymentMethodsManager: React.FC<PaymentMethodsManagerProps> = ({
  onMethodAdded,
  onMethodDeleted,
  showAddButton = true
}) => {
  const [paymentMethods, setPaymentMethods] = useState<PaymentMethod[]>([]);
  const [default_method_id, setDefault_method_id] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [addingMethod, setAddingMethod] = useState(false);
  const [deletingMethod, setDeletingMethod] = useState<string>('');
  const [settingDefault, setSettingDefault] = useState<string>('');
  
  const { showNotification } = useNotifications();

  const loadPaymentMethods = useCallback(async () => {
    try {
      setLoading(true);
      const response = await paymentMethodsApi.getPaymentMethods();
      if (response.success) {
        setPaymentMethods(response.payment_methods);
        setDefault_method_id(response.default_payment_method_id || '');
      } else {
        showNotification(response.error || 'Failed to load payment methods', 'error');
      }
    } catch (error: any) {
      showNotification('Failed to load payment methods', 'error');
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  useEffect(() => {
    loadPaymentMethods();
  }, [loadPaymentMethods]);

  const handleAddPaymentMethod = async () => {
    try {
      setAddingMethod(true);
      const response = await paymentMethodsApi.createSetupIntent();
      
      if (response.success) {
        // This would integrate with Stripe Elements in a real implementation
        showNotification('Payment method setup initiated', 'info');
        // For now, just reload the list
        await loadPaymentMethods();
        if (onMethodAdded) {
          // In real implementation, this would be called after successful setup
          // onMethodAdded(newMethod);
        }
      } else {
        showNotification(response.error || 'Failed to setup payment method', 'error');
      }
    } catch (error: any) {
      showNotification('Failed to setup payment method', 'error');
    } finally {
      setAddingMethod(false);
    }
  };

  const handleSetDefault = async (method_id: string) => {
    try {
      setSettingDefault(method_id);
      const response = await paymentMethodsApi.setDefaultPaymentMethod(method_id);

      if (response.success) {
        setDefault_method_id(method_id);
        showNotification('Default payment method updated', 'success');
      } else {
        showNotification(response.error || 'Failed to set default payment method', 'error');
      }
    } catch (error: any) {
      showNotification('Failed to set default payment method', 'error');
    } finally {
      setSettingDefault('');
    }
  };

  const handleDeleteMethod = async (method_id: string) => {
    if (!window.confirm('Are you sure you want to delete this payment method?')) {
      return;
    }

    try {
      setDeletingMethod(method_id);
      const response = await paymentMethodsApi.deletePaymentMethod(method_id);

      if (response.success) {
        setPaymentMethods(prev => prev.filter(method => method.id !== method_id));
        if (default_method_id === method_id) {
          setDefault_method_id('');
        }
        showNotification('Payment method deleted successfully', 'success');
        if (onMethodDeleted) {
          onMethodDeleted(method_id);
        }
      } else {
        showNotification(response.error || 'Failed to delete payment method', 'error');
      }
    } catch (error: any) {
      showNotification('Failed to delete payment method', 'error');
    } finally {
      setDeletingMethod('');
    }
  };

  const getExpiryWarning = (method: PaymentMethod): string | null => {
    if (paymentMethodsApi.isExpiredCard(method)) {
      return 'Expired';
    }
    
    if (method.type === 'card' && method.card) {
      const expiry = new Date(method.card.exp_year, method.card.exp_month - 1);
      const now = new Date();
      const monthsUntilExpiry = (expiry.getFullYear() - now.getFullYear()) * 12 + 
                               (expiry.getMonth() - now.getMonth());
      
      if (monthsUntilExpiry <= 2 && monthsUntilExpiry > 0) {
        return 'Expires soon';
      }
    }
    
    return null;
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Payment Methods</h3>
          <p className="text-sm text-theme-secondary">
            Manage your payment methods for subscriptions and invoices
          </p>
        </div>
        
        {showAddButton && (
          <Button
            onClick={handleAddPaymentMethod}
            disabled={addingMethod}
            loading={addingMethod}
            variant="primary">
            {!addingMethod && <Plus className="w-4 h-4 mr-2" />}
            {addingMethod ? 'Adding...' : 'Add Payment Method'}
          </Button>
        )}
      </div>

      {/* Payment Methods List */}
      {paymentMethods.length === 0 ? (
        <div className="text-center py-8 bg-theme-surface rounded-lg border border-theme">
          <CreditCard className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
          <h4 className="text-lg font-medium text-theme-primary mb-2">No Payment Methods</h4>
          <p className="text-theme-secondary mb-4">
            Add a payment method to enable automatic billing
          </p>
          {showAddButton && (
            <Button
              onClick={handleAddPaymentMethod}
              disabled={addingMethod}
              loading={addingMethod}
              variant="primary"
            >
              {addingMethod ? 'Adding...' : 'Add Your First Payment Method'}
            </Button>
          )}
        </div>
      ) : (
        <div className="space-y-4">
          {paymentMethods.map((method) => {
            const isDefault = method.id === default_method_id;
            const expiryWarning = getExpiryWarning(method);
            
            return (
              <div
                key={method.id}
                className={`p-4 border rounded-lg bg-theme-surface transition-all ${
                  isDefault 
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary bg-opacity-5' 
                    : 'border-theme hover:border-theme-focus'
                }`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    {/* Payment Method Icon */}
                    <div className="w-10 h-10 bg-theme-background rounded-lg flex items-center justify-center">
                      {method.type === 'card' && method.card && (
                        <span className="text-lg">
                          {paymentMethodsApi.getCardBrandIcon(method.card.brand)}
                        </span>
                      )}
                      {method.type === 'bank_account' && (
                        <span className="text-lg">🏦</span>
                      )}
                      {method.type === 'paypal' && (
                        <span className="text-lg">💙</span>
                      )}
                    </div>
                    
                    {/* Payment Method Info */}
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-medium text-theme-primary">
                          {paymentMethodsApi.getPaymentMethodDisplay(method)}
                        </span>
                        {isDefault && (
                          <div className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary bg-opacity-10 rounded text-xs text-theme-interactive-primary">
                            <Star className="w-3 h-3" />
                            Default
                          </div>
                        )}
                        {expiryWarning && (
                          <div className={`flex items-center gap-1 px-2 py-1 rounded text-xs ${
                            expiryWarning === 'Expired' 
                              ? 'bg-theme-error-background text-theme-error'
                              : 'bg-theme-warning-background text-theme-warning'
                          }`}>
                            <AlertTriangle className="w-3 h-3" />
                            {expiryWarning}
                          </div>
                        )}
                      </div>
                      
                      <div className="text-sm text-theme-secondary">
                        {method.type === 'card' && method.card && (
                          <span>
                            Expires {paymentMethodsApi.formatExpiryDate(method.card.exp_month, method.card.exp_year)}
                          </span>
                        )}
                        {method.type === 'bank_account' && method.bank_account && (
                          <span>
                            {method.bank_account.account_holder_type} • {method.bank_account.country}
                          </span>
                        )}
                        {method.type === 'paypal' && method.paypal && (
                          <span>
                            PayPal Account
                          </span>
                        )}
                        {method.last_used_at && (
                          <span className="ml-2">
                            • Last used {new Date(method.last_used_at).toLocaleDateString()}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                  
                  {/* Actions */}
                  <div className="flex items-center gap-2">
                    {!isDefault && (
                      <Button
                        onClick={() => handleSetDefault(method.id)}
                        disabled={settingDefault === method.id}
                        loading={settingDefault === method.id}
                        variant="secondary"
                        size="sm"
                      >
                        {settingDefault !== method.id && <Check className="w-3 h-3 mr-1" />}
                        Set Default
                      </Button>
                    )}
                    
                    <Button
                      onClick={() => handleDeleteMethod(method.id)}
                      disabled={deletingMethod === method.id}
                      loading={deletingMethod === method.id}
                      variant="ghost"
                      size="sm"
                      iconOnly
                      className="text-theme-error hover:text-theme-error-hover"
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};


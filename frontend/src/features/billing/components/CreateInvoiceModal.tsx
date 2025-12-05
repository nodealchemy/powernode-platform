import React, { useEffect } from 'react';
import { DatePicker } from '@/shared/components/ui/DatePicker';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Plus, Trash2, DollarSign, Save } from 'lucide-react';

interface CreateInvoiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (invoiceData: InvoiceFormData) => Promise<void>;
}

export interface InvoiceFormData {
  customerEmail: string;
  dueDate: Date | null;
  issueDate: Date | null;
  amount: number;
  currency: string;
  description: string;
  lineItems: Array<{
    description: string;
    quantity: number;
    unitPrice: number;
    total: number;
  }>;
}

export const CreateInvoiceModal: React.FC<CreateInvoiceModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
}) => {
  const defaultValues: InvoiceFormData = {
    customerEmail: '',
    dueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
    issueDate: new Date(),
    amount: 0,
    currency: 'USD',
    description: '',
    lineItems: [{ description: '', quantity: 1, unitPrice: 0, total: 0 }],
  };

  const validationRules: FormValidationRules = {
    customerEmail: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
    },
    dueDate: {
      required: true,
      custom: (value: unknown) => {
        const date = value as Date | null;
        if (date && date < new Date()) {
          return 'Due date cannot be in the past';
        }
        return null;
      }
    },
    issueDate: {
      required: true,
    },
    amount: {
      custom: (value: unknown) => {
        const amount = value as number;
        if (amount <= 0) {
          return 'Amount must be greater than 0';
        }
        return null;
      }
    },
    description: {
      required: true,
      minLength: 3,
      maxLength: 500,
    }
  };

  const form = useForm<InvoiceFormData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Invoice created successfully',
    resetAfterSubmit: true,
  });

  // Reset form when modal opens
  useEffect(() => {
    if (isOpen) {
      form.reset();
    }
  }, [isOpen, form]);

  const calculateTotal = () => {
    return form.values.lineItems.reduce((sum, item) => sum + item.total, 0);
  };

  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const updateLineItem = (index: number, field: 'description' | 'quantity' | 'unitPrice', value: string | number) => {
    const newItems = [...form.values.lineItems];
    const currentItem = newItems.at(index);
    
    if (!currentItem) return;
    
    const item = { ...currentItem };
    
    // Type-safe property assignment
    if (field === 'description') {
      item.description = value as string;
    } else if (field === 'quantity') {
      item.quantity = value as number;
    } else if (field === 'unitPrice') {
      item.unitPrice = value as number;
    }
    
    newItems.splice(index, 1, item);
    
    // Recalculate total for this line item
    if (field === 'quantity' || field === 'unitPrice') {
      const updatedItem = newItems.at(index);
      if (updatedItem) {
        updatedItem.total = updatedItem.quantity * updatedItem.unitPrice;
      }
    }
    
    // Update form with new line items
    form.setValue('lineItems', newItems);
    
    // Update total amount
    const newTotal = newItems.reduce((sum, item) => sum + item.total, 0);
    form.setValue('amount', newTotal);
  };

  const addLineItem = () => {
    const newItems = [...form.values.lineItems, { description: '', quantity: 1, unitPrice: 0, total: 0 }];
    form.setValue('lineItems', newItems);
  };

  const removeLineItem = (index: number) => {
    if (form.values.lineItems.length > 1) {
      const newItems = form.values.lineItems.filter((_, i) => i !== index);
      form.setValue('lineItems', newItems);
      
      // Update total amount
      const newTotal = newItems.reduce((sum, item) => sum + item.total, 0);
      form.setValue('amount', newTotal);
    }
  };

  const modalFooter = (
    <div className="flex justify-end space-x-3">
      <Button
        variant="secondary"
        onClick={handleCancel}
        disabled={form.isSubmitting}
      >
        Cancel
      </Button>
      <Button
        variant="primary"
        type="submit"
        form="create-invoice-form"
        loading={form.isSubmitting}
      >
        {!form.isSubmitting && <Save className="w-4 h-4 mr-2" />}
        {form.isSubmitting ? 'Creating...' : 'Create Invoice'}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleCancel}
      title="Create Invoice"
      subtitle="Generate a new invoice for your customer"
      icon={<DollarSign />}
      maxWidth="4xl"
      footer={modalFooter}
      closeOnBackdrop={!form.isSubmitting}
      closeOnEscape={!form.isSubmitting}
    >
      <form id="create-invoice-form" onSubmit={form.handleSubmit} className="space-y-6">
          {/* Basic Information */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <FormField 
                label="Customer Email" 
                type="email" 
                placeholder="customer@example.com" 
                value={form.values.customerEmail || ''}
                onChange={(value) => form.setValue('customerEmail', value)}
                required 
                disabled={form.isSubmitting} 
              />
              {form.errors.customerEmail && (
                <p className="text-theme-error text-sm mt-1">{form.errors.customerEmail}</p>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Currency
              </label>
              <select
                {...form.getFieldProps('currency')}
                className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={form.isSubmitting}
              >
                <option value="USD">USD</option>
                <option value="EUR">EUR</option>
                <option value="GBP">GBP</option>
                <option value="CAD">CAD</option>
              </select>
            </div>
          </div>

          {/* Dates */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Issue Date *
              </label>
              <DatePicker
                selected={form.values.issueDate}
                onChange={(date) => form.setValue('issueDate', date)}
                dateFormat="MM/dd/yyyy"
                maxDate={new Date()}
                disabled={form.isSubmitting}
                required
                useNativeInput={false}
                className={form.errors.issueDate ? 'border-theme-error' : ''}
              />
              {form.errors.issueDate && (
                <p className="text-theme-error text-sm mt-1">{form.errors.issueDate}</p>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Due Date *
              </label>
              <DatePicker
                selected={form.values.dueDate}
                onChange={(date) => form.setValue('dueDate', date)}
                dateFormat="MM/dd/yyyy"
                minDate={new Date()}
                disabled={form.isSubmitting}
                required
                useNativeInput={false}
                className={form.errors.dueDate ? 'border-theme-error' : ''}
              />
              {form.errors.dueDate && (
                <p className="text-theme-error text-sm mt-1">{form.errors.dueDate}</p>
              )}
            </div>
          </div>

          {/* Description */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Description *
            </label>
            <textarea
              {...form.getFieldProps('description')}
              className={`w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm placeholder-theme-tertiary text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary disabled:opacity-50 disabled:cursor-not-allowed resize-y ${form.errors.description ? 'border-theme-error' : ''}`}
              rows={3}
              placeholder="Invoice description..."
              disabled={form.isSubmitting}
              required
            />
            {form.errors.description && (
              <p className="text-theme-error text-sm mt-1">{form.errors.description}</p>
            )}
          </div>

          {/* Line Items */}
          <div>
            <div className="flex justify-between items-center mb-4">
              <label className="block text-sm font-medium text-theme-primary mb-1">Line Items</label>
              <Button
                type="button"
                onClick={addLineItem}
                variant="secondary"
                size="sm"
                disabled={form.isSubmitting}
              >
                <Plus className="w-4 h-4 mr-1" />
                Add Item
              </Button>
            </div>

            <div className="space-y-3">
              {form.values.lineItems.map((item, index) => (
                <div key={index} className="grid grid-cols-1 md:grid-cols-12 gap-3 p-4 border border-theme rounded-lg">
                  <div className="md:col-span-5">
                    <input
                      type="text"
                      value={item.description}
                      onChange={(e) => updateLineItem(index, 'description', e.target.value)}
                      className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm placeholder-theme-tertiary text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary disabled:opacity-50"
                      placeholder="Item description"
                      disabled={form.isSubmitting}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <input
                      type="number"
                      min="1"
                      value={item.quantity}
                      onChange={(e) => updateLineItem(index, 'quantity', parseInt(e.target.value) || 1)}
                      className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm placeholder-theme-tertiary text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary disabled:opacity-50"
                      placeholder="Qty"
                      disabled={form.isSubmitting}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={item.unitPrice}
                      onChange={(e) => updateLineItem(index, 'unitPrice', parseFloat(e.target.value) || 0)}
                      className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme rounded-md shadow-sm placeholder-theme-tertiary text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-theme-interactive-primary disabled:opacity-50"
                      placeholder="Unit price"
                      disabled={form.isSubmitting}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <FormField 
                      label="Total" 
                      type="text" 
                      value={`$${item.total.toFixed(2)}`} 
                      onChange={() => {}}
                      disabled 
                    />
                  </div>
                  <div className="md:col-span-1">
                    {form.values.lineItems.length > 1 && (
                      <Button
                        type="button"
                        onClick={() => removeLineItem(index)}
                        variant="ghost"
                        size="sm"
                        disabled={form.isSubmitting}
                        iconOnly
                        className="text-theme-error hover:text-theme-error-hover"
                      >
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    )}
                  </div>
                </div>
              ))}
            </div>

            <div className="flex justify-end mt-4">
              <div className="text-right">
                <p className="text-lg font-semibold text-theme-primary">
                  Total: ${calculateTotal().toFixed(2)}
                </p>
              </div>
            </div>
          </div>
        </form>
    </Modal>
  );
};


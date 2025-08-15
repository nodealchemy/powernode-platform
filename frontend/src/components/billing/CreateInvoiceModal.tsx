import React, { useState } from 'react';
import { DatePicker } from '../common/DatePicker';

interface CreateInvoiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (invoiceData: InvoiceFormData) => void;
  loading?: boolean;
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
  loading = false,
}) => {
  const [formData, setFormData] = useState<InvoiceFormData>({
    customerEmail: '',
    dueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
    issueDate: new Date(),
    amount: 0,
    currency: 'USD',
    description: '',
    lineItems: [{ description: '', quantity: 1, unitPrice: 0, total: 0 }],
  });

  const [errors, setErrors] = useState<Record<string, string>>({});

  if (!isOpen) return null;

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.customerEmail) {
      newErrors.customerEmail = 'Customer email is required';
    } else if (!/\S+@\S+\.\S+/.test(formData.customerEmail)) {
      newErrors.customerEmail = 'Please enter a valid email address';
    }

    if (!formData.dueDate) {
      newErrors.dueDate = 'Due date is required';
    } else if (formData.dueDate < new Date()) {
      newErrors.dueDate = 'Due date cannot be in the past';
    }

    if (!formData.issueDate) {
      newErrors.issueDate = 'Issue date is required';
    }

    if (formData.amount <= 0) {
      newErrors.amount = 'Amount must be greater than 0';
    }

    if (!formData.description.trim()) {
      newErrors.description = 'Description is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (validateForm()) {
      onSubmit(formData);
    }
  };

  const handleInputChange = (field: keyof InvoiceFormData, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear error when user starts typing
    if (Object.prototype.hasOwnProperty.call(errors, field)) {
      setErrors(prev => ({ ...prev, [field]: '' }));
    }
  };

  const calculateTotal = () => {
    return formData.lineItems.reduce((sum, item) => sum + item.total, 0);
  };

  const updateLineItem = (index: number, field: string, value: any) => {
    const newItems = [...formData.lineItems];
    const currentItem = newItems.at(index);
    
    if (!currentItem) return;
    
    const item = { ...currentItem };
    
    // Type-safe property assignment
    if (field === 'description') {
      item.description = value;
    } else if (field === 'quantity') {
      item.quantity = value;
    } else if (field === 'unitPrice') {
      item.unitPrice = value;
    }
    
    newItems.splice(index, 1, item);
    
    // Recalculate total for this line item
    if (field === 'quantity' || field === 'unitPrice') {
      const updatedItem = newItems.at(index);
      if (updatedItem) {
        updatedItem.total = updatedItem.quantity * updatedItem.unitPrice;
      }
    }
    
    setFormData(prev => ({ ...prev, lineItems: newItems }));
    
    // Update total amount
    const newTotal = newItems.reduce((sum, item) => sum + item.total, 0);
    setFormData(prev => ({ ...prev, amount: newTotal }));
  };

  const addLineItem = () => {
    setFormData(prev => ({
      ...prev,
      lineItems: [...prev.lineItems, { description: '', quantity: 1, unitPrice: 0, total: 0 }]
    }));
  };

  const removeLineItem = (index: number) => {
    if (formData.lineItems.length > 1) {
      const newItems = formData.lineItems.filter((_, i) => i !== index);
      setFormData(prev => ({ ...prev, lineItems: newItems }));
      
      // Update total amount
      const newTotal = newItems.reduce((sum, item) => sum + item.total, 0);
      setFormData(prev => ({ ...prev, amount: newTotal }));
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="card-theme max-w-4xl w-full max-h-[90vh] overflow-y-auto mx-4">
        <div className="sticky top-0 bg-theme-background border-b border-theme px-6 py-4">
          <div className="flex justify-between items-center">
            <h2 className="text-xl font-bold text-theme-primary">Create Invoice</h2>
            <button
              onClick={onClose}
              className="text-theme-secondary hover:text-theme-primary"
              disabled={loading}
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          {/* Basic Information */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="label-theme">
                Customer Email *
              </label>
              <input
                type="email"
                value={formData.customerEmail}
                onChange={(e) => handleInputChange('customerEmail', e.target.value)}
                className={`input-theme ${errors.customerEmail ? 'border-theme-error' : ''}`}
                placeholder="customer@example.com"
                disabled={loading}
                required
              />
              {errors.customerEmail && (
                <p className="text-theme-error text-sm mt-1">{errors.customerEmail}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Currency
              </label>
              <select
                value={formData.currency}
                onChange={(e) => handleInputChange('currency', e.target.value)}
                className="select-theme"
                disabled={loading}
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
              <label className="label-theme">
                Issue Date *
              </label>
              <DatePicker
                selected={formData.issueDate}
                onChange={(date) => handleInputChange('issueDate', date)}
                dateFormat="MM/dd/yyyy"
                maxDate={new Date()}
                disabled={loading}
                required
                className={errors.issueDate ? 'border-theme-error' : ''}
              />
              {errors.issueDate && (
                <p className="text-theme-error text-sm mt-1">{errors.issueDate}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Due Date *
              </label>
              <DatePicker
                selected={formData.dueDate}
                onChange={(date) => handleInputChange('dueDate', date)}
                dateFormat="MM/dd/yyyy"
                minDate={new Date()}
                disabled={loading}
                required
                className={errors.dueDate ? 'border-theme-error' : ''}
              />
              {errors.dueDate && (
                <p className="text-theme-error text-sm mt-1">{errors.dueDate}</p>
              )}
            </div>
          </div>

          {/* Description */}
          <div>
            <label className="label-theme">
              Description *
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => handleInputChange('description', e.target.value)}
              className={`input-theme ${errors.description ? 'border-theme-error' : ''}`}
              rows={3}
              placeholder="Invoice description..."
              disabled={loading}
              required
            />
            {errors.description && (
              <p className="text-theme-error text-sm mt-1">{errors.description}</p>
            )}
          </div>

          {/* Line Items */}
          <div>
            <div className="flex justify-between items-center mb-4">
              <label className="label-theme">Line Items</label>
              <button
                type="button"
                onClick={addLineItem}
                className="btn-theme btn-theme-secondary text-sm"
                disabled={loading}
              >
                Add Item
              </button>
            </div>

            <div className="space-y-3">
              {formData.lineItems.map((item, index) => (
                <div key={index} className="grid grid-cols-1 md:grid-cols-12 gap-3 p-4 border border-theme rounded-lg">
                  <div className="md:col-span-5">
                    <input
                      type="text"
                      value={item.description}
                      onChange={(e) => updateLineItem(index, 'description', e.target.value)}
                      className="input-theme text-sm"
                      placeholder="Item description"
                      disabled={loading}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <input
                      type="number"
                      min="1"
                      value={item.quantity}
                      onChange={(e) => updateLineItem(index, 'quantity', parseInt(e.target.value) || 1)}
                      className="input-theme text-sm"
                      placeholder="Qty"
                      disabled={loading}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={item.unitPrice}
                      onChange={(e) => updateLineItem(index, 'unitPrice', parseFloat(e.target.value) || 0)}
                      className="input-theme text-sm"
                      placeholder="Unit price"
                      disabled={loading}
                    />
                  </div>
                  <div className="md:col-span-2">
                    <input
                      type="text"
                      value={`$${item.total.toFixed(2)}`}
                      className="input-theme text-sm bg-theme-background-secondary"
                      disabled
                      readOnly
                    />
                  </div>
                  <div className="md:col-span-1">
                    {formData.lineItems.length > 1 && (
                      <button
                        type="button"
                        onClick={() => removeLineItem(index)}
                        className="text-theme-error hover:text-theme-error-dark p-1"
                        disabled={loading}
                      >
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                        </svg>
                      </button>
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

          {/* Action Buttons */}
          <div className="flex justify-end space-x-3 pt-6 border-t border-theme">
            <button
              type="button"
              onClick={onClose}
              className="btn-theme btn-theme-secondary"
              disabled={loading}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="btn-theme btn-theme-primary"
              disabled={loading}
            >
              {loading ? 'Creating...' : 'Create Invoice'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default CreateInvoiceModal;
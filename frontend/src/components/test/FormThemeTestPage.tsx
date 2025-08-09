import React, { useState } from 'react';

export const FormThemeTestPage: React.FC = () => {
  const [formData, setFormData] = useState({
    text: '',
    email: '',
    password: '',
    textarea: '',
    select: 'option1',
    checkbox: false,
    radio: 'option1',
    toggle: false,
    range: 50,
    file: null as File | null,
  });

  const [errors, setErrors] = useState<Record<string, string>>({});
  const [showValidation, setShowValidation] = useState(false);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setShowValidation(true);
    
    // Simple validation example
    const newErrors: Record<string, string> = {};
    if (!formData.text.trim()) newErrors.text = 'Name is required';
    if (!formData.email.trim()) newErrors.email = 'Email is required';
    if (formData.email && !/\S+@\S+\.\S+/.test(formData.email)) newErrors.email = 'Email is invalid';
    if (!formData.password) newErrors.password = 'Password is required';
    if (formData.password && formData.password.length < 6) newErrors.password = 'Password must be at least 6 characters';
    
    setErrors(newErrors);
    
    if (Object.keys(newErrors).length === 0) {
      alert('Form submitted successfully! Check console for data.');
      console.log('Form Data:', formData);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    
    if (type === 'checkbox') {
      setFormData(prev => ({ ...prev, [name]: (e.target as HTMLInputElement).checked }));
    } else if (type === 'file') {
      const files = (e.target as HTMLInputElement).files;
      setFormData(prev => ({ ...prev, [name]: files?.[0] || null }));
    } else {
      setFormData(prev => ({ ...prev, [name]: value }));
    }
    
    // Clear error when user starts typing
    if (name in errors && errors[name as keyof typeof errors]) {
      setErrors(prev => ({ ...prev, [name]: '' }));
    }
  };

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-8">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-theme-primary mb-2">
          Form Theme Test Page
        </h1>
        <p className="text-theme-secondary">
          Comprehensive demonstration of all themed form elements in light and dark modes
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Text Input */}
          <div className="form-group-theme">
            <label className="label-theme">
              Full Name <span className="required">*</span>
            </label>
            <input
              type="text"
              name="text"
              value={formData.text}
              onChange={handleInputChange}
              className={`input-theme ${errors.text ? 'error' : formData.text ? 'success' : ''}`}
              placeholder="Enter your full name"
            />
            {errors.text && <div className="form-error-theme">{errors.text}</div>}
            {formData.text && !errors.text && <div className="form-success-theme">Looks good!</div>}
            <div className="form-help-theme">This field is required for account creation</div>
          </div>

          {/* Email Input */}
          <div className="form-group-theme">
            <label className="label-theme">
              Email Address <span className="required">*</span>
            </label>
            <div className="form-field-icon">
              <input
                type="email"
                name="email"
                value={formData.email}
                onChange={handleInputChange}
                className={`input-theme ${errors.email ? 'error' : formData.email && /\S+@\S+\.\S+/.test(formData.email) ? 'success' : ''}`}
                placeholder="Enter your email"
              />
              <span className="form-icon">📧</span>
            </div>
            {errors.email && <div className="form-error-theme">{errors.email}</div>}
            {formData.email && !errors.email && <div className="form-success-theme">Valid email format</div>}
          </div>

          {/* Password Input */}
          <div className="form-group-theme">
            <label className="label-theme">
              Password <span className="required">*</span>
            </label>
            <input
              type="password"
              name="password"
              value={formData.password}
              onChange={handleInputChange}
              className={`input-theme ${errors.password ? 'error' : formData.password && formData.password.length >= 6 ? 'success' : ''}`}
              placeholder="Enter password"
            />
            {errors.password && <div className="form-error-theme">{errors.password}</div>}
            {formData.password && formData.password.length >= 6 && <div className="form-success-theme">Strong password</div>}
          </div>

          {/* Select Dropdown */}
          <div className="form-group-theme">
            <label className="label-theme">
              Account Type
            </label>
            <select
              name="select"
              value={formData.select}
              onChange={handleInputChange}
              className="select-theme"
            >
              <option value="option1">Personal Account</option>
              <option value="option2">Business Account</option>
              <option value="option3">Enterprise Account</option>
              <option value="option4">Developer Account</option>
            </select>
            <div className="form-help-theme">Choose the type that best fits your needs</div>
          </div>
        </div>

        {/* Textarea */}
        <div className="form-group-theme">
          <label className="label-theme">
            Description
          </label>
          <textarea
            name="textarea"
            value={formData.textarea}
            onChange={handleInputChange}
            className="textarea-theme"
            placeholder="Tell us about yourself or your business..."
            rows={4}
          />
          <div className="form-help-theme">Optional: Provide additional context about your account</div>
        </div>

        {/* Checkbox Options */}
        <fieldset className="fieldset-theme">
          <legend className="legend-theme">Preferences</legend>
          <div className="space-y-4">
            <div className="flex items-center space-x-3">
              <input
                type="checkbox"
                id="checkbox1"
                name="checkbox"
                checked={formData.checkbox}
                onChange={handleInputChange}
                className="checkbox-theme"
              />
              <label htmlFor="checkbox1" className="text-theme-primary cursor-pointer">
                Subscribe to newsletter and product updates
              </label>
            </div>

            <div className="flex items-center space-x-3">
              <input
                type="checkbox"
                id="checkbox2"
                className="checkbox-theme"
                disabled
              />
              <label htmlFor="checkbox2" className="text-theme-tertiary">
                Enable advanced analytics (Coming soon)
              </label>
            </div>
          </div>
        </fieldset>

        {/* Radio Button Group */}
        <fieldset className="fieldset-theme">
          <legend className="legend-theme">Billing Frequency</legend>
          <div className="space-y-3">
            <div className="flex items-center space-x-3">
              <input
                type="radio"
                id="monthly"
                name="radio"
                value="monthly"
                checked={formData.radio === 'monthly'}
                onChange={handleInputChange}
                className="radio-theme"
              />
              <label htmlFor="monthly" className="text-theme-primary cursor-pointer">
                Monthly billing ($29/month)
              </label>
            </div>
            <div className="flex items-center space-x-3">
              <input
                type="radio"
                id="yearly"
                name="radio"
                value="yearly"
                checked={formData.radio === 'yearly'}
                onChange={handleInputChange}
                className="radio-theme"
              />
              <label htmlFor="yearly" className="text-theme-primary cursor-pointer">
                Yearly billing ($290/year - Save 17%)
              </label>
            </div>
            <div className="flex items-center space-x-3">
              <input
                type="radio"
                id="lifetime"
                name="radio"
                value="lifetime"
                className="radio-theme"
                disabled
              />
              <label htmlFor="lifetime" className="text-theme-tertiary cursor-not-allowed">
                Lifetime access ($999 - Limited availability)
              </label>
            </div>
          </div>
        </fieldset>

        {/* Toggle Switches */}
        <div className="form-group-theme">
          <label className="label-theme">Notification Settings</label>
          <div className="space-y-4">
            <div className="flex items-center justify-between p-3 bg-theme-surface border border-theme rounded-lg">
              <div>
                <div className="font-medium text-theme-primary">Email Notifications</div>
                <div className="text-sm text-theme-secondary">Receive important updates via email</div>
              </div>
              <input
                type="checkbox"
                name="toggle"
                checked={formData.toggle}
                onChange={handleInputChange}
                className="toggle-theme"
              />
            </div>
            
            <div className="flex items-center justify-between p-3 bg-theme-surface border border-theme rounded-lg">
              <div>
                <div className="font-medium text-theme-primary">SMS Notifications</div>
                <div className="text-sm text-theme-secondary">Receive urgent alerts via SMS</div>
              </div>
              <input
                type="checkbox"
                className="toggle-theme"
                disabled
              />
            </div>
          </div>
        </div>

        {/* Range Slider */}
        <div className="form-group-theme">
          <label className="label-theme">
            Storage Allocation: {formData.range}GB
          </label>
          <input
            type="range"
            name="range"
            min="10"
            max="100"
            value={formData.range}
            onChange={handleInputChange}
            className="range-theme"
          />
          <div className="flex justify-between text-xs text-theme-tertiary mt-1">
            <span>10GB</span>
            <span>100GB</span>
          </div>
        </div>

        {/* File Input */}
        <div className="form-group-theme">
          <label className="label-theme">
            Profile Picture
          </label>
          <input
            type="file"
            name="file"
            onChange={handleInputChange}
            accept="image/*"
            className="file-theme"
          />
          <div className="form-help-theme">Upload a profile picture (JPG, PNG, max 5MB)</div>
        </div>

        {/* Submit Button */}
        <div className="flex items-center justify-between pt-6 border-t border-theme">
          <button
            type="button"
            onClick={() => {
              setFormData({
                text: '',
                email: '',
                password: '',
                textarea: '',
                select: 'option1',
                checkbox: false,
                radio: 'option1',
                toggle: false,
                range: 50,
                file: null,
              });
              setErrors({});
              setShowValidation(false);
            }}
            className="btn-theme btn-theme-secondary"
          >
            Clear Form
          </button>
          
          <div className="flex space-x-4">
            <button
              type="button"
              className="btn-theme btn-theme-secondary"
              onClick={() => setShowValidation(!showValidation)}
            >
              {showValidation ? 'Hide' : 'Show'} Validation
            </button>
            <button
              type="submit"
              className="btn-theme btn-theme-primary"
            >
              Create Account
            </button>
          </div>
        </div>
      </form>

      {/* Current Form State Display */}
      <div className="card-theme p-6 mt-8">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Form State (for testing)</h3>
        <pre className="text-sm text-theme-secondary bg-theme-background-tertiary p-4 rounded-md overflow-auto">
          {JSON.stringify({ formData, errors, showValidation }, null, 2)}
        </pre>
      </div>
    </div>
  );
};
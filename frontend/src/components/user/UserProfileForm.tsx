import React, { useState } from 'react';
import { DatePicker } from '../common/DatePicker';

interface UserProfileFormProps {
  initialData?: UserProfileData;
  onSubmit: (data: UserProfileData) => void;
  onCancel: () => void;
  loading?: boolean;
}

export interface UserProfileData {
  firstName: string;
  lastName: string;
  email: string;
  phone: string;
  birthDate: Date | null;
  joinDate: Date | null;
  timezone: string;
  bio: string;
  company: string;
  position: string;
  lastLoginDate: Date | null;
}

export const UserProfileForm: React.FC<UserProfileFormProps> = ({
  initialData,
  onSubmit,
  onCancel,
  loading = false,
}) => {
  const [formData, setFormData] = useState<UserProfileData>({
    firstName: initialData?.firstName || '',
    lastName: initialData?.lastName || '',
    email: initialData?.email || '',
    phone: initialData?.phone || '',
    birthDate: initialData?.birthDate || null,
    joinDate: initialData?.joinDate || new Date(),
    timezone: initialData?.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone,
    bio: initialData?.bio || '',
    company: initialData?.company || '',
    position: initialData?.position || '',
    lastLoginDate: initialData?.lastLoginDate || null,
  });

  const [errors, setErrors] = useState<Record<string, string>>({});

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.firstName.trim()) {
      newErrors.firstName = 'First name is required';
    }

    if (!formData.lastName.trim()) {
      newErrors.lastName = 'Last name is required';
    }

    if (!formData.email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!/\S+@\S+\.\S+/.test(formData.email)) {
      newErrors.email = 'Please enter a valid email address';
    }

    if (formData.birthDate && formData.birthDate > new Date()) {
      newErrors.birthDate = 'Birth date cannot be in the future';
    }

    if (formData.birthDate && formData.joinDate && formData.birthDate > formData.joinDate) {
      newErrors.birthDate = 'Birth date cannot be after join date';
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

  const handleInputChange = (field: keyof UserProfileData, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear error when user starts typing
    if (Object.prototype.hasOwnProperty.call(errors, field)) {
      setErrors(prev => ({ ...prev, [field]: '' }));
    }
  };

  return (
    <div className="max-w-4xl mx-auto">
      <form onSubmit={handleSubmit} className="space-y-8">
        {/* Basic Information */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">Basic Information</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="label-theme">
                First Name *
              </label>
              <input
                type="text"
                value={formData.firstName}
                onChange={(e) => handleInputChange('firstName', e.target.value)}
                className={`input-theme ${errors.firstName ? 'border-theme-error' : ''}`}
                placeholder="Enter first name"
                disabled={loading}
                required
              />
              {errors.firstName && (
                <p className="text-theme-error text-sm mt-1">{errors.firstName}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Last Name *
              </label>
              <input
                type="text"
                value={formData.lastName}
                onChange={(e) => handleInputChange('lastName', e.target.value)}
                className={`input-theme ${errors.lastName ? 'border-theme-error' : ''}`}
                placeholder="Enter last name"
                disabled={loading}
                required
              />
              {errors.lastName && (
                <p className="text-theme-error text-sm mt-1">{errors.lastName}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Email *
              </label>
              <input
                type="email"
                value={formData.email}
                onChange={(e) => handleInputChange('email', e.target.value)}
                className={`input-theme ${errors.email ? 'border-theme-error' : ''}`}
                placeholder="Enter email address"
                disabled={loading}
                required
              />
              {errors.email && (
                <p className="text-theme-error text-sm mt-1">{errors.email}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Phone
              </label>
              <input
                type="tel"
                value={formData.phone}
                onChange={(e) => handleInputChange('phone', e.target.value)}
                className="input-theme"
                placeholder="Enter phone number"
                disabled={loading}
              />
            </div>
          </div>
        </div>

        {/* Dates */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">Important Dates</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <label className="label-theme">
                Birth Date
              </label>
              <DatePicker
                selected={formData.birthDate}
                onChange={(date) => handleInputChange('birthDate', date)}
                dateFormat="MM/dd/yyyy"
                maxDate={new Date()}
                showYearDropdown
                showMonthDropdown
                dropdownMode="select"
                placeholderText="Select birth date"
                disabled={loading}
                className={errors.birthDate ? 'border-theme-error' : ''}
                isClearable={true}
              />
              {errors.birthDate && (
                <p className="text-theme-error text-sm mt-1">{errors.birthDate}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Join Date
              </label>
              <DatePicker
                selected={formData.joinDate}
                onChange={(date) => handleInputChange('joinDate', date)}
                dateFormat="MM/dd/yyyy"
                maxDate={new Date()}
                showYearDropdown
                showMonthDropdown
                dropdownMode="select"
                placeholderText="Select join date"
                disabled={loading}
                isClearable={false}
              />
            </div>

            <div>
              <label className="label-theme">
                Last Login
              </label>
              <DatePicker
                selected={formData.lastLoginDate}
                onChange={(date) => handleInputChange('lastLoginDate', date)}
                dateFormat="MM/dd/yyyy HH:mm"
                showTimeSelect
                timeFormat="HH:mm"
                timeIntervals={15}
                maxDate={new Date()}
                showYearDropdown
                showMonthDropdown
                dropdownMode="select"
                placeholderText="Last login date/time"
                disabled={loading}
                isClearable={true}
              />
            </div>
          </div>
        </div>

        {/* Professional Information */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">Professional Information</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="label-theme">
                Company
              </label>
              <input
                type="text"
                value={formData.company}
                onChange={(e) => handleInputChange('company', e.target.value)}
                className="input-theme"
                placeholder="Enter company name"
                disabled={loading}
              />
            </div>

            <div>
              <label className="label-theme">
                Position
              </label>
              <input
                type="text"
                value={formData.position}
                onChange={(e) => handleInputChange('position', e.target.value)}
                className="input-theme"
                placeholder="Enter job title"
                disabled={loading}
              />
            </div>

            <div className="md:col-span-2">
              <label className="label-theme">
                Timezone
              </label>
              <select
                value={formData.timezone}
                onChange={(e) => handleInputChange('timezone', e.target.value)}
                className="select-theme"
                disabled={loading}
              >
                <option value="America/New_York">Eastern Time (ET)</option>
                <option value="America/Chicago">Central Time (CT)</option>
                <option value="America/Denver">Mountain Time (MT)</option>
                <option value="America/Los_Angeles">Pacific Time (PT)</option>
                <option value="Europe/London">Greenwich Mean Time (GMT)</option>
                <option value="Europe/Paris">Central European Time (CET)</option>
                <option value="Asia/Tokyo">Japan Standard Time (JST)</option>
                <option value="Australia/Sydney">Australian Eastern Time (AET)</option>
              </select>
            </div>
          </div>
        </div>

        {/* Bio */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">About</h3>
          
          <div>
            <label className="label-theme">
              Bio
            </label>
            <textarea
              value={formData.bio}
              onChange={(e) => handleInputChange('bio', e.target.value)}
              className="input-theme"
              rows={4}
              placeholder="Tell us about yourself..."
              disabled={loading}
            />
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex justify-end space-x-4">
          <button
            type="button"
            onClick={onCancel}
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
            {loading ? 'Saving...' : 'Save Profile'}
          </button>
        </div>
      </form>
    </div>
  );
};

export default UserProfileForm;
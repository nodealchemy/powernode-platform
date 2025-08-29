import React from 'react';
import { DatePicker } from '@/shared/components/ui/DatePicker';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';

interface UserProfileFormProps {
  initialData?: UserProfileData;
  onSubmit: (data: UserProfileData) => Promise<void>;
  onCancel: () => void;
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
}) => {
  const defaultValues: UserProfileData = {
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
  };

  const validationRules: FormValidationRules = {
    firstName: {
      required: true,
      minLength: 1,
      maxLength: 50,
    },
    lastName: {
      required: true,
      minLength: 1,
      maxLength: 50,
    },
    email: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
    },
    phone: {
      maxLength: 20,
    },
    company: {
      maxLength: 100,
    },
    position: {
      maxLength: 100,
    },
    bio: {
      maxLength: 500,
    },
    birthDate: {
      custom: (value: unknown) => {
        const date = value as Date | null;
        if (date && date > new Date()) {
          return 'Birth date cannot be in the future';
        }
        return null;
      }
    }
  };

  const form = useForm<UserProfileData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Profile updated successfully',
  });

  // Custom handler for date fields since DatePicker doesn't use standard events
  const handleDateChange = (field: keyof UserProfileData, value: Date | null) => {
    form.setValue(field, value);
  };

  return (
    <div className="max-w-4xl mx-auto">
      <form onSubmit={form.handleSubmit} className="space-y-8">
        {/* Basic Information */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">Basic Information</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <FormField
              label="First Name"
              type="text"
              value={form.values.firstName}
              onChange={(value) => form.setValue('firstName', value)}
              error={form.errors.firstName}
              placeholder="Enter first name"
              disabled={form.isSubmitting}
              required
            />

            <FormField
              label="Last Name"
              type="text"
              value={form.values.lastName}
              onChange={(value) => form.setValue('lastName', value)}
              error={form.errors.lastName}
              placeholder="Enter last name"
              disabled={form.isSubmitting}
              required
            />

            <FormField
              label="Email"
              type="email"
              value={form.values.email}
              onChange={(value) => form.setValue('email', value)}
              error={form.errors.email}
              placeholder="Enter email address"
              disabled={form.isSubmitting}
              required
            />

            <FormField
              label="Phone"
              type="tel"
              value={form.values.phone}
              onChange={(value) => form.setValue('phone', value)}
              placeholder="Enter phone number"
              disabled={form.isSubmitting}
            />
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
                selected={form.values.birthDate}
                onChange={(date) => handleDateChange('birthDate', date)}
                dateFormat="MM/dd/yyyy"
                maxDate={new Date()}
                showYearDropdown
                showMonthDropdown
                dropdownMode="select"
                placeholderText="Select birth date"
                disabled={form.isSubmitting}
                className={form.errors.birthDate ? 'border-theme-error' : ''}
                isClearable={true}
              />
              {form.errors.birthDate && (
                <p className="text-theme-error text-sm mt-1">{form.errors.birthDate}</p>
              )}
            </div>

            <div>
              <label className="label-theme">
                Join Date
              </label>
              <DatePicker
                selected={form.values.joinDate}
                onChange={(date) => handleDateChange('joinDate', date)}
                dateFormat="MM/dd/yyyy"
                maxDate={new Date()}
                showYearDropdown
                showMonthDropdown
                dropdownMode="select"
                placeholderText="Select join date"
                disabled={form.isSubmitting}
                isClearable={false}
              />
            </div>

            <div>
              <label className="label-theme">
                Last Login
              </label>
              <DatePicker
                selected={form.values.lastLoginDate}
                onChange={(date) => handleDateChange('lastLoginDate', date)}
                dateFormat="MM/dd/yyyy HH:mm"
                showTimeSelect
                timeFormat="HH:mm"
                timeIntervals={15}
                maxDate={new Date()}
                showYearDropdown
                showMonthDropdown
                dropdownMode="select"
                placeholderText="Last login date/time"
                disabled={form.isSubmitting}
                isClearable={true}
              />
            </div>
          </div>
        </div>

        {/* Professional Information */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">Professional Information</h3>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <FormField
              label="Company"
              type="text"
              value={form.values.company}
              onChange={(value) => form.setValue('company', value)}
              placeholder="Enter company name"
              disabled={form.isSubmitting}
            />

            <FormField
              label="Position"
              type="text"
              value={form.values.position}
              onChange={(value) => form.setValue('position', value)}
              placeholder="Enter job title"
              disabled={form.isSubmitting}
            />

            <div className="md:col-span-2">
              <FormField
                label="Timezone"
                type="select"
                value={form.values.timezone}
                onChange={(value) => form.setValue('timezone', value)}
                disabled={form.isSubmitting}
                options={[
                  { value: "America/New_York", label: "Eastern Time (ET)" },
                  { value: "America/Chicago", label: "Central Time (CT)" },
                  { value: "America/Denver", label: "Mountain Time (MT)" },
                  { value: "America/Los_Angeles", label: "Pacific Time (PT)" },
                  { value: "Europe/London", label: "Greenwich Mean Time (GMT)" },
                  { value: "Europe/Paris", label: "Central European Time (CET)" },
                  { value: "Asia/Tokyo", label: "Japan Standard Time (JST)" },
                  { value: "Australia/Sydney", label: "Australian Eastern Time (AET)" }
                ]}
              />
            </div>
          </div>
        </div>

        {/* Bio */}
        <div className="card-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-6">About</h3>
          
          <FormField
            label="Bio"
            type="textarea"
            value={form.values.bio}
            onChange={(value) => form.setValue('bio', value)}
            error={form.errors.bio}
            rows={4}
            placeholder="Tell us about yourself..."
            disabled={form.isSubmitting}
          />
        </div>

        {/* Action Buttons */}
        <div className="flex justify-end space-x-4">
          <Button
            type="button"
            onClick={onCancel}
            variant="secondary"
            disabled={form.isSubmitting}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            variant="primary"
            disabled={form.isSubmitting || !form.isValid}
            loading={form.isSubmitting}
          >
            Save Profile
          </Button>
        </div>
      </form>
    </div>
  );
};

export default UserProfileForm;
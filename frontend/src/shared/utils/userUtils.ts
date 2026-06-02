/**
 * User Utility Functions
 *
 * Helper functions for working with User objects after schema migration
 * from first_name/last_name to consolidated name field.
 */

export interface UserWithName {
  name?: string;
  full_name?: string;
}

/**
 * Get user initials from full name
 *
 * @param user - User object with name field
 * @returns Two-letter initials (uppercase) or 'U' if no name
 *
 * @example
 * getUserInitials({ name: 'John Doe' }) // 'JD'
 * getUserInitials({ name: 'Madonna' }) // 'M'
 * getUserInitials({ name: '' }) // 'U'
 * getUserInitials(null) // 'U'
 */
export const getUserInitials = (user?: UserWithName | null): string => {
  const fullName = user?.name || user?.full_name;

  if (!fullName) return 'U';

  const parts = fullName.trim().split(/\s+/);

  // Single word name (e.g., "Madonna")
  if (parts.length === 1) {
    return parts[0][0].toUpperCase();
  }

  // Multiple words - use first and last
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
};

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
  // Trim each field before falling back so a whitespace-only name neither
  // shadows a real full_name nor crashes the split below (a blank name is
  // truthy but trims to '', whose split yields [''] -> parts[0][0] === undefined).
  const fullName = user?.name?.trim() || user?.full_name?.trim();

  if (!fullName) return 'U';

  const parts = fullName.split(/\s+/);

  // Single word name (e.g., "Madonna")
  if (parts.length === 1) {
    return parts[0][0].toUpperCase();
  }

  // Multiple words - use first and last
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
};

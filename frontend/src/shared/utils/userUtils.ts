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

/**
 * Get first name (first word of full name)
 *
 * @param user - User object with name field
 * @returns First word of name or empty string
 *
 * @example
 * getFirstName({ name: 'John Doe' }) // 'John'
 * getFirstName({ name: 'Madonna' }) // 'Madonna'
 */
export const getFirstName = (user?: UserWithName | null): string => {
  const fullName = user?.name || user?.full_name;
  return fullName?.split(' ')[0] || '';
};

/**
 * Get last name (last word of full name)
 *
 * @param user - User object with name field
 * @returns Last word of name or empty string
 *
 * @example
 * getLastName({ name: 'John Doe' }) // 'Doe'
 * getLastName({ name: 'Madonna' }) // '' (single word)
 */
export const getLastName = (user?: UserWithName | null): string => {
  const fullName = user?.name || user?.full_name;
  const parts = fullName?.split(' ') || [];
  return parts.length > 1 ? parts[parts.length - 1] : '';
};

/**
 * Format user display name
 *
 * @param user - User object with name field
 * @param fallback - Text to show if no name available
 * @returns Formatted name or fallback
 *
 * @example
 * formatUserName({ name: 'John Doe' }) // 'John Doe'
 * formatUserName(undefined, 'Unknown User') // 'Unknown User'
 * formatUserName(null, 'Guest') // 'Guest'
 */
export const formatUserName = (user?: UserWithName | null, fallback: string = 'Unknown'): string => {
  return user?.name || user?.full_name || fallback;
};

/**
 * Check if user has a complete name
 *
 * @param user - User object with name field
 * @returns true if user has a non-empty name
 */
export const hasCompleteName = (user?: UserWithName | null): boolean => {
  const fullName = user?.name || user?.full_name;
  return !!fullName?.trim();
};

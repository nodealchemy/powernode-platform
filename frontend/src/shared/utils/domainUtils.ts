/**
 * Domain utility functions for handling cross-domain authentication scenarios
 */

/**
 * Get the current domain (including port if non-standard)
 */
export const getCurrentDomain = (): string => {
  const { hostname, port, protocol } = window.location;
  const standardPorts = { 'http:': '80', 'https:': '443' };
  
  if (port && port !== standardPorts[protocol as keyof typeof standardPorts]) {
    return `${hostname}:${port}`;
  }
  return hostname;
};

/**
 * Get the stored domain from localStorage (where tokens might exist)
 */
export const getStoredAuthDomain = (): string | null => {
  try {
    return localStorage.getItem('authDomain');
  } catch (_error) {
    return null;
  }
};

/**
 * Set the current domain as the auth domain
 */
export const setAuthDomain = (domain?: string): void => {
  try {
    const currentDomain = domain || getCurrentDomain();
    localStorage.setItem('authDomain', currentDomain);
  } catch (_error) {
    // Handle localStorage errors gracefully
  }
};

/**
 * Check if we're on a different domain than where auth was established
 */
export const isDomainChanged = (): boolean => {
  const currentDomain = getCurrentDomain();
  const storedDomain = getStoredAuthDomain();
  
  return storedDomain !== null && storedDomain !== currentDomain;
};

/**
 * Clear domain-related storage (useful for logout)
 */
export const clearAuthDomain = (): void => {
  try {
    localStorage.removeItem('authDomain');
  } catch (_error) {
    // Handle localStorage errors gracefully
  }
};

/**
 * Generate a user-friendly message about domain change
 */
export const getDomainChangeMessage = (): { title: string; message: string; previousDomain?: string } => {
  const currentDomain = getCurrentDomain();
  const storedDomain = getStoredAuthDomain();
  
  return {
    title: 'Domain Changed - Re-authentication Required',
    message: `You're now accessing Powernode from ${currentDomain}. Due to security requirements, you'll need to sign in again on this domain.`,
    previousDomain: storedDomain || undefined
  };
};
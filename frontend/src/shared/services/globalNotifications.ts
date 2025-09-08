// Simple global notifications service
export const globalNotifications = {
  success: (message: string) => {
    console.log('SUCCESS:', message);
    // TODO: Integrate with existing notification system
  },
  
  error: (message: string) => {
    console.error('ERROR:', message);
    // TODO: Integrate with existing notification system
  },
  
  info: (message: string) => {
    console.info('INFO:', message);
    // TODO: Integrate with existing notification system
  },
  
  warning: (message: string) => {
    console.warn('WARNING:', message);
    // TODO: Integrate with existing notification system
  }
};
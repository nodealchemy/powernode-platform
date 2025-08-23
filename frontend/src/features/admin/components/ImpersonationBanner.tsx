import React from 'react';
import { Button } from '@/shared/components/ui/Button';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { stopImpersonation } from '@/shared/services/slices/authSlice';

const ImpersonationBanner: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const { impersonation, isLoading } = useSelector((state: RootState) => state.auth);


  if (!impersonation.isImpersonating) {
    return null;
  }

  // Show loading state if impersonating but user details not loaded yet
  const isLoadingImpersonation = impersonation.isImpersonating && !impersonation.impersonatedUser;

  const handleStopImpersonation = async () => {
    try {
      await dispatch(stopImpersonation()).unwrap();
      // Refresh the page after successful impersonation stop to ensure clean state
      window.location.reload();
    } catch (error) {
    }
  };

  return (
    <div className="bg-theme-warning bg-opacity-10 border-b border-theme-warning border-opacity-30 px-4 py-2 text-sm">
      <div className="flex items-center justify-between max-w-7xl mx-auto">
        <div className="flex items-center space-x-3">
          <div className="flex items-center space-x-2">
            <svg className="w-5 h-5 text-theme-warning" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
            </svg>
            <span className="text-theme-warning font-medium">
              Impersonation Active
            </span>
          </div>
          <div className="text-theme-warning opacity-90">
            {isLoadingImpersonation ? (
              'Restoring impersonation session...'
            ) : (
              <>
                You are viewing as{' '}
                <span className="font-semibold">
                  {impersonation.impersonatedUser?.first_name} {impersonation.impersonatedUser?.last_name}
                </span>
                {' '}({impersonation.impersonatedUser?.email})
              </>
            )}
          </div>
          {impersonation.expiresAt && (
            <div className="text-theme-warning opacity-80 text-xs">
              Expires: {new Date(impersonation.expiresAt).toLocaleString()}
            </div>
          )}
        </div>
        
        <Button onClick={handleStopImpersonation} disabled={isLoading || isLoadingImpersonation} variant="outline" size="sm">
          {isLoading ? (
            <>
              <svg className="animate-spin -ml-1 mr-2 h-3 w-3 text-theme-warning" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Stopping...
            </>
          ) : (
            <>
              <svg className="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
              Stop Impersonation
            </>
          )}
        </Button>
      </div>
    </div>
  );
};

export default ImpersonationBanner;
import React from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { clearMaintenanceMode } from '@/shared/services/slices/uiSlice';

/**
 * Full-page overlay shown when api.ts's response interceptor sees a 503
 * carrying { code: 'maintenance_mode' } — Admin::MaintenanceMode's gate
 * (server/app/controllers/concerns/authentication.rb). Renders nothing
 * otherwise. "Retry" clears the flag and reloads, which either re-triggers
 * the overlay (still down) or resumes the app (maintenance lifted).
 */
export const MaintenanceScreen: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const maintenance = useSelector((state: RootState) => state.ui.maintenance);

  if (!maintenance?.active) return null;

  const handleRetry = () => {
    dispatch(clearMaintenanceMode());
    window.location.reload();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-theme-background">
      <div className="max-w-md w-full mx-4 p-8 rounded-xl border border-theme bg-theme-surface text-center space-y-4">
        <div className="text-5xl">🔧</div>
        <h1 className="text-xl font-semibold text-theme-primary">System Under Maintenance</h1>
        <p className="text-theme-secondary">
          {maintenance.message || 'System is under maintenance'}
        </p>
        {maintenance.estimatedCompletion && (
          <p className="text-sm text-theme-secondary">
            <span className="font-medium">Estimated completion:</span> {maintenance.estimatedCompletion}
          </p>
        )}
        <button
          onClick={handleRetry}
          className="btn-theme btn-theme-primary"
        >
          Retry
        </button>
      </div>
    </div>
  );
};

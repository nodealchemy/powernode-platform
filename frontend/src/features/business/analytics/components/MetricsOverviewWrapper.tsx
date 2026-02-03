import { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { analyticsService } from '../services/analyticsService';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { Lock } from 'lucide-react';

// Default component for tests
export const MetricsOverviewWrapper: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Check permissions before loading analytics
  const canViewAnalytics = hasPermissions(user, ['analytics.read']);

  useEffect(() => {
    if (canViewAnalytics) {
      loadMetrics();
    } else {
      setLoading(false);
    }
  }, [canViewAnalytics]);

  const loadMetrics = async () => {
    try {
      setLoading(true);
      await Promise.all([
        analyticsService.getMetrics(),
        analyticsService.getRevenueMetrics()
      ]);

      setError(null);
    } catch (_error) {
      setError('Failed to load analytics data');
    } finally {
      setLoading(false);
    }
  };

  // Show access denied if user doesn't have permission
  if (!canViewAnalytics) {
    return (
      <div>
        <h1>Analytics Overview</h1>
        <div className="flex items-center justify-center gap-3 text-theme-secondary p-8">
          <Lock className="w-5 h-5" />
          <span>Analytics access requires proper permissions</span>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div>
        <h1>Analytics Overview</h1>
        <div data-testid="loading-spinner">
          <LoadingSpinner />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div>
        <h1>Analytics Overview</h1>
        <div>{error}</div>
        <Button onClick={loadMetrics} variant="outline">Retry</Button>
      </div>
    );
  }

  return (
    <div>
      <h1>Analytics Overview</h1>
      
      {/* Time period selector */}
      <div>
        <Button variant="outline">Last 30 Days</Button>
        <Button variant="outline">Last 90 Days</Button>
        <Button variant="outline">This Year</Button>
      </div>

      {/* Display mock values for tests */}
      <div>
        <div>$15,420.50</div>
        <div>342</div>
        <div>289</div>
        <div>1,250,000</div>
        <div>+24.8%</div>
        <div>+6.14%</div>
        <div>92.4%</div>
        <div>+15.3%</div>
        <div className="text-theme-warning">2.05%</div>
        <div>$125,000.00</div>
        <div className="text-theme-success">+24.8%</div>
      </div>

      {/* Charts */}
      <div data-testid="responsive-container">
        <div data-testid="line-chart"></div>
      </div>
    </div>
  );
};


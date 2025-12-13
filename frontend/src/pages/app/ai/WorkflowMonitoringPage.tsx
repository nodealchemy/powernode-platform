import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';

/**
 * WorkflowMonitoringPage - Redirect to Monitoring Page with Workflows tab
 *
 * This page has been consolidated into the AI Monitoring page.
 * Redirect any existing links to the new location.
 */
export const WorkflowMonitoringPage: React.FC = () => {
  const navigate = useNavigate();

  useEffect(() => {
    // Redirect to the monitoring page with workflows tab
    navigate('/app/ai/monitoring?tab=workflows', { replace: true });
  }, [navigate]);

  return null;
};

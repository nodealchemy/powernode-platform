import { render, screen } from '@testing-library/react';
import { AuditLogAnalytics } from './AuditLogAnalytics';

jest.mock('./AuditLogChart', () => ({ AuditLogChart: () => null }));
jest.mock('./SecurityOverview', () => ({ SecurityOverview: () => null }));
jest.mock('./ComplianceMetrics', () => ({ ComplianceMetrics: () => null }));
jest.mock('./RiskAssessment', () => ({ RiskAssessment: () => null }));
jest.mock('./ActivityHeatmap', () => ({ ActivityHeatmap: () => null }));
jest.mock('./TopThreats', () => ({ TopThreats: () => null }));

describe('AuditLogAnalytics', () => {
  // fc-47: the sub-tab lists security events, and "Security" alone names the
  // admin settings and profile pages too.
  it('labels its security sub-tab Security Events', () => {
    render(<AuditLogAnalytics filters={{}} onFiltersChange={jest.fn()} refreshData={jest.fn()} />);

    expect(screen.getByRole('button', { name: /Security Events/ })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Security$/ })).not.toBeInTheDocument();
  });
});

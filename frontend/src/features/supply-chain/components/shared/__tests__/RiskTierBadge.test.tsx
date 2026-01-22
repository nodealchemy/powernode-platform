import { render, screen } from '@testing-library/react';
import { RiskTierBadge } from '../RiskTierBadge';

describe('RiskTierBadge', () => {
  describe('rendering risk tiers', () => {
    it('renders critical tier with correct label', () => {
      render(<RiskTierBadge tier="critical" />);
      expect(screen.getByText('Critical Risk')).toBeInTheDocument();
    });

    it('renders high tier with correct label', () => {
      render(<RiskTierBadge tier="high" />);
      expect(screen.getByText('High Risk')).toBeInTheDocument();
    });

    it('renders medium tier with correct label', () => {
      render(<RiskTierBadge tier="medium" />);
      expect(screen.getByText('Medium Risk')).toBeInTheDocument();
    });

    it('renders low tier with correct label', () => {
      render(<RiskTierBadge tier="low" />);
      expect(screen.getByText('Low Risk')).toBeInTheDocument();
    });
  });

  describe('color classes by tier', () => {
    it('applies error colors for critical tier', () => {
      const { container } = render(<RiskTierBadge tier="critical" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-error/10');
      expect(badge).toHaveClass('text-theme-error');
    });

    it('applies warning colors for high tier', () => {
      const { container } = render(<RiskTierBadge tier="high" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-warning/10');
      expect(badge).toHaveClass('text-theme-warning');
    });

    it('applies info colors for medium tier', () => {
      const { container } = render(<RiskTierBadge tier="medium" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-info/10');
      expect(badge).toHaveClass('text-theme-info');
    });

    it('applies success colors for low tier', () => {
      const { container } = render(<RiskTierBadge tier="low" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-success/10');
      expect(badge).toHaveClass('text-theme-success');
    });
  });

  describe('size prop', () => {
    it('applies medium size classes by default', () => {
      const { container } = render(<RiskTierBadge tier="critical" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies small size classes when size is sm', () => {
      const { container } = render(<RiskTierBadge tier="critical" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies medium size classes when size is md', () => {
      const { container } = render(<RiskTierBadge tier="critical" size="md" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies correct size for all tiers', () => {
      const tiers: Array<'critical' | 'high' | 'medium' | 'low'> = [
        'critical',
        'high',
        'medium',
        'low',
      ];

      tiers.forEach((tier) => {
        const { container } = render(<RiskTierBadge tier={tier} size="sm" />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('px-1.5');
        expect(badge).toHaveClass('py-0.5');
      });
    });
  });

  describe('semantic structure', () => {
    it('has proper badge styling', () => {
      const { container } = render(<RiskTierBadge tier="high" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('inline-flex');
      expect(badge).toHaveClass('items-center');
      expect(badge).toHaveClass('rounded-full');
      expect(badge).toHaveClass('font-medium');
    });

    it('renders as inline-flex for layout flexibility', () => {
      const { container } = render(<RiskTierBadge tier="medium" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('inline-flex');
    });

    it('all badges use text-xs font size', () => {
      const tiers: Array<'critical' | 'high' | 'medium' | 'low'> = [
        'critical',
        'high',
        'medium',
        'low',
      ];

      tiers.forEach((tier) => {
        const { container } = render(<RiskTierBadge tier={tier} />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('text-xs');
      });
    });
  });

  describe('label formatting', () => {
    it('includes "Risk" suffix in all labels', () => {
      const labels = [
        { tier: 'critical' as const, label: 'Critical Risk' },
        { tier: 'high' as const, label: 'High Risk' },
        { tier: 'medium' as const, label: 'Medium Risk' },
        { tier: 'low' as const, label: 'Low Risk' },
      ];

      labels.forEach(({ tier, label }) => {
        const { unmount } = render(<RiskTierBadge tier={tier} />);
        expect(screen.getByText(label)).toBeInTheDocument();
        unmount();
      });
    });

    it('capitalizes tier names in labels', () => {
      render(<RiskTierBadge tier="critical" />);
      expect(screen.getByText('Critical Risk')).toBeInTheDocument();
      expect(screen.queryByText('critical risk')).not.toBeInTheDocument();
      expect(screen.queryByText('CRITICAL RISK')).not.toBeInTheDocument();
    });
  });

  describe('combinations', () => {
    it('renders small critical risk badge', () => {
      const { container } = render(<RiskTierBadge tier="critical" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('bg-theme-error/10');
      expect(badge).toHaveClass('text-theme-error');
    });

    it('renders medium high risk badge', () => {
      const { container } = render(<RiskTierBadge tier="high" size="md" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('bg-theme-warning/10');
      expect(badge).toHaveClass('text-theme-warning');
    });

    it('renders small low risk badge', () => {
      const { container } = render(<RiskTierBadge tier="low" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('bg-theme-success/10');
      expect(badge).toHaveClass('text-theme-success');
    });
  });

  describe('size transitions', () => {
    it('transitions size from small to medium', () => {
      const { container, rerender } = render(<RiskTierBadge tier="high" size="sm" />);
      let badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');

      rerender(<RiskTierBadge tier="high" size="md" />);
      badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
    });

    it('transitions size from medium to small', () => {
      const { container, rerender } = render(<RiskTierBadge tier="medium" size="md" />);
      let badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');

      rerender(<RiskTierBadge tier="medium" size="sm" />);
      badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
    });
  });

  describe('tier transitions', () => {
    it('transitions from critical to low tier', () => {
      const { container, rerender } = render(<RiskTierBadge tier="critical" />);
      expect(screen.getByText('Critical Risk')).toBeInTheDocument();
      let badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-error/10');

      rerender(<RiskTierBadge tier="low" />);
      expect(screen.getByText('Low Risk')).toBeInTheDocument();
      badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-success/10');
    });
  });

  describe('visual consistency', () => {
    it('all tiers maintain consistent base structure', () => {
      const tiers: Array<'critical' | 'high' | 'medium' | 'low'> = [
        'critical',
        'high',
        'medium',
        'low',
      ];

      tiers.forEach((tier) => {
        const { container } = render(<RiskTierBadge tier={tier} />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('inline-flex');
        expect(badge).toHaveClass('items-center');
        expect(badge).toHaveClass('rounded-full');
        expect(badge).toHaveClass('font-medium');
        expect(badge).toHaveClass('text-xs');
      });
    });
  });
});

import { render, screen } from '@testing-library/react';
import { ActivityHeatmap, HeatmapDataPoint } from './ActivityHeatmap';

describe('ActivityHeatmap', () => {
  // Generate sample heatmap data
  const generateMockData = (): HeatmapDataPoint[] => {
    const data: HeatmapDataPoint[] = [];
    const daysOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    for (let day = 0; day < 7; day++) {
      for (let hour = 0; hour < 24; hour++) {
        let baseActivity = 5;
        // Business hours (9 AM - 5 PM) have higher activity
        if (hour >= 9 && hour <= 17) {
          baseActivity = 25;
        }
        // Weekdays (Mon-Fri) have higher activity
        if (day >= 1 && day <= 5) {
          baseActivity = Math.floor(baseActivity * 1.5);
        }

        data.push({
          day: daysOfWeek[day],
          hour,
          activity: baseActivity,
          dayIndex: day
        });
      }
    }

    return data;
  };

  const mockData = generateMockData();

  const defaultProps = {
    data: mockData
  };

  describe('header', () => {
    it('shows Activity Heatmap title', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Activity Heatmap')).toBeInTheDocument();
    });

    it('shows description', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Audit event distribution by time of day and day of week')).toBeInTheDocument();
    });

    it('shows Activity icon', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.lucide-activity')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<ActivityHeatmap data={[]} loading={true} />);

      expect(container.querySelector('.animate-pulse')).toBeInTheDocument();
    });

    it('hides content when loading', () => {
      render(<ActivityHeatmap data={[]} loading={true} />);

      expect(screen.queryByText('Activity Heatmap')).not.toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows no data message when data is empty', () => {
      render(<ActivityHeatmap data={[]} />);

      expect(screen.getByText('No activity data available')).toBeInTheDocument();
    });
  });

  describe('day labels', () => {
    it('shows all days of week', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Sun')).toBeInTheDocument();
      expect(screen.getByText('Mon')).toBeInTheDocument();
      expect(screen.getByText('Tue')).toBeInTheDocument();
      expect(screen.getByText('Wed')).toBeInTheDocument();
      expect(screen.getByText('Thu')).toBeInTheDocument();
      expect(screen.getByText('Fri')).toBeInTheDocument();
      expect(screen.getByText('Sat')).toBeInTheDocument();
    });
  });

  describe('hour labels', () => {
    it('shows hour markers', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      // Shows every 6 hours: 0h, 6h, 12h, 18h
      expect(screen.getByText('0h')).toBeInTheDocument();
      expect(screen.getByText('6h')).toBeInTheDocument();
      expect(screen.getByText('12h')).toBeInTheDocument();
      expect(screen.getByText('18h')).toBeInTheDocument();
    });
  });

  describe('heatmap grid', () => {
    it('renders 168 cells (7 days * 24 hours)', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      // 7 days * 24 hours = 168 cells
      const cells = container.querySelectorAll('.h-4.rounded-sm.cursor-pointer');
      expect(cells.length).toBe(168);
    });

    it('cells have title attribute with activity info', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      const cells = container.querySelectorAll('.h-4.rounded-sm.cursor-pointer');
      const firstCell = cells[0];

      // Title should contain day, hour, and events count
      expect(firstCell.getAttribute('title')).toMatch(/Sun 0:00 - \d+ events/);
    });

    it('cells have hover effect', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      const cells = container.querySelectorAll('.h-4.rounded-sm.cursor-pointer');
      expect(cells[0]).toHaveClass('hover:ring-2');
    });
  });

  describe('legend', () => {
    it('shows Less label', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Less')).toBeInTheDocument();
    });

    it('shows More label', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('More')).toBeInTheDocument();
    });

    it('shows peak activity info', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText(/Peak activity:/)).toBeInTheDocument();
      expect(screen.getByText(/events\/hour/)).toBeInTheDocument();
    });

    it('shows legend color boxes', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      // Legend has 6 color intensity boxes
      const legendBoxes = container.querySelectorAll('.w-3.h-3.rounded-sm');
      expect(legendBoxes.length).toBe(6);
    });
  });

  describe('activity summary', () => {
    it('shows Total Events', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Total Events')).toBeInTheDocument();
    });

    it('shows Avg per Hour', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Avg per Hour')).toBeInTheDocument();
    });

    it('shows Weekday vs Weekend', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      expect(screen.getByText('Weekday vs Weekend')).toBeInTheDocument();
    });

    it('displays formatted total events count', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      // Total events should be displayed as a number
      const totalSection = screen.getByText('Total Events').parentElement;
      expect(totalSection?.querySelector('.text-2xl')).toBeInTheDocument();
    });

    it('displays percentage for weekday vs weekend ratio', () => {
      render(<ActivityHeatmap {...defaultProps} />);

      // Should show a percentage value
      const ratioSection = screen.getByText('Weekday vs Weekend').parentElement;
      const percentValue = ratioSection?.querySelector('.text-2xl');
      expect(percentValue?.textContent).toMatch(/\d+%/);
    });
  });

  describe('intensity colors', () => {
    it('assigns different opacity based on activity level', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      // Should have cells with different opacity levels
      const cells = container.querySelectorAll('.h-4.rounded-sm.cursor-pointer');
      const classLists = Array.from(cells).map(cell => cell.className);

      // Should have mix of opacities
      expect(classLists.some(c => c.includes('opacity-20') || c.includes('opacity-40') || c.includes('opacity-60') || c.includes('opacity-80'))).toBe(true);
    });
  });

  describe('styling', () => {
    it('has theme background', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.bg-theme-background')).toBeInTheDocument();
    });

    it('has border styling', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.border-theme')).toBeInTheDocument();
    });

    it('has rounded corners', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.rounded-lg')).toBeInTheDocument();
    });

    it('has padding', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.p-6')).toBeInTheDocument();
    });
  });

  describe('grid structure', () => {
    it('has 24-column grid for hours', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.grid-cols-24')).toBeInTheDocument();
    });

    it('has 3-column summary grid on medium screens', () => {
      const { container } = render(<ActivityHeatmap {...defaultProps} />);

      expect(container.querySelector('.md\\:grid-cols-3')).toBeInTheDocument();
    });
  });

  describe('data calculations', () => {
    it('calculates correct total events', () => {
      const simpleData: HeatmapDataPoint[] = [
        { day: 'Mon', hour: 9, activity: 100, dayIndex: 1 },
        { day: 'Mon', hour: 10, activity: 200, dayIndex: 1 }
      ];

      render(<ActivityHeatmap data={simpleData} />);

      expect(screen.getByText('300')).toBeInTheDocument();
    });

    it('handles zero weekend events', () => {
      const weekdayOnlyData: HeatmapDataPoint[] = [
        { day: 'Mon', hour: 9, activity: 100, dayIndex: 1 }
      ];

      render(<ActivityHeatmap data={weekdayOnlyData} />);

      // Should display 0% when no weekend events
      expect(screen.getByText('0%')).toBeInTheDocument();
    });
  });
});

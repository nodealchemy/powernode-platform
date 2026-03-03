---
Last Updated: 2026-02-28
Platform Version: 0.3.1
---

# Dashboard Specialist Guide

## Role & Responsibilities

The Dashboard Specialist specializes in analytics dashboards, interactive charts, and reporting interfaces for Powernode's subscription platform.

### Core Responsibilities
- Implementing analytics dashboards
- Creating interactive charts and graphs
- Building reporting interfaces
- Handling real-time data updates
- Optimizing dashboard performance

### Key Focus Areas
- Data visualization best practices
- Real-time data integration with WebSockets
- Interactive chart components and filtering
- KPI calculation and display
- Performance optimization for large datasets

## Dashboard Architecture Standards

### 1. Chart Library Integration (MANDATORY)

#### Chart Component Architecture
```tsx
// src/shared/components/charts/BaseChart.tsx
import React, { useMemo, useCallback } from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler
} from 'chart.js';
import { Line, Bar, Doughnut, Pie } from 'react-chartjs-2';
import { useTheme } from '@/shared/hooks/ThemeContext';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

export interface BaseChartProps {
  title?: string;
  subtitle?: string;
  data: any;
  options?: any;
  type: 'line' | 'bar' | 'doughnut' | 'pie';
  height?: number;
  loading?: boolean;
  error?: string;
  className?: string;
}

export const BaseChart: React.FC<BaseChartProps> = ({
  title,
  subtitle,
  data,
  options = {},
  type,
  height = 400,
  loading = false,
  error,
  className
}) => {
  const { effectiveTheme } = useTheme();

  // Theme-aware chart options
  const chartOptions = useMemo(() => {
    const isDark = effectiveTheme === 'dark';
    
    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: {
            color: isDark ? '#e5e7eb' : '#374151',
            font: {
              family: 'Inter, system-ui, sans-serif',
              size: 12
            }
          }
        },
        tooltip: {
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
          titleColor: isDark ? '#f9fafb' : '#111827',
          bodyColor: isDark ? '#d1d5db' : '#374151',
          borderColor: isDark ? '#374151' : '#e5e7eb',
          borderWidth: 1
        }
      },
      scales: type !== 'doughnut' && type !== 'pie' ? {
        x: {
          grid: {
            color: isDark ? '#374151' : '#f3f4f6'
          },
          ticks: {
            color: isDark ? '#9ca3af' : '#6b7280'
          }
        },
        y: {
          grid: {
            color: isDark ? '#374151' : '#f3f4f6'
          },
          ticks: {
            color: isDark ? '#9ca3af' : '#6b7280'
          }
        }
      } : undefined
    };

    return {
      ...defaultOptions,
      ...options
    };
  }, [effectiveTheme, options, type]);

  const renderChart = useCallback(() => {
    const ChartComponent = {
      line: Line,
      bar: Bar,
      doughnut: Doughnut,
      pie: Pie
    }[type];

    return (
      <ChartComponent
        data={data}
        options={chartOptions}
        height={height}
      />
    );
  }, [type, data, chartOptions, height]);

  if (loading) {
    return (
      <div 
        className="flex items-center justify-center bg-theme-surface rounded-lg border border-theme"
        style={{ height: `${height}px` }}
      >
        <div className="animate-pulse space-y-4 w-full p-6">
          <div className="h-4 bg-theme-background rounded w-1/4" />
          <div className="space-y-2">
            <div className="h-2 bg-theme-background rounded" />
            <div className="h-2 bg-theme-background rounded w-5/6" />
            <div className="h-2 bg-theme-background rounded w-4/6" />
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div 
        className="flex items-center justify-center bg-theme-surface rounded-lg border border-theme-error"
        style={{ height: `${height}px` }}
      >
        <div className="text-center p-6">
          <p className="text-theme-error font-medium">Failed to load chart</p>
          <p className="text-theme-secondary text-sm mt-2">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className={`bg-theme-surface rounded-lg border border-theme p-6 ${className || ''}`}>
      {(title || subtitle) && (
        <div className="mb-4">
          {title && (
            <h3 className="text-lg font-semibold text-theme-primary">{title}</h3>
          )}
          {subtitle && (
            <p className="text-sm text-theme-secondary mt-1">{subtitle}</p>
          )}
        </div>
      )}
      
      <div style={{ height: `${height}px` }}>
        {renderChart()}
      </div>
    </div>
  );
};
```

#### Specialized Chart Components
```tsx
// src/features/analytics/components/RevenueChart.tsx
import React, { useMemo } from 'react';
import { BaseChart } from '@/shared/components/charts/BaseChart';
import { formatCurrency } from '@/shared/utils/currency';

interface RevenueData {
  date: string;
  mrr: number;
  arr: number;
  newRevenue: number;
  churnedRevenue: number;
}

interface RevenueChartProps {
  data: RevenueData[];
  timeRange: '30d' | '90d' | '12m';
  metric: 'mrr' | 'arr';
  loading?: boolean;
  error?: string;
}

export const RevenueChart: React.FC<RevenueChartProps> = ({
  data,
  timeRange,
  metric,
  loading,
  error
}) => {
  const chartData = useMemo(() => {
    const labels = data.map(d => {
      const date = new Date(d.date);
      return timeRange === '12m' 
        ? date.toLocaleDateString('en-US', { month: 'short', year: 'numeric' })
        : date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    });

    const revenueData = data.map(d => d[metric]);
    const newRevenueData = data.map(d => d.newRevenue);
    const churnedRevenueData = data.map(d => -d.churnedRevenue);

    return {
      labels,
      datasets: [
        {
          label: metric.toUpperCase(),
          data: revenueData,
          borderColor: '#3b82f6',
          backgroundColor: 'rgba(59, 130, 246, 0.1)',
          tension: 0.4,
          fill: true
        },
        {
          label: 'New Revenue',
          data: newRevenueData,
          borderColor: '#10b981',
          backgroundColor: 'rgba(16, 185, 129, 0.1)',
          tension: 0.4,
          fill: false
        },
        {
          label: 'Churned Revenue',
          data: churnedRevenueData,
          borderColor: '#ef4444',
          backgroundColor: 'rgba(239, 68, 68, 0.1)',
          tension: 0.4,
          fill: false
        }
      ]
    };
  }, [data, metric, timeRange]);

  const chartOptions = useMemo(() => ({
    plugins: {
      tooltip: {
        callbacks: {
          label: (context: any) => {
            const value = Math.abs(context.parsed.y);
            return `${context.dataset.label}: ${formatCurrency(value)}`;
          }
        }
      }
    },
    scales: {
      y: {
        ticks: {
          callback: (value: any) => formatCurrency(Math.abs(value))
        }
      }
    }
  }), []);

  const currentValue = data.length > 0 ? data[data.length - 1][metric] : 0;
  const previousValue = data.length > 1 ? data[data.length - 2][metric] : currentValue;
  const growthRate = previousValue !== 0 
    ? ((currentValue - previousValue) / previousValue) * 100 
    : 0;

  return (
    <div className="space-y-4">
      {/* KPI Summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="text-2xl font-bold text-theme-primary">
            {formatCurrency(currentValue)}
          </div>
          <div className="text-sm text-theme-secondary">
            Current {metric.toUpperCase()}
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className={`text-2xl font-bold ${growthRate >= 0 ? 'text-theme-success' : 'text-theme-error'}`}>
            {growthRate >= 0 ? '+' : ''}{growthRate.toFixed(1)}%
          </div>
          <div className="text-sm text-theme-secondary">
            Growth Rate
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="text-2xl font-bold text-theme-primary">
            {formatCurrency(currentValue * 12)}
          </div>
          <div className="text-sm text-theme-secondary">
            Annualized
          </div>
        </div>
      </div>

      {/* Chart */}
      <BaseChart
        type="line"
        title={`${metric.toUpperCase()} Trend`}
        subtitle={`Revenue tracking over the last ${timeRange}`}
        data={chartData}
        options={chartOptions}
        height={400}
        loading={loading}
        error={error}
      />
    </div>
  );
};

// src/features/analytics/components/ChurnChart.tsx
export const ChurnChart: React.FC<{
  data: Array<{ date: string; churnRate: number; cohortSize: number }>;
  loading?: boolean;
}> = ({ data, loading }) => {
  const chartData = useMemo(() => {
    return {
      labels: data.map(d => new Date(d.date).toLocaleDateString('en-US', { month: 'short' })),
      datasets: [
        {
          label: 'Churn Rate (%)',
          data: data.map(d => (d.churnRate * 100).toFixed(2)),
          backgroundColor: 'rgba(239, 68, 68, 0.8)',
          borderColor: '#ef4444',
          borderWidth: 2
        }
      ]
    };
  }, [data]);

  const avgChurnRate = data.length > 0 
    ? data.reduce((sum, d) => sum + d.churnRate, 0) / data.length
    : 0;

  return (
    <div className="space-y-4">
      <div className="bg-theme-surface rounded-lg p-4 border border-theme">
        <div className="text-2xl font-bold text-theme-error">
          {(avgChurnRate * 100).toFixed(2)}%
        </div>
        <div className="text-sm text-theme-secondary">
          Average Monthly Churn Rate
        </div>
      </div>
      
      <BaseChart
        type="bar"
        title="Monthly Churn Rate"
        subtitle="Customer churn rate by month"
        data={chartData}
        loading={loading}
        height={300}
      />
    </div>
  );
};
```

### 2. Real-Time Dashboard Integration (MANDATORY)

#### WebSocket Integration for Live Data
```tsx
// src/features/analytics/hooks/useRealTimeMetrics.tsx
import { useState, useEffect, useRef } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

interface MetricUpdate {
  type: 'mrr' | 'arr' | 'active_subscriptions' | 'churn_rate';
  value: number;
  timestamp: string;
  change: number;
}

interface RealTimeMetrics {
  mrr: number;
  arr: number;
  activeSubscriptions: number;
  churnRate: number;
  lastUpdated: string;
  isConnected: boolean;
}

export const useRealTimeMetrics = (accountId: string) => {
  const [metrics, setMetrics] = useState<RealTimeMetrics>({
    mrr: 0,
    arr: 0,
    activeSubscriptions: 0,
    churnRate: 0,
    lastUpdated: new Date().toISOString(),
    isConnected: false
  });

  const metricsRef = useRef(metrics);
  metricsRef.current = metrics;

  const { isConnected, sendMessage } = useWebSocket({
    url: `${process.env.REACT_APP_WS_URL}/cable`,
    protocols: ['actioncable-v1-json'],
    onMessage: (data) => {
      try {
        const message = JSON.parse(data);
        
        if (message.type === 'ping') {
          return; // Ignore ping messages
        }
        
        if (message.type === 'metric_update') {
          const update: MetricUpdate = message.data;
          
          setMetrics(prev => ({
            ...prev,
            [update.type === 'active_subscriptions' ? 'activeSubscriptions' : update.type]: update.value,
            lastUpdated: update.timestamp
          }));
        }
      } catch (error) {
        console.error('Error parsing WebSocket message:', error);
      }
    },
    onConnect: () => {
      // Subscribe to analytics channel
      sendMessage(JSON.stringify({
        command: 'subscribe',
        identifier: JSON.stringify({
          channel: 'AnalyticsChannel',
          account_id: accountId
        })
      }));
    },
    reconnectAttempts: 5,
    reconnectInterval: 3000
  });

  useEffect(() => {
    setMetrics(prev => ({ ...prev, isConnected }));
  }, [isConnected]);

  return {
    metrics,
    isConnected,
    refreshMetrics: () => {
      sendMessage(JSON.stringify({
        command: 'message',
        identifier: JSON.stringify({
          channel: 'AnalyticsChannel',
          account_id: accountId
        }),
        data: JSON.stringify({ action: 'refresh_metrics' })
      }));
    }
  };
};

// src/features/analytics/components/LiveMetricCard.tsx
interface LiveMetricCardProps {
  title: string;
  value: number;
  previousValue?: number;
  format?: 'currency' | 'number' | 'percentage';
  icon?: React.ReactNode;
  isConnected?: boolean;
  lastUpdated?: string;
}

export const LiveMetricCard: React.FC<LiveMetricCardProps> = ({
  title,
  value,
  previousValue,
  format = 'number',
  icon,
  isConnected = false,
  lastUpdated
}) => {
  const [isAnimating, setIsAnimating] = useState(false);
  const prevValueRef = useRef(value);

  useEffect(() => {
    if (prevValueRef.current !== value) {
      setIsAnimating(true);
      const timer = setTimeout(() => setIsAnimating(false), 500);
      prevValueRef.current = value;
      return () => clearTimeout(timer);
    }
  }, [value]);

  const formatValue = (val: number) => {
    switch (format) {
      case 'currency':
        return new Intl.NumberFormat('en-US', {
          style: 'currency',
          currency: 'USD'
        }).format(val);
      case 'percentage':
        return `${val.toFixed(2)}%`;
      default:
        return new Intl.NumberFormat().format(val);
    }
  };

  const getChangeIndicator = () => {
    if (previousValue === undefined || previousValue === value) return null;
    
    const change = value - previousValue;
    const percentChange = previousValue !== 0 ? (change / previousValue) * 100 : 0;
    const isPositive = change > 0;
    
    return (
      <div className={`flex items-center text-sm ${
        isPositive ? 'text-theme-success' : 'text-theme-error'
      }`}>
        {isPositive ? '↗' : '↘'}
        <span className="ml-1">{Math.abs(percentChange).toFixed(1)}%</span>
      </div>
    );
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6 relative overflow-hidden">
      {/* Connection indicator */}
      <div className="absolute top-4 right-4">
        <div className={`w-2 h-2 rounded-full ${
          isConnected ? 'bg-theme-success animate-pulse' : 'bg-theme-error'
        }`} />
      </div>

      {/* Icon */}
      {icon && (
        <div className="text-theme-secondary mb-2">
          {icon}
        </div>
      )}

      {/* Title */}
      <h3 className="text-sm font-medium text-theme-secondary mb-2">
        {title}
      </h3>

      {/* Value */}
      <div className={`text-2xl font-bold text-theme-primary transition-all duration-500 ${
        isAnimating ? 'scale-110 text-theme-success' : ''
      }`}>
        {formatValue(value)}
      </div>

      {/* Change indicator */}
      <div className="mt-2 flex items-center justify-between">
        {getChangeIndicator()}
        
        {lastUpdated && (
          <div className="text-xs text-theme-tertiary">
            Updated {new Date(lastUpdated).toLocaleTimeString()}
          </div>
        )}
      </div>

      {/* Loading animation overlay */}
      {isAnimating && (
        <div className="absolute inset-0 bg-theme-success/10 animate-pulse" />
      )}
    </div>
  );
};
```

### 3. Dashboard Layout Components (MANDATORY)

#### Dashboard Grid System
```tsx
// src/features/analytics/components/DashboardLayout.tsx
import React, { useState } from 'react';
import { DndContext, closestCenter, KeyboardSensor, PointerSensor, useSensor, useSensors } from '@dnd-kit/core';
import { arrayMove, SortableContext, sortableKeyboardCoordinates, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { restrictToWindowEdges } from '@dnd-kit/modifiers';

interface DashboardWidget {
  id: string;
  title: string;
  component: React.ComponentType<any>;
  props?: Record<string, any>;
  span?: { cols: number; rows: number };
  minSize?: { cols: number; rows: number };
}

interface DashboardLayoutProps {
  widgets: DashboardWidget[];
  onWidgetOrderChange?: (widgets: DashboardWidget[]) => void;
  editable?: boolean;
  className?: string;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({
  widgets: initialWidgets,
  onWidgetOrderChange,
  editable = false,
  className
}) => {
  const [widgets, setWidgets] = useState(initialWidgets);
  
  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    })
  );

  const handleDragEnd = (event: any) => {
    const { active, over } = event;
    
    if (active.id !== over.id) {
      const oldIndex = widgets.findIndex(widget => widget.id === active.id);
      const newIndex = widgets.findIndex(widget => widget.id === over.id);
      
      const newWidgets = arrayMove(widgets, oldIndex, newIndex);
      setWidgets(newWidgets);
      onWidgetOrderChange?.(newWidgets);
    }
  };

  return (
    <div className={`dashboard-grid ${className || ''}`}>
      {editable ? (
        <DndContext 
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={handleDragEnd}
          modifiers={[restrictToWindowEdges]}
        >
          <SortableContext items={widgets.map(w => w.id)} strategy={verticalListSortingStrategy}>
            <div className="grid grid-cols-12 gap-6">
              {widgets.map((widget) => (
                <SortableWidget
                  key={widget.id}
                  widget={widget}
                  editable={editable}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      ) : (
        <div className="grid grid-cols-12 gap-6">
          {widgets.map((widget) => (
            <DashboardWidget key={widget.id} widget={widget} />
          ))}
        </div>
      )}
    </div>
  );
};

// Individual dashboard widget component
const DashboardWidget: React.FC<{ widget: DashboardWidget }> = ({ widget }) => {
  const { component: Component, props = {}, span = { cols: 6, rows: 1 } } = widget;
  
  const colSpan = Math.min(Math.max(span.cols, 1), 12);
  const rowSpan = Math.max(span.rows, 1);
  
  return (
    <div 
      className={`col-span-${colSpan}`}
      style={{ gridRow: `span ${rowSpan}` }}
    >
      <Component {...props} />
    </div>
  );
};

// Sortable widget wrapper for drag & drop
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';

const SortableWidget: React.FC<{ 
  widget: DashboardWidget; 
  editable: boolean;
}> = ({ widget, editable }) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
  } = useSortable({ id: widget.id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...(editable ? { ...attributes, ...listeners } : {})}
      className={`${editable ? 'cursor-move' : ''}`}
    >
      <DashboardWidget widget={widget} />
    </div>
  );
};
```

#### Performance Optimized Dashboard
```tsx
// src/features/analytics/components/PerformanceDashboard.tsx
import React, { memo, useMemo, useCallback } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { useIntersectionObserver } from '@/shared/hooks/useIntersectionObserver';

interface PerformanceDashboardProps {
  widgets: DashboardWidget[];
  containerHeight: number;
}

export const PerformanceDashboard: React.FC<PerformanceDashboardProps> = memo(({
  widgets,
  containerHeight
}) => {
  const parentRef = React.useRef<HTMLDivElement>(null);
  
  // Virtual scrolling for large numbers of widgets
  const virtualizer = useVirtualizer({
    count: widgets.length,
    getScrollElement: () => parentRef.current,
    estimateSize: useCallback(() => 400, []), // Estimated widget height
    overscan: 2 // Render 2 extra items outside viewport
  });

  const items = virtualizer.getVirtualItems();

  return (
    <div 
      ref={parentRef}
      className="overflow-auto"
      style={{ height: containerHeight }}
    >
      <div
        style={{
          height: virtualizer.getTotalSize(),
          width: '100%',
          position: 'relative',
        }}
      >
        {items.map((virtualItem) => {
          const widget = widgets[virtualItem.index];
          
          return (
            <div
              key={widget.id}
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                height: virtualItem.size,
                transform: `translateY(${virtualItem.start}px)`,
              }}
            >
              <LazyWidget widget={widget} />
            </div>
          );
        })}
      </div>
    </div>
  );
});

// Lazy-loaded widget component
const LazyWidget: React.FC<{ widget: DashboardWidget }> = ({ widget }) => {
  const [ref, isIntersecting] = useIntersectionObserver({
    threshold: 0.1
  });

  const { component: Component, props = {} } = widget;

  return (
    <div ref={ref} className="p-4">
      {isIntersecting ? (
        <Component {...props} />
      ) : (
        <div className="bg-theme-surface rounded-lg border border-theme animate-pulse">
          <div className="p-6">
            <div className="h-4 bg-theme-background rounded w-1/4 mb-4" />
            <div className="h-32 bg-theme-background rounded" />
          </div>
        </div>
      )}
    </div>
  );
};
```

## Development Commands

### Dashboard Development
```bash
# Install chart.js and related dependencies
npm install chart.js react-chartjs-2 @dnd-kit/core @dnd-kit/sortable

# Install virtualization for performance
npm install @tanstack/react-virtual

# Install date handling for time series
npm install date-fns

# Run dashboard in development
npm start

# Test dashboard components
npm test -- --testPathPattern=analytics

# Build optimized dashboard
npm run build
```

### Performance Testing
```bash
# Install performance testing tools
npm install --save-dev @testing-library/react-hooks
npm install --save-dev lighthouse

# Run performance audits
npm run audit:performance

# Analyze bundle size
npm run analyze
```

## Integration Points

### Dashboard Specialist Coordinates With:
- **Analytics Engineer**: KPI calculations, data aggregation logic
- **React Architect**: Component architecture, state management patterns
- **UI Component Developer**: Chart component library, responsive design
- **Backend Test Engineer**: API data contracts, real-time data validation
- **Performance Optimizer**: Dashboard performance, data loading optimization

## Quick Reference

### Chart Component Template
```tsx
import React, { useMemo } from 'react';
import { BaseChart } from '@/shared/components/charts/BaseChart';

export const CustomChart: React.FC<{
  data: ChartData[];
  loading?: boolean;
}> = ({ data, loading }) => {
  const chartData = useMemo(() => ({
    labels: data.map(d => d.label),
    datasets: [{
      label: 'Dataset',
      data: data.map(d => d.value),
      backgroundColor: 'rgba(59, 130, 246, 0.1)',
      borderColor: '#3b82f6'
    }]
  }), [data]);

  return (
    <BaseChart
      type="line"
      title="Chart Title"
      data={chartData}
      loading={loading}
      height={300}
    />
  );
};
```

### Real-Time Metric Template
```tsx
const { metrics, isConnected } = useRealTimeMetrics(accountId);

return (
  <LiveMetricCard
    title="Monthly Recurring Revenue"
    value={metrics.mrr}
    format="currency"
    isConnected={isConnected}
    lastUpdated={metrics.lastUpdated}
  />
);
```

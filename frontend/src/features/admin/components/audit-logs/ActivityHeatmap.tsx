import React from 'react';
import { Activity } from 'lucide-react';

interface ActivityHeatmapProps {
  timeRange: { label: string; value: string; days: number };
}

export const ActivityHeatmap: React.FC<ActivityHeatmapProps> = ({ timeRange }) => {
  // Generate mock heatmap data
  const generateHeatmapData = () => {
    const data = [];
    const daysOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    
    for (let day = 0; day < 7; day++) {
      for (let hour = 0; hour < 24; hour++) {
        // Simulate activity patterns (higher during business hours, weekdays)
        let baseActivity = 5;
        
        // Business hours (9 AM - 5 PM) have higher activity
        if (hour >= 9 && hour <= 17) {
          baseActivity = 25;
        }
        
        // Weekdays (Mon-Fri) have higher activity
        if (day >= 1 && day <= 5) {
          baseActivity *= 1.5;
        }
        
        // Add some randomness
        const activity = Math.floor(baseActivity + Math.random() * baseActivity * 0.5);
        
        data.push({
          // eslint-disable-next-line security/detect-object-injection
          day: daysOfWeek[day] || 'Unknown',
          hour,
          activity,
          dayIndex: day,
          hourIndex: hour
        });
      }
    }
    
    return data;
  };

  const heatmapData = generateHeatmapData();
  const maxActivity = Math.max(...heatmapData.map(d => d.activity));
  
  const getIntensityColor = (activity: number) => {
    const intensity = activity / maxActivity;
    if (intensity > 0.8) return 'bg-theme-interactive-primary';
    if (intensity > 0.6) return 'bg-theme-interactive-primary opacity-80';
    if (intensity > 0.4) return 'bg-theme-interactive-primary opacity-60';
    if (intensity > 0.2) return 'bg-theme-interactive-primary opacity-40';
    if (intensity > 0.1) return 'bg-theme-interactive-primary opacity-20';
    return 'bg-theme-surface';
  };

  const hours = Array.from({ length: 24 }, (_, i) => i);
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  return (
    <div className="bg-theme-background rounded-lg border border-theme p-6">
      <div className="flex items-center gap-2 mb-6">
        <div className="p-1 bg-theme-interactive-primary bg-opacity-10 rounded">
          <Activity className="w-4 h-4 text-theme-interactive-primary" />
        </div>
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Activity Heatmap</h3>
          <p className="text-theme-secondary">Audit event distribution by time of day and day of week</p>
        </div>
      </div>

      <div className="space-y-4">
        {/* Hour labels */}
        <div className="flex items-center">
          <div className="w-12"></div> {/* Spacer for day labels */}
          <div className="flex-1 grid grid-cols-24 gap-1">
            {hours.map(hour => (
              <div key={hour} className="text-xs text-theme-tertiary text-center">
                {hour % 6 === 0 ? `${hour}h` : ''}
              </div>
            ))}
          </div>
        </div>

        {/* Heatmap grid */}
        {days.map((day, dayIndex) => (
          <div key={day} className="flex items-center">
            <div className="w-12 text-xs font-medium text-theme-secondary text-right pr-2">
              {day}
            </div>
            <div className="flex-1 grid grid-cols-24 gap-1">
              {hours.map(hour => {
                const dataPoint = heatmapData.find(
                  d => d.dayIndex === dayIndex && d.hour === hour
                );
                return (
                  <div
                    key={`${day}-${hour}`}
                    className={`h-4 rounded-sm cursor-pointer transition-all duration-200 hover:ring-2 hover:ring-theme-interactive-primary hover:ring-opacity-50 ${
                      getIntensityColor(dataPoint?.activity || 0)
                    }`}
                    title={`${day} ${hour}:00 - ${dataPoint?.activity || 0} events`}
                  />
                );
              })}
            </div>
          </div>
        ))}

        {/* Legend */}
        <div className="flex items-center justify-between pt-4 border-t border-theme">
          <div className="flex items-center gap-4">
            <span className="text-sm text-theme-secondary">Less</span>
            <div className="flex items-center gap-1">
              <div className="w-3 h-3 bg-theme-surface rounded-sm" />
              <div className="w-3 h-3 bg-theme-interactive-primary opacity-20 rounded-sm" />
              <div className="w-3 h-3 bg-theme-interactive-primary opacity-40 rounded-sm" />
              <div className="w-3 h-3 bg-theme-interactive-primary opacity-60 rounded-sm" />
              <div className="w-3 h-3 bg-theme-interactive-primary opacity-80 rounded-sm" />
              <div className="w-3 h-3 bg-theme-interactive-primary rounded-sm" />
            </div>
            <span className="text-sm text-theme-secondary">More</span>
          </div>
          
          <div className="text-sm text-theme-secondary">
            Peak activity: {maxActivity} events/hour
          </div>
        </div>

        {/* Activity summary */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 pt-4 border-t border-theme">
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {heatmapData.reduce((acc, d) => acc + d.activity, 0).toLocaleString()}
            </div>
            <div className="text-sm text-theme-secondary">Total Events</div>
          </div>
          
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {Math.round(heatmapData.reduce((acc, d) => acc + d.activity, 0) / (7 * 24))}
            </div>
            <div className="text-sm text-theme-secondary">Avg per Hour</div>
          </div>
          
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">
              {Math.round(heatmapData.filter(d => d.dayIndex >= 1 && d.dayIndex <= 5).reduce((acc, d) => acc + d.activity, 0) / 
                         heatmapData.filter(d => d.dayIndex === 0 || d.dayIndex === 6).reduce((acc, d) => acc + d.activity, 0) * 100)}%
            </div>
            <div className="text-sm text-theme-secondary">Weekday vs Weekend</div>
          </div>
        </div>
      </div>
    </div>
  );
};
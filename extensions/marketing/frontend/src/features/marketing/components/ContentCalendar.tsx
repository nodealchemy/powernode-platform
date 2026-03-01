import React, { useState, useMemo } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useContentCalendar } from '../hooks/useContentCalendar';
import { ContentCalendarEntry as CalendarEntryCard } from './ContentCalendarEntry';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { ContentCalendarEntry as CalendarEntry, CalendarEntryFormData } from '../types';

type ViewMode = 'month' | 'week';

export const ContentCalendar: React.FC = () => {
  const [viewMode, setViewMode] = useState<ViewMode>('month');
  const [currentDate, setCurrentDate] = useState(new Date());
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);

  const startDate = useMemo(() => {
    const d = new Date(currentDate);
    if (viewMode === 'month') {
      d.setDate(1);
    } else {
      d.setDate(d.getDate() - d.getDay());
    }
    return d.toISOString().split('T')[0];
  }, [currentDate, viewMode]);

  const endDate = useMemo(() => {
    const d = new Date(currentDate);
    if (viewMode === 'month') {
      d.setMonth(d.getMonth() + 1, 0);
    } else {
      d.setDate(d.getDate() + (6 - d.getDay()));
    }
    return d.toISOString().split('T')[0];
  }, [currentDate, viewMode]);

  const { entries, loading, error, createEntry } = useContentCalendar({
    startDate,
    endDate,
  });

  const navigate = (direction: number) => {
    const d = new Date(currentDate);
    if (viewMode === 'month') {
      d.setMonth(d.getMonth() + direction);
    } else {
      d.setDate(d.getDate() + (direction * 7));
    }
    setCurrentDate(d);
  };

  const daysInView = useMemo(() => {
    const days: Date[] = [];
    const start = new Date(startDate);
    const end = new Date(endDate);

    if (viewMode === 'month') {
      // Pad to start of week
      const firstDay = new Date(start);
      firstDay.setDate(firstDay.getDate() - firstDay.getDay());
      const lastDay = new Date(end);
      lastDay.setDate(lastDay.getDate() + (6 - lastDay.getDay()));

      const current = new Date(firstDay);
      while (current <= lastDay) {
        days.push(new Date(current));
        current.setDate(current.getDate() + 1);
      }
    } else {
      const current = new Date(start);
      for (let i = 0; i < 7; i++) {
        days.push(new Date(current));
        current.setDate(current.getDate() + 1);
      }
    }
    return days;
  }, [startDate, endDate, viewMode]);

  const entriesByDate = useMemo(() => {
    const map: Record<string, CalendarEntry[]> = {};
    entries.forEach(entry => {
      const dateKey = entry.scheduled_date;
      if (!map[dateKey]) map[dateKey] = [];
      map[dateKey].push(entry);
    });
    return map;
  }, [entries]);

  const handleCreateEntry = async (data: CalendarEntryFormData) => {
    await createEntry(data);
    setShowCreateForm(false);
  };

  const monthLabel = currentDate.toLocaleString('default', { month: 'long', year: 'numeric' });
  const weekLabel = viewMode === 'week'
    ? `${daysInView[0]?.toLocaleDateString()} - ${daysInView[6]?.toLocaleDateString()}`
    : '';
  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  if (loading && entries.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <div className="card-theme p-6 text-center">
        <p className="text-theme-error">{error}</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Calendar Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1">
            <button onClick={() => navigate(-1)} className="p-1.5 rounded hover:bg-theme-surface-hover text-theme-secondary">
              <ChevronLeft className="w-5 h-5" />
            </button>
            <h3 className="text-lg font-semibold text-theme-primary min-w-[200px] text-center">
              {viewMode === 'month' ? monthLabel : weekLabel}
            </h3>
            <button onClick={() => navigate(1)} className="p-1.5 rounded hover:bg-theme-surface-hover text-theme-secondary">
              <ChevronRight className="w-5 h-5" />
            </button>
          </div>
          <button onClick={() => setCurrentDate(new Date())} className="btn-theme btn-theme-secondary btn-theme-sm">
            Today
          </button>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex rounded-lg border border-theme-border overflow-hidden">
            <button
              onClick={() => setViewMode('month')}
              className={`px-3 py-1.5 text-sm ${
                viewMode === 'month' ? 'bg-theme-primary text-theme-on-primary' : 'bg-theme-surface text-theme-secondary'
              }`}
            >
              Month
            </button>
            <button
              onClick={() => setViewMode('week')}
              className={`px-3 py-1.5 text-sm ${
                viewMode === 'week' ? 'bg-theme-primary text-theme-on-primary' : 'bg-theme-surface text-theme-secondary'
              }`}
            >
              Week
            </button>
          </div>
        </div>
      </div>

      {/* Calendar Grid */}
      <div className="card-theme overflow-hidden">
        {/* Day Headers */}
        <div className="grid grid-cols-7 border-b border-theme-border">
          {dayNames.map(day => (
            <div key={day} className="px-2 py-2 text-center text-xs font-medium text-theme-secondary uppercase">
              {day}
            </div>
          ))}
        </div>

        {/* Day Cells */}
        <div className="grid grid-cols-7">
          {daysInView.map((day, i) => {
            const dateKey = day.toISOString().split('T')[0];
            const dayEntries = entriesByDate[dateKey] || [];
            const isToday = dateKey === new Date().toISOString().split('T')[0];
            const isCurrentMonth = day.getMonth() === currentDate.getMonth();

            return (
              <div
                key={i}
                className={`min-h-[100px] border-b border-r border-theme-border p-1.5 ${
                  !isCurrentMonth ? 'bg-theme-surface bg-opacity-50' : ''
                }`}
                onClick={() => { setSelectedDate(dateKey); setShowCreateForm(true); }}
              >
                <div className="flex items-center justify-between mb-1">
                  <span className={`text-xs font-medium px-1.5 py-0.5 rounded ${
                    isToday
                      ? 'bg-theme-primary text-theme-on-primary'
                      : isCurrentMonth
                        ? 'text-theme-primary'
                        : 'text-theme-tertiary'
                  }`}>
                    {day.getDate()}
                  </span>
                  {dayEntries.length > 0 && (
                    <span className="text-[10px] text-theme-tertiary">{dayEntries.length}</span>
                  )}
                </div>
                <div className="space-y-0.5">
                  {dayEntries.slice(0, 3).map(entry => (
                    <CalendarEntryCard key={entry.id} entry={entry} compact />
                  ))}
                  {dayEntries.length > 3 && (
                    <p className="text-[10px] text-theme-tertiary">+{dayEntries.length - 3} more</p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Quick Create Modal */}
      {showCreateForm && (
        <QuickCreateModal
          date={selectedDate || new Date().toISOString().split('T')[0]}
          onSave={handleCreateEntry}
          onClose={() => setShowCreateForm(false)}
        />
      )}
    </div>
  );
};

// Quick create modal for calendar entries
interface QuickCreateModalProps {
  date: string;
  onSave: (data: CalendarEntryFormData) => Promise<void>;
  onClose: () => void;
}

const QuickCreateModal: React.FC<QuickCreateModalProps> = ({ date, onSave, onClose }) => {
  const [title, setTitle] = useState('');
  const [saving, setSaving] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    await onSave({
      title,
      description: '',
      entry_type: 'post',
      channel: null,
      campaign_id: null,
      scheduled_date: date,
      scheduled_time: null,
      color: null,
    });
    setSaving(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <div className="card-theme-elevated p-6 w-full max-w-md">
        <h3 className="text-lg font-medium text-theme-primary mb-4">
          New Entry - {new Date(date + 'T00:00:00').toLocaleDateString()}
        </h3>
        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="text"
            required
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="input-theme w-full"
            placeholder="Entry title"
            autoFocus
          />
          <div className="flex justify-end gap-3">
            <button type="button" onClick={onClose} className="btn-theme btn-theme-secondary">Cancel</button>
            <button type="submit" disabled={saving} className="btn-theme btn-theme-primary">
              {saving ? 'Creating...' : 'Create'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

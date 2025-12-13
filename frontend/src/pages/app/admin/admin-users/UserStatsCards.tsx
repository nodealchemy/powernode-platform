import React from 'react';
import { UserStatsCardsProps } from './types';

export const UserStatsCards: React.FC<UserStatsCardsProps> = ({ userStats }) => (
  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
    <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
      <div className="text-2xl font-semibold text-theme-primary">{userStats.total_users}</div>
      <div className="text-theme-secondary text-sm">Total Users</div>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
      <div className="text-2xl font-semibold text-theme-success">{userStats.active_users}</div>
      <div className="text-theme-secondary text-sm">Active Users</div>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
      <div className="text-2xl font-semibold text-theme-error">{userStats.suspended_users}</div>
      <div className="text-theme-secondary text-sm">Suspended Users</div>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
      <div className="text-2xl font-semibold text-theme-warning">{userStats.unverified_users}</div>
      <div className="text-theme-secondary text-sm">Unverified Users</div>
    </div>
    <div className="bg-theme-surface rounded-lg p-4 shadow-sm">
      <div className="text-2xl font-semibold text-theme-info">{userStats.recent_logins}</div>
      <div className="text-theme-secondary text-sm">Recent Logins</div>
    </div>
  </div>
);

import React from 'react';
import { GitBranch, Clock, ExternalLink, Shield, Target, AlertCircle } from 'lucide-react';
import { timeAgo, formatDuration } from '../constants/missionConstants';
import { cn } from '@/shared/utils/cn';
import type { Mission } from '../types/mission';

interface MissionExpandedRowProps {
  mission: Mission;
}

export const MissionExpandedRow: React.FC<MissionExpandedRowProps> = ({ mission }) => {
  const lastApproval = mission.approvals?.length
    ? mission.approvals[mission.approvals.length - 1]
    : null;

  return (
    <tr>
      <td colSpan={8} className="p-0">
        <div className="border-l-2 border-theme-accent mx-4 my-3 ml-6 pl-5 pr-2">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            {/* Column 1: Mission Info */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Mission Info</h4>
              <div className="space-y-2">
                {mission.description && (
                  <p className="text-sm text-theme-secondary max-w-sm">{mission.description}</p>
                )}
                {mission.objective && (
                  <DetailRow icon={Target} label="Objective" value={mission.objective} />
                )}
                {mission.current_phase && (
                  <div className="space-y-1.5">
                    <DetailRow icon={Clock} label="Phase" value={mission.current_phase.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())} />
                    <div className="ml-5">
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs text-theme-tertiary">Progress</span>
                        <span className="text-xs font-semibold text-theme-primary">{mission.phase_progress ?? 0}%</span>
                      </div>
                      <div className="h-1.5 bg-theme-bg-secondary rounded-full overflow-hidden max-w-[180px]">
                        <div
                          className={cn(
                            'h-full rounded-full transition-all duration-500',
                            (mission.phase_progress ?? 0) >= 80 ? 'bg-theme-status-success' :
                            (mission.phase_progress ?? 0) >= 40 ? 'bg-theme-status-warning' :
                            'bg-theme-interactive-primary'
                          )}
                          style={{ width: `${mission.phase_progress ?? 0}%` }}
                        />
                      </div>
                    </div>
                  </div>
                )}
                {mission.status === 'failed' && mission.error_message && (
                  <div className="flex items-start gap-2 text-xs">
                    <AlertCircle className="h-3.5 w-3.5 text-theme-error flex-shrink-0 mt-0.5" />
                    <span className="text-theme-error">{mission.error_message}</span>
                  </div>
                )}
              </div>
            </div>

            {/* Column 2: Repository & Deployment */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Repository & Deployment</h4>
              <div className="space-y-2">
                {mission.repository?.name ? (
                  <DetailRow icon={GitBranch} label="Repository" value={mission.repository.name} />
                ) : (
                  <DetailRow icon={GitBranch} label="Repository" value="—" />
                )}
                {mission.branch_name && (
                  <DetailRow icon={GitBranch} label="Branch" value={mission.branch_name} />
                )}
                {mission.pr_url && (
                  <div className="flex items-center gap-2 text-xs">
                    <ExternalLink className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0" />
                    <span className="text-theme-secondary">PR:</span>
                    <a
                      href={mission.pr_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-theme-accent hover:underline font-medium truncate"
                    >
                      #{mission.pr_number}
                    </a>
                  </div>
                )}
                {mission.deployed_url && (
                  <div className="flex items-center gap-2 text-xs">
                    <ExternalLink className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0" />
                    <span className="text-theme-secondary">Deployed:</span>
                    <a
                      href={mission.deployed_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-theme-accent hover:underline font-medium truncate"
                    >
                      {mission.deployed_url}
                    </a>
                  </div>
                )}
              </div>
            </div>

            {/* Column 3: Timing & Approvals */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Timing & Approvals</h4>
              <div className="space-y-2">
                <DetailRow icon={Clock} label="Created" value={timeAgo(mission.created_at)} />
                {mission.started_at && (
                  <DetailRow icon={Clock} label="Started" value={timeAgo(mission.started_at)} />
                )}
                <DetailRow icon={Clock} label="Duration" value={formatDuration(mission.duration_ms)} />
                {lastApproval && (
                  <div className="flex items-center gap-2 text-xs">
                    <Shield className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0" />
                    <span className="text-theme-secondary">Approval:</span>
                    <span className={cn(
                      'font-medium',
                      lastApproval.decision === 'approved' ? 'text-theme-success' : 'text-theme-error'
                    )}>
                      {lastApproval.decision === 'approved' ? 'Approved' : 'Rejected'}
                    </span>
                    <span className="text-theme-tertiary">
                      ({lastApproval.gate.replace(/_/g, ' ')})
                    </span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </td>
    </tr>
  );
};

function DetailRow({ icon: Icon, label, value }: { icon: React.ElementType; label: string; value: string }) {
  return (
    <div className="flex items-center gap-2 text-xs">
      <Icon className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0" />
      <span className="text-theme-secondary">{label}:</span>
      <span className="text-theme-primary font-medium truncate">{value}</span>
    </div>
  );
}

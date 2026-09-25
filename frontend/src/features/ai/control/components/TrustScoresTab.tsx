import React from 'react';
import { Shield } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useTrustScores } from '@/features/ai/autonomy/api/autonomyApi';
import { TrustScoreCard } from '@/features/ai/autonomy/components/TrustScoreCard';
import { CapabilityMatrixViewer } from '@/features/ai/autonomy/components/CapabilityMatrixViewer';
import type { TrustScore } from '@/features/ai/autonomy/types/autonomy';

const TrustScoresList: React.FC<{ trustScores: TrustScore[] }> = ({ trustScores }) => (
  <div className="space-y-6">
    {trustScores.length > 0 ? (
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {trustScores.map((score) => (
          <TrustScoreCard key={score.id} score={score} />
        ))}
      </div>
    ) : (
      <Card>
        <CardContent className="p-8 text-center text-theme-tertiary">
          <Shield className="w-12 h-12 mx-auto mb-3 opacity-30" />
          <p>No trust scores available. Agents need evaluations to build trust scores.</p>
        </CardContent>
      </Card>
    )}
    <CapabilityMatrixViewer />
  </div>
);

/** Control → Trust & Lineage → Trust: every agent's trust score and the capability matrix. */
export const TrustScoresTab: React.FC = () => {
  const { data: trustScores, isLoading } = useTrustScores();
  if (isLoading) return <LoadingSpinner size="lg" className="py-12" message="Loading trust scores..." />;
  return <TrustScoresList trustScores={trustScores ?? []} />;
};

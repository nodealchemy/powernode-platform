import React, { useState } from 'react';
import { CheckCircle2, XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { setupApi } from '../services/setupApi';
import type { SetupStepComponentProps } from './types';

type SeedStatus = 'idle' | 'seeding' | 'done' | 'empty' | 'error';

/**
 * Seed step — the optional final step. Offers to seed example data via
 * POST /setup/seed (idempotent, core-pure: a no-op in builds with no seeder).
 * "Continue" in the wizard footer stamps the step and finishes setup.
 */
export const SeedStep: React.FC<SetupStepComponentProps> = () => {
  const [status, setStatus] = useState<SeedStatus>('idle');

  const seed = async () => {
    setStatus('seeding');
    try {
      const result = await setupApi.seed();
      setStatus(result.seeded ? 'done' : 'empty');
    } catch (err) {
      logger.error('SeedStep: seed failed', err);
      setStatus('error');
    }
  };

  return (
    <div className="space-y-3" data-testid="setup-seed-step">
      <p className="text-sm text-theme-secondary">
        Optionally seed a starter set of example data so the platform has something to work
        with. Idempotent — you can skip this and seed later. Use <strong>Continue</strong> to
        finish setup.
      </p>
      <Button
        type="button"
        variant="secondary"
        size="sm"
        onClick={() => {
          void seed();
        }}
        disabled={status === 'seeding' || status === 'done'}
        loading={status === 'seeding'}
        data-testid="setup-seed-btn"
      >
        {status === 'done' ? (
          <>
            <CheckCircle2 className="mr-1.5 h-4 w-4" />
            Seeded
          </>
        ) : (
          'Seed example data'
        )}
      </Button>
      {status === 'empty' && (
        <p className="text-xs text-theme-secondary" data-testid="setup-seed-empty">
          Nothing to seed in this build.
        </p>
      )}
      {status === 'error' && (
        <p className="flex items-center gap-1 text-xs text-theme-danger-fg" data-testid="setup-seed-error">
          <XCircle className="h-4 w-4" />
          Seeding failed — you can continue and seed later.
        </p>
      )}
    </div>
  );
};

export default SeedStep;

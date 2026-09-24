import { featureRegistry, type MentionMember } from '@/shared/services/featureRegistry';
import { logger } from '@/shared/utils/logger';

/**
 * Members for the chat @-mention picker: the workspace's own members plus
 * whatever extensions contribute through registered mention sources. Every
 * source is best-effort; one that rejects is dropped and logged at debug
 * level only, never surfaced to the user.
 */
export async function gatherMentionMembers(
  loadWorkspaceMembers: () => Promise<unknown[]>
): Promise<MentionMember[]> {
  const sources = featureRegistry.getMentionSources();
  const results = await Promise.allSettled([
    loadWorkspaceMembers(),
    ...sources.map((source) => source()),
  ]);

  return results.flatMap((result, index) => {
    if (result.status === 'fulfilled') return result.value as MentionMember[];
    logger.debug('Mention source failed; dropping its members', {
      source: index === 0 ? 'workspace' : `registered#${index - 1}`,
      error: result.reason instanceof Error ? result.reason.message : String(result.reason),
    });
    return [];
  });
}

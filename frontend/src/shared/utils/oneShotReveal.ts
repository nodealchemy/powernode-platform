// IMP-246994888a1f — shared narrowing for the server's one-shot reveal slot.
//
// Two endpoints carry `revealed_result` (the autonomy approve action and the
// governance decide action) and both hand it to the same modal, so the "is
// there anything here worth showing an operator" question is answered once.

/**
 * Narrows a one-shot slot to something worth revealing: a plain object with at
 * least one non-empty field. A bare string would otherwise render one row per
 * character, and an all-empty slot would open a dialog with nothing in it that
 * the operator still has to acknowledge to escape.
 *
 * Returns null when there is nothing to show.
 */
export function takeRevealableResult(revealed: unknown): Record<string, unknown> | null {
  if (!revealed || typeof revealed !== 'object' || Array.isArray(revealed)) return null;
  const shown = Object.fromEntries(
    Object.entries(revealed as Record<string, unknown>).filter(
      ([, value]) => value !== null && value !== undefined && value !== ''
    )
  );
  return Object.keys(shown).length > 0 ? shown : null;
}

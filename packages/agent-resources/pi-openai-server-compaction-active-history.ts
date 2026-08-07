export type ActiveHistoryEntry = {
	id: string;
	parentId?: string | null;
};

/** Keep the active compaction and only entries descended from it. */
export function selectCompactionLineage<T extends ActiveHistoryEntry>(
	activeEntries: readonly T[],
	latestCompaction: T | undefined,
): T[] {
	if (!latestCompaction) return [];

	const lineage = [latestCompaction];
	const lineageIds = new Set([latestCompaction.id]);
	for (const entry of activeEntries) {
		if (lineageIds.has(entry.id) || !entry.parentId || !lineageIds.has(entry.parentId)) continue;
		lineage.push(entry);
		lineageIds.add(entry.id);
	}
	return lineage;
}

/** Include the finalized assistant that message_end has not persisted yet. */
export function completedContextLength(requestContextLength: number | undefined): number | undefined {
	if (
		requestContextLength === undefined ||
		!Number.isSafeInteger(requestContextLength) ||
		requestContextLength < 0 ||
		requestContextLength >= Number.MAX_SAFE_INTEGER
	) {
		return undefined;
	}
	return requestContextLength + 1;
}

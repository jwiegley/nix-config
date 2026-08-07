import {
	isMemoryDetails,
	isObservationsDroppedEntry,
	isObservationsRecordedEntry,
	isReflectionsRecordedEntry,
	type Entry,
	type Observation,
	type Reflection,
} from "../om/ledger/types.js";
import { recallMemorySources, type RecallResult } from "../om/ledger/recall.js";
import type { RelatedObservation, RelatedReflection } from "../om/reverse-recall.js";
import type { HistoryMetadata, IndexedHistorySessionManager } from "./streaming-history.js";

const OBSERVATIONS = "om.observations.recorded";
const REFLECTIONS = "om.reflections.recorded";
const DROPPED = "om.observations.dropped";
const OM_TYPES = new Set([OBSERVATIONS, REFLECTIONS, DROPPED]);

interface Located<T> {
	value: T;
	entryId: string;
	entryOrdinal: number;
	recordOrdinal: number;
}

function asEntry(value: unknown): Entry | undefined {
	if (!value || typeof value !== "object") return undefined;
	const candidate = value as Partial<Entry>;
	return typeof candidate.id === "string" && typeof candidate.type === "string" ? (candidate as Entry) : undefined;
}

async function forEachActiveOmEntry(
	sessionManager: IndexedHistorySessionManager,
	visitor: (entry: Entry, metadata: HistoryMetadata) => void | Promise<void>,
): Promise<void> {
	await sessionManager.iterateActiveAncestry(async (metadata) => {
		if (!metadata.customType || !OM_TYPES.has(metadata.customType)) return;
		const entry = asEntry(sessionManager.getEntry(metadata.id));
		if (entry) await visitor(entry, metadata);
	});
}

function locatedOrder<T>(left: Located<T>, right: Located<T>): number {
	return left.entryOrdinal - right.entryOrdinal || left.recordOrdinal - right.recordOrdinal;
}

export async function relatedMemoryForEntryIds(
	sessionManager: IndexedHistorySessionManager,
	targetEntryIds: string[],
): Promise<{ observations: RelatedObservation[]; reflections: RelatedReflection[] }> {
	if (targetEntryIds.length === 0) return { observations: [], reflections: [] };
	const targets = new Set(targetEntryIds);
	const matchingObservations: Array<Located<Observation>> = [];
	const matchingObservationIds = new Set<string>();
	await forEachActiveOmEntry(sessionManager, (entry, metadata) => {
		if (!isObservationsRecordedEntry(entry)) return;
		entry.data.observations.forEach((observation, recordOrdinal) => {
			if (!observation.sourceEntryIds.some((id) => targets.has(id))) return;
			matchingObservations.push({
				value: observation,
				entryId: entry.id,
				entryOrdinal: metadata.ordinal,
				recordOrdinal,
			});
			matchingObservationIds.add(observation.id);
		});
	});

	const droppedIds = new Set<string>();
	const matchingReflections: Array<Located<Reflection>> = [];
	if (matchingObservationIds.size > 0) {
		await forEachActiveOmEntry(sessionManager, (entry, metadata) => {
			if (isObservationsDroppedEntry(entry)) {
				for (const id of entry.data.observationIds) if (matchingObservationIds.has(id)) droppedIds.add(id);
				return;
			}
			if (!isReflectionsRecordedEntry(entry)) return;
			entry.data.reflections.forEach((reflection, recordOrdinal) => {
				if (!reflection.supportingObservationIds.some((id) => matchingObservationIds.has(id))) return;
				matchingReflections.push({
					value: reflection,
					entryId: entry.id,
					entryOrdinal: metadata.ordinal,
					recordOrdinal,
				});
			});
		});
	}

	matchingObservations.sort(locatedOrder);
	matchingReflections.sort(locatedOrder);
	return {
		observations: matchingObservations.map(({ value }) => ({
			memoryId: value.id,
			content: value.content,
			timestamp: value.timestamp,
			relevance: value.relevance,
			status: droppedIds.has(value.id) ? "dropped" : "active",
			matchedEntryIds: value.sourceEntryIds.filter((id) => targets.has(id)),
		})),
		reflections: matchingReflections.map(({ value }) => ({ memoryId: value.id, content: value.content })),
	};
}

interface LocatedEntry {
	entry: Entry;
	ordinal: number;
}

export async function recallMemorySourcesStreaming(
	sessionManager: IndexedHistorySessionManager,
	memoryId: string,
): Promise<RecallResult> {
	const directObservationEntryIds = new Set<string>();
	const directReflectionEntryIds = new Set<string>();
	const supportingObservationIds = new Set<string>();
	await forEachActiveOmEntry(sessionManager, (entry) => {
		if (isObservationsRecordedEntry(entry)) {
			if (entry.data.observations.some((observation) => observation.id === memoryId)) {
				directObservationEntryIds.add(entry.id);
			}
			return;
		}
		if (!isReflectionsRecordedEntry(entry)) return;
		const matching = entry.data.reflections.filter((reflection) => reflection.id === memoryId);
		if (matching.length === 0) return;
		directReflectionEntryIds.add(entry.id);
		for (const reflection of matching) {
			for (const id of reflection.supportingObservationIds) supportingObservationIds.add(id);
		}
	});

	const relevantObservationIds = new Set([memoryId, ...supportingObservationIds]);
	const sourceEntryIds = new Set<string>();
	const retained: LocatedEntry[] = [];
	await forEachActiveOmEntry(sessionManager, (entry, metadata) => {
		if (isObservationsRecordedEntry(entry)) {
			const observations = entry.data.observations.filter((observation) => relevantObservationIds.has(observation.id));
			if (observations.length === 0) return;
			for (const observation of observations) {
				for (const id of observation.sourceEntryIds) sourceEntryIds.add(id);
			}
			retained.push({ entry: { ...entry, data: { ...entry.data, observations } }, ordinal: metadata.ordinal });
			return;
		}
		if (isReflectionsRecordedEntry(entry)) {
			if (!directReflectionEntryIds.has(entry.id)) return;
			const reflections = entry.data.reflections.filter((reflection) => reflection.id === memoryId);
			retained.push({ entry: { ...entry, data: { ...entry.data, reflections } }, ordinal: metadata.ordinal });
			return;
		}
		if (isObservationsDroppedEntry(entry)) {
			const observationIds = entry.data.observationIds.filter((id) => relevantObservationIds.has(id));
			if (observationIds.length > 0) {
				retained.push({ entry: { ...entry, data: { ...entry.data, observationIds } }, ordinal: metadata.ordinal });
			}
		}
	});

	if (directObservationEntryIds.size === 0 && directReflectionEntryIds.size === 0) {
		return recallMemorySources([], memoryId);
	}

	const activeSourceIds = new Set<string>();
	if (sourceEntryIds.size > 0) {
		await sessionManager.iterateActiveAncestry((metadata) => {
			if (sourceEntryIds.has(metadata.id)) activeSourceIds.add(metadata.id);
		});
	}
	for (const sourceId of sourceEntryIds) {
		if (!activeSourceIds.has(sourceId)) continue;
		const entry = asEntry(sessionManager.getEntry(sourceId));
		const metadata = sessionManager.getEntryMetadata(sourceId);
		if (entry && metadata) retained.push({ entry, ordinal: metadata.ordinal });
	}
	retained.sort((left, right) => left.ordinal - right.ordinal);
	return recallMemorySources(
		retained.map(({ entry }) => entry),
		memoryId,
	);
}

export function sourceMessageOrdinals(
	sessionManager: IndexedHistorySessionManager,
	sourceEntryIds: string[],
): Map<string, number> {
	const result = new Map<string, number>();
	for (const id of sourceEntryIds) {
		const ordinal = sessionManager.getEntryMetadata(id)?.messageOrdinal;
		if (ordinal !== undefined) result.set(id, ordinal);
	}
	return result;
}

function memoryDetails(entry: Entry): unknown {
	if (isMemoryDetails(entry.details)) return entry.details;
	if (entry.details && typeof entry.details === "object" && !Array.isArray(entry.details)) {
		const nested = (entry.details as Record<string, unknown>)["om.folded"];
		if (isMemoryDetails(nested)) return nested;
	}
	return undefined;
}

function coverageTarget(entry: Entry): string | undefined {
	if (!isObservationsRecordedEntry(entry) && !isReflectionsRecordedEntry(entry) && !isObservationsDroppedEntry(entry)) {
		return undefined;
	}
	return entry.data.coversUpToId;
}

/**
 * Build the exact OM ledger projection without retaining transcript payloads.
 * Lightweight placeholders preserve coverage-boundary ordering for the
 * existing projection reducers.
 */
export async function memoryLedgerEntries(
	sessionManager: IndexedHistorySessionManager,
): Promise<Entry[]> {
	const retained: Array<{ entry: Entry; ordinal: number }> = [];
	const coverageTargets = new Set<string>();
	let retainedVisibleCompaction = false;
	await sessionManager.iterateActiveAncestry((metadata) => {
		if (metadata.customType && OM_TYPES.has(metadata.customType)) {
			const entry = asEntry(sessionManager.getEntry(metadata.id));
			if (!entry) return;
			retained.push({ entry, ordinal: metadata.ordinal });
			const target = coverageTarget(entry);
			if (target) coverageTargets.add(target);
			return;
		}
		if (metadata.type === "compaction" && !retainedVisibleCompaction) {
			const entry = asEntry(sessionManager.getEntry(metadata.id));
			if (!entry || !memoryDetails(entry)) return;
			retained.push({ entry, ordinal: metadata.ordinal });
			retainedVisibleCompaction = true;
		}
	});

	if (coverageTargets.size > 0) {
		await sessionManager.iterateActiveAncestry((metadata) => {
			if (!coverageTargets.has(metadata.id)) return;
			retained.push({
				entry: { type: "memory-boundary", id: metadata.id },
				ordinal: metadata.ordinal,
			});
		});
	}
	retained.sort((left, right) => left.ordinal - right.ordinal);
	return retained.map(({ entry }) => entry);
}

const SOURCE_ENTRY_TYPES = new Set(["message", "custom_message", "branch_summary"]);

export async function rawTokensAfterMarkerStreaming(
	sessionManager: IndexedHistorySessionManager,
	markerId: string | undefined,
	estimateEntryTokens: (entry: Entry) => number,
	includeMarker = false,
): Promise<number> {
	let tokens = 0;
	const stop = Symbol("raw-token-marker");
	try {
		await sessionManager.iterateActiveAncestry((metadata) => {
			if (metadata.id === markerId && !includeMarker) throw stop;
			if (SOURCE_ENTRY_TYPES.has(metadata.type)) {
				const entry = asEntry(sessionManager.getEntry(metadata.id));
				if (entry) tokens += estimateEntryTokens(entry);
			}
			if (metadata.id === markerId) throw stop;
		});
	} catch (error) {
		if (error !== stop) throw error;
	}
	return tokens;
}

export async function rawTokensSinceLastCompactionStreaming(
	sessionManager: IndexedHistorySessionManager,
	estimateEntryTokens: (entry: Entry) => number,
): Promise<number> {
	let compaction: Entry | undefined;
	const stop = Symbol("latest-compaction");
	try {
		await sessionManager.iterateActiveAncestry((metadata) => {
			if (metadata.type !== "compaction") return;
			compaction = asEntry(sessionManager.getEntry(metadata.id));
			throw stop;
		});
	} catch (error) {
		if (error !== stop) throw error;
	}
	if (!compaction) return rawTokensAfterMarkerStreaming(sessionManager, undefined, estimateEntryTokens);
	return compaction.firstKeptEntryId
		? rawTokensAfterMarkerStreaming(sessionManager, compaction.firstKeptEntryId, estimateEntryTokens, true)
		: rawTokensAfterMarkerStreaming(sessionManager, compaction.id, estimateEntryTokens);
}

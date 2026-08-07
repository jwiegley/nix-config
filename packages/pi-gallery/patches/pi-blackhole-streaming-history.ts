import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { Message } from "@earendil-works/pi-ai";
import { isContentBearing, textOf, toolCallArgsText } from "./content.js";
import { shortPath } from "./format-recall.js";
import { renderMessage, type RenderedEntry } from "./render-entries.js";
import { getFileIndicators, type FileMatch, type SearchHit, type TouchedFile } from "./search-entries.js";
import type { RecallMode, RecallScope } from "./recall-scope.js";

export interface HistoryMetadata {
	ordinal: number;
	messageOrdinal?: number;
	id: string;
	type: string;
	customType?: string;
}

interface MessageEntry {
	type: "message";
	id: string;
	message: Message;
}

export interface IndexedHistorySessionManager {
	getEntry(id: string): unknown;
	getEntryMetadata(id: string): HistoryMetadata | undefined;
	getMessageByOrdinal(messageOrdinal: number): unknown;
	iterateEntries(
		options: {
			type?: string;
			customType?: string;
			direction?: "forward" | "reverse";
			limit?: number;
		},
		visitor: (entry: unknown, metadata: HistoryMetadata) => void | Promise<void>,
	): Promise<void>;
	iterateActiveAncestry(visitor: (metadata: HistoryMetadata) => void | Promise<void>): Promise<void>;
}

interface LocalBashExec {
	role: "bashExecution";
	command: string;
	output: string;
}

const PAGE_SIZE = 5;
const STOPWORDS = new Set([
	"the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
	"have", "has", "had", "do", "does", "did", "will", "would", "could",
	"should", "may", "might", "can", "shall", "of", "in", "to", "for",
	"with", "on", "at", "from", "by", "as", "into", "through", "during",
	"before", "after", "above", "below", "between", "out", "off", "over",
	"under", "again", "further", "then", "once", "here", "there", "when",
	"where", "why", "how", "all", "both", "each", "few", "more", "most",
	"other", "some", "such", "no", "nor", "not", "only", "own", "same",
	"so", "than", "too", "very", "just", "about", "it", "its", "that",
	"this", "what", "which", "who", "whom", "these", "those",
]);

function asMessageEntry(entry: unknown): MessageEntry | undefined {
	if (!entry || typeof entry !== "object") return undefined;
	const candidate = entry as Partial<MessageEntry>;
	return candidate.type === "message" && typeof candidate.id === "string" && candidate.message
		? (candidate as MessageEntry)
		: undefined;
}

function requireMessageOrdinal(metadata: HistoryMetadata): number {
	if (metadata.messageOrdinal === undefined) {
		throw new Error("Pi session history index does not expose transcript ordinals");
	}
	return metadata.messageOrdinal;
}

async function forEachScopedMessage(
	sessionManager: IndexedHistorySessionManager,
	scope: RecallScope,
	visitor: (entry: MessageEntry, metadata: HistoryMetadata) => void | Promise<void>,
): Promise<void> {
	if (scope === "all") {
		await sessionManager.iterateEntries({ type: "message" }, async (entry, metadata) => {
			const messageEntry = asMessageEntry(entry);
			if (messageEntry) await visitor(messageEntry, metadata);
		});
		return;
	}

	await sessionManager.iterateActiveAncestry(async (metadata) => {
		if (metadata.type !== "message") return;
		const entry = asMessageEntry(sessionManager.getEntry(metadata.id));
		if (entry) await visitor(entry, metadata);
	});
}

function escapeRegex(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function safeRegex(pattern: string): RegExp {
	try {
		return new RegExp(pattern, "i");
	} catch {
		return new RegExp(escapeRegex(pattern), "i");
	}
}

function looksLikeRegex(query: string): boolean {
	return /[|*+?{}()[\]\\^$.]/.test(query);
}

function snippetRegex(terms: string[]): RegExp {
	return new RegExp(
		terms
			.map((term) => {
				try {
					new RegExp(term, "i");
					return term;
				} catch {
					return escapeRegex(term);
				}
			})
			.join("|"),
		"i",
	);
}

function filterStopwords(terms: string[]): string[] {
	const meaningful = terms.filter((term) => !STOPWORDS.has(term.toLowerCase()) && term.length > 1);
	return meaningful.length > 0 ? meaningful : terms;
}

function fullText(message: Message, mode?: RecallMode): string {
	if ((message as { role?: string }).role === "bashExecution") {
		if (mode === "file") return "";
		const bash = message as unknown as LocalBashExec;
		return `${bash.command ?? ""} ${bash.output ?? ""}`;
	}
	if (mode === "file") return toolCallArgsText(message.content);
	const text = textOf(message.content);
	const toolArgs = toolCallArgsText(message.content);
	return toolArgs ? `${text}\n${toolArgs}` : text;
}

function extractToolCallText(args: Record<string, unknown>): string {
	let text = "";
	if (typeof args.content === "string") text += `${args.content}\n`;
	if (Array.isArray(args.edits)) {
		for (const edit of args.edits) {
			if (!edit || typeof edit !== "object") continue;
			if (typeof edit.oldText === "string") text += `${edit.oldText}\n`;
			if (typeof edit.newText === "string") text += `${edit.newText}\n`;
		}
	}
	if (typeof args.oldText === "string" && !Array.isArray(args.edits)) text += `${args.oldText}\n`;
	if (typeof args.newText === "string" && !Array.isArray(args.edits)) text += `${args.newText}\n`;
	return text;
}

function computeFileMatches(message: Message, query: string): FileMatch[] {
	if (!message.content || typeof message.content === "string") return [];
	const rawQuery = query.trim();
	if (!rawQuery) return getFileIndicators(message);
	const regex = looksLikeRegex(rawQuery) ? safeRegex(rawQuery) : snippetRegex(rawQuery.split(/\s+/));
	const matches: FileMatch[] = [];
	for (const part of message.content) {
		if (!part || typeof part !== "object" || part.type !== "toolCall") continue;
		const args = part.arguments as Record<string, unknown>;
		if (!isContentBearing(args)) continue;
		const path = ["path", "filePath", "file_path", "file"]
			.map((key) => args[key])
			.find((value): value is string => typeof value === "string");
		if (!path) continue;
		const matchingLines = extractToolCallText(args)
			.split("\n")
			.filter((line) => regex.test(line));
		if (matchingLines.length > 0) {
			matches.push({
				toolName: part.name || "",
				path,
				lineCount: matchingLines.length,
				snippet: matchingLines[0],
			});
		}
	}
	return matches;
}

function lineSnippet(text: string, regex: RegExp, contextLines = 2): string | undefined {
	const lines = text.split("\n");
	let matchIndex = -1;
	for (let index = 0; index < lines.length; index++) {
		if (regex.test(lines[index])) {
			matchIndex = index;
			break;
		}
	}
	if (matchIndex < 0) return undefined;
	const start = Math.max(0, matchIndex - contextLines);
	const end = Math.min(lines.length, matchIndex + contextLines + 1);
	const result: string[] = [];
	if (start > 0) result.push(`...(${start} lines above)`);
	result.push(...lines.slice(start, end));
	if (end < lines.length) result.push(`...(${lines.length - end} lines below)`);
	return result.join("\n");
}

interface SearchPlan {
	rawQuery: string;
	regex?: RegExp;
	terms: string[];
	snippet: RegExp;
}

interface SearchStats {
	n: number;
	totalLength: number;
	df: Map<string, number>;
}

function createSearchPlan(query: string): SearchPlan {
	const rawQuery = query.trim();
	if (looksLikeRegex(rawQuery)) {
		const regex = safeRegex(rawQuery);
		return { rawQuery, regex, terms: [rawQuery], snippet: regex };
	}
	const terms = filterStopwords(rawQuery.split(/\s+/));
	return { rawQuery, terms, snippet: snippetRegex(terms) };
}

function documentFor(entry: RenderedEntry, message: Message, mode?: RecallMode): { text: string; document: string } {
	const text = fullText(message, mode);
	return { text, document: `${entry.role} ${text} ${entry.files?.join(" ") ?? ""}` };
}

function countMatches(document: string, terms: string[]): number {
	let count = 0;
	for (const term of terms) if (safeRegex(term).test(document)) count++;
	return count;
}

function termFrequency(document: string, term: string): number {
	return document.match(new RegExp(safeRegex(term).source, "gi"))?.length ?? 0;
}

function bm25Score(document: string, plan: SearchPlan, stats: SearchStats): number {
	const documentLength = document.split(/\s+/).length;
	const averageLength = stats.totalLength / Math.max(stats.n, 1);
	let score = 0;
	for (const term of plan.terms) {
		const frequency = termFrequency(document, term);
		if (frequency === 0) continue;
		const documentFrequency = stats.df.get(term) ?? 0;
		const idf = Math.log((stats.n - documentFrequency + 0.5) / (documentFrequency + 0.5) + 1);
		const normalized =
			(frequency * 2.2) / (frequency + 1.2 * (0.25 + (0.75 * documentLength) / averageLength));
		score += idf * normalized;
	}
	return score;
}

async function withResultsDatabase<T>(action: (database: DatabaseSync) => Promise<T>): Promise<T> {
	const root = mkdtempSync(join(tmpdir(), "pi-blackhole-history-"));
	const database = new DatabaseSync(join(root, "results.sqlite"));
	try {
		database.exec("PRAGMA journal_mode = DELETE; PRAGMA synchronous = OFF; PRAGMA temp_store = FILE; PRAGMA cache_size = -2048;");
		return await action(database);
	} finally {
		database.close();
		rmSync(root, { recursive: true, force: true });
	}
}

export interface SearchPage {
	results: SearchHit[];
	totalMatches: number;
	appendedExpandCount: number;
	totalResults: number;
	totalPages: number;
	page: number;
}

export async function searchHistory(
	sessionManager: IndexedHistorySessionManager,
	scope: RecallScope,
	query: string,
	mode: RecallMode,
	page = 1,
	pageSize = PAGE_SIZE,
	expandedOrdinals: number[] = [],
): Promise<SearchPage> {
	const plan = createSearchPlan(query);
	const normalizedPage = Math.max(1, Math.trunc(page));
	const normalizedPageSize = Math.max(1, Math.min(100, Math.trunc(pageSize)));
	return withResultsDatabase(async (database) => {
		database.exec(`
			CREATE TABLE hits (
				message_ordinal INTEGER PRIMARY KEY,
				score REAL NOT NULL,
				query_match INTEGER NOT NULL,
				hit_json TEXT NOT NULL
			);
		`);
		const stats: SearchStats = { n: 0, totalLength: 0, df: new Map() };
		if (!plan.regex) {
			await forEachScopedMessage(sessionManager, scope, (entry, metadata) => {
				const rendered = renderMessage(entry.message, requireMessageOrdinal(metadata), entry.id, false);
				const { document } = documentFor(rendered, entry.message, mode);
				stats.n++;
				stats.totalLength += document.split(/\s+/).length;
				for (const term of plan.terms) {
					if (safeRegex(term).test(document)) stats.df.set(term, (stats.df.get(term) ?? 0) + 1);
				}
			});
		}

		const insert = database.prepare(
			"INSERT INTO hits(message_ordinal, score, query_match, hit_json) VALUES (?, ?, 1, ?)",
		);
		await forEachScopedMessage(sessionManager, scope, (entry, metadata) => {
			const messageOrdinal = requireMessageOrdinal(metadata);
			const rendered = renderMessage(entry.message, messageOrdinal, entry.id, false);
			const { text, document } = documentFor(rendered, entry.message, mode);
			const matchCount = plan.regex ? (plan.regex.test(document) ? 1 : 0) : countMatches(document, plan.terms);
			if (matchCount === 0) return;
			const fileMatches = computeFileMatches(entry.message, plan.rawQuery);
			const hit: SearchHit = {
				...rendered,
				snippet: lineSnippet(text, plan.snippet),
				matchCount,
				...(fileMatches.length > 0 ? { fileMatches } : {}),
			};
			insert.run(messageOrdinal, plan.regex ? 0 : bm25Score(document, plan, stats), JSON.stringify(hit));
		});
		if (expandedOrdinals.length > 0) {
			const expanded = await messagesByOrdinal(sessionManager, scope, expandedOrdinals, true);
			if (expanded.invalid.length > 0) {
				throw new RangeError(`Cannot expand transcript indices: ${expanded.invalid.join(", ")}`);
			}
			const upsertExpanded = database.prepare(`
				INSERT INTO hits(message_ordinal, score, query_match, hit_json)
				VALUES (?, 0, 0, ?)
				ON CONFLICT(message_ordinal) DO UPDATE SET hit_json = excluded.hit_json
			`);
			for (const entry of expanded.entries) upsertExpanded.run(entry.index, JSON.stringify(entry));
		}

		const counts = database
			.prepare("SELECT count(*) AS total, coalesce(sum(query_match), 0) AS matches FROM hits")
			.get() as { total: number; matches: number };
		const totalMatches = counts.matches;
		const appendedExpandCount = counts.total - counts.matches;
		const totalPages = Math.ceil(counts.total / normalizedPageSize);
		const offset = Math.min(Number.MAX_SAFE_INTEGER, (normalizedPage - 1) * normalizedPageSize);
		const order = expandedOrdinals.length > 0 || plan.regex ? "message_ordinal ASC" : "score DESC, message_ordinal ASC";
		const rows = database
			.prepare(`SELECT hit_json FROM hits ORDER BY ${order} LIMIT ? OFFSET ?`)
			.all(normalizedPageSize, offset) as Array<{ hit_json: string }>;
		return {
			results: rows.map((row) => JSON.parse(row.hit_json) as SearchHit),
			totalMatches,
			appendedExpandCount,
			totalResults: counts.total,
			totalPages,
			page: normalizedPage,
		};
	});
}

export async function recentHistory(
	sessionManager: IndexedHistorySessionManager,
	scope: RecallScope,
	limit = 25,
): Promise<SearchHit[]> {
	const entries: Array<{ entry: MessageEntry; metadata: HistoryMetadata }> = [];
	const boundedLimit = Math.max(1, Math.min(4096, Math.trunc(limit)));
	if (scope === "all") {
		await sessionManager.iterateEntries(
			{ type: "message", direction: "reverse", limit: boundedLimit },
			(entry, metadata) => {
				const messageEntry = asMessageEntry(entry);
				if (messageEntry) entries.push({ entry: messageEntry, metadata });
			},
		);
	} else {
		const stop = Symbol("recent-history-complete");
		try {
			await sessionManager.iterateActiveAncestry((metadata) => {
				if (metadata.type !== "message") return;
				const entry = asMessageEntry(sessionManager.getEntry(metadata.id));
				if (entry) entries.push({ entry, metadata });
				if (entries.length >= boundedLimit) throw stop;
			});
		} catch (error) {
			if (error !== stop) throw error;
		}
	}
	return entries.reverse().map(({ entry, metadata }) => {
		const rendered = renderMessage(entry.message, requireMessageOrdinal(metadata), entry.id, false);
		const fileMatches = getFileIndicators(entry.message);
		return fileMatches.length > 0 ? { ...rendered, fileMatches } : rendered;
	});
}

export async function messagesByOrdinal(
	sessionManager: IndexedHistorySessionManager,
	scope: RecallScope,
	ordinals: number[],
	full: boolean,
): Promise<{ entries: RenderedEntry[]; invalid: number[] }> {
	const requested = [...new Set(ordinals)];
	const found = new Map<number, MessageEntry>();
	for (const ordinal of requested) {
		if (!Number.isSafeInteger(ordinal) || ordinal < 0) continue;
		const entry = asMessageEntry(sessionManager.getMessageByOrdinal(ordinal));
		if (entry) found.set(ordinal, entry);
	}
	if (scope === "lineage" && found.size > 0) {
		const wantedIds = new Set([...found.values()].map((entry) => entry.id));
		const activeIds = new Set<string>();
		await sessionManager.iterateActiveAncestry((metadata) => {
			if (wantedIds.has(metadata.id)) activeIds.add(metadata.id);
		});
		for (const [ordinal, entry] of found) if (!activeIds.has(entry.id)) found.delete(ordinal);
	}
	const invalid = requested.filter((ordinal) => !found.has(ordinal));
	return {
		entries: requested.flatMap((ordinal) => {
			const entry = found.get(ordinal);
			return entry ? [renderMessage(entry.message, ordinal, entry.id, full)] : [];
		}),
		invalid,
	};
}

export function messageByOrdinal(
	sessionManager: IndexedHistorySessionManager,
	messageOrdinal: number,
): Message | undefined {
	return asMessageEntry(sessionManager.getMessageByOrdinal(messageOrdinal))?.message;
}

export interface TouchedHistoryPage {
	files: TouchedFile[];
	totalFiles: number;
	totalPages: number;
	page: number;
}

export async function touchedHistory(
	sessionManager: IndexedHistorySessionManager,
	scope: RecallScope,
	page = 1,
	pageSize = PAGE_SIZE,
): Promise<TouchedHistoryPage> {
	const normalizedPage = Math.max(1, Math.trunc(page));
	const normalizedPageSize = Math.max(1, Math.min(100, Math.trunc(pageSize)));
	return withResultsDatabase(async (database) => {
		database.exec(`
			CREATE TABLE touches (
				path TEXT NOT NULL,
				message_ordinal INTEGER NOT NULL,
				part_ordinal INTEGER NOT NULL,
				tool_name TEXT NOT NULL
			);
			CREATE INDEX touches_path ON touches(path, message_ordinal, part_ordinal);
		`);
		const insert = database.prepare(
			"INSERT INTO touches(path, message_ordinal, part_ordinal, tool_name) VALUES (?, ?, ?, ?)",
		);
		await forEachScopedMessage(sessionManager, scope, (entry, metadata) => {
			const messageOrdinal = requireMessageOrdinal(metadata);
			getFileIndicators(entry.message).forEach((match, partOrdinal) => {
				insert.run(match.path, messageOrdinal, partOrdinal, match.toolName);
			});
		});
		const totalFiles = (database.prepare("SELECT count(DISTINCT path) AS count FROM touches").get() as { count: number })
			.count;
		const totalPages = Math.ceil(totalFiles / normalizedPageSize);
		const offset = Math.min(Number.MAX_SAFE_INTEGER, (normalizedPage - 1) * normalizedPageSize);
		const paths = database
			.prepare(`
				SELECT path, message_ordinal AS first_message, part_ordinal AS first_part
				FROM (
					SELECT path, message_ordinal, part_ordinal,
						row_number() OVER (PARTITION BY path ORDER BY message_ordinal, part_ordinal) AS position
					FROM touches
				)
				WHERE position = 1
				ORDER BY first_message, first_part, path
				LIMIT ? OFFSET ?
			`)
			.all(normalizedPageSize, offset) as Array<{ path: string }>;
		const selectTouches = database.prepare(
			"SELECT message_ordinal, tool_name FROM touches WHERE path = ? ORDER BY message_ordinal, part_ordinal",
		);
		const files = paths.map(({ path }) => ({
			path,
			entries: (selectTouches.all(path) as Array<{ message_ordinal: number; tool_name: string }>).map((row) => ({
				index: row.message_ordinal,
				toolName: row.tool_name,
			})),
		}));
		return { files, totalFiles, totalPages, page: normalizedPage };
	});
}

export function formatTouchedHistoryPage(result: TouchedHistoryPage): string {
	if (result.totalFiles === 0) return "No file operations found in session history.";
	const header =
		result.totalPages > 1
			? `Page ${result.page}/${result.totalPages} (${result.totalFiles} total files)`
			: `${result.totalFiles} files touched`;
	const lines = result.files.map((file) => {
		const indices = file.entries.map((entry) => `#${entry.index} (${entry.toolName})`).join(", ");
		return `  ${shortPath(file.path)}    ${indices}`;
	});
	let output = `${header}:\n\n${lines.join("\n")}`;
	if (result.page < result.totalPages) output += `\n\n--- Use page:${result.page + 1} for more results ---`;
	return output;
}

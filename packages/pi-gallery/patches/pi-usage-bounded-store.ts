import {
	chmodSync,
	closeSync,
	mkdirSync,
	mkdtempSync,
	openSync,
	renameSync,
	rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

type SqliteValue = string | number | bigint | null | Uint8Array;
type SqliteRow = Record<string, unknown>;

export interface SyncStatement {
	get(...values: SqliteValue[]): SqliteRow | undefined;
	all(...values: SqliteValue[]): SqliteRow[];
	iterate(...values: SqliteValue[]): IterableIterator<SqliteRow>;
	run(...values: SqliteValue[]): { changes: number };
}

export interface SyncDatabase {
	exec(sql: string): void;
	prepare(sql: string): SyncStatement;
	close(): void;
}

interface RawStatement {
	get(...values: SqliteValue[]): SqliteRow | null | undefined;
	all(...values: SqliteValue[]): SqliteRow[];
	iterate(...values: SqliteValue[]): IterableIterator<SqliteRow>;
	run(...values: SqliteValue[]): { changes?: number | bigint };
	finalize?(): unknown;
}

interface RawDatabase {
	exec(sql: string): unknown;
	prepare(sql: string): RawStatement;
	close(): unknown;
}

type RawDatabaseConstructor = new (path: string) => RawDatabase;

class CompatibleStatement implements SyncStatement {
	private readonly raw: RawStatement;

	constructor(raw: RawStatement) {
		this.raw = raw;
	}

	get(...values: SqliteValue[]): SqliteRow | undefined {
		return this.raw.get(...values) ?? undefined;
	}

	all(...values: SqliteValue[]): SqliteRow[] {
		return this.raw.all(...values);
	}

	iterate(...values: SqliteValue[]): IterableIterator<SqliteRow> {
		return this.raw.iterate(...values);
	}

	run(...values: SqliteValue[]): { changes: number } {
		return { changes: Number(this.raw.run(...values).changes ?? 0) };
	}

	finalize(): void {
		this.raw.finalize?.();
	}
}

class CompatibleDatabase implements SyncDatabase {
	private readonly raw: RawDatabase;
	private readonly statements = new Map<string, CompatibleStatement>();

	constructor(raw: RawDatabase) {
		this.raw = raw;
	}

	exec(sql: string): void {
		this.raw.exec(sql);
	}

	prepare(sql: string): SyncStatement {
		let statement = this.statements.get(sql);
		if (!statement) {
			statement = new CompatibleStatement(this.raw.prepare(sql));
			this.statements.set(sql, statement);
		}
		return statement;
	}

	close(): void {
		for (const statement of this.statements.values()) statement.finalize();
		this.statements.clear();
		this.raw.close();
	}
}

function databaseConstructor(): RawDatabaseConstructor {
	const runtimeProcess = process as typeof process & {
		getBuiltinModule?: (name: string) => unknown;
	};
	if (!runtimeProcess.getBuiltinModule) {
		throw new Error(
			"Usage Dashboard requires synchronous built-in SQLite support",
		);
	}
	if (process.versions.bun) {
		const module = runtimeProcess.getBuiltinModule("bun:sqlite") as
			| { Database?: RawDatabaseConstructor }
			| undefined;
		if (module?.Database) return module.Database;
	}
	const module = runtimeProcess.getBuiltinModule("node:sqlite") as
		| { DatabaseSync?: RawDatabaseConstructor }
		| undefined;
	if (module?.DatabaseSync) return module.DatabaseSync;
	throw new Error("Usage Dashboard could not load a built-in SQLite module");
}

function compatibleDatabase(path: string): SyncDatabase {
	const Database = databaseConstructor();
	return new CompatibleDatabase(new Database(path));
}

export interface CachedFileMetadata {
	size: number;
	mtimeMs: number;
	sessionId: string;
	cwd: string;
	messageCount: number;
	toolUsageCount: number;
}

export interface StoredRecordRow {
	filePath: string;
	payload: string;
}

const CACHE_VERSION = 6;
const SCHEMA = `
	PRAGMA foreign_keys = ON;
	PRAGMA temp_store = FILE;
	CREATE TABLE IF NOT EXISTS files (
		path TEXT PRIMARY KEY,
		size REAL NOT NULL,
		mtime_ms REAL NOT NULL,
		session_id TEXT NOT NULL,
		cwd TEXT NOT NULL,
		message_count INTEGER NOT NULL,
		tool_usage_count INTEGER NOT NULL
	);
	CREATE TABLE IF NOT EXISTS messages (
		file_path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
		ordinal INTEGER NOT NULL,
		payload TEXT NOT NULL,
		PRIMARY KEY (file_path, ordinal)
	) WITHOUT ROWID;
	CREATE TABLE IF NOT EXISTS tool_usages (
		file_path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
		ordinal INTEGER NOT NULL,
		payload TEXT NOT NULL,
		PRIMARY KEY (file_path, ordinal)
	) WITHOUT ROWID;
	PRAGMA user_version = ${CACHE_VERSION};
`;

function openDatabase(path: string): SyncDatabase {
	const descriptor = openSync(path, "a", 0o600);
	closeSync(descriptor);
	chmodSync(path, 0o600);
	const database = compatibleDatabase(path);
	database.exec(
		"PRAGMA foreign_keys = ON; PRAGMA temp_store = FILE; PRAGMA busy_timeout = 5000;",
	);
	return database;
}

function validDatabase(database: SyncDatabase): boolean {
	try {
		const row = database.prepare("PRAGMA user_version").get() as
			| { user_version?: unknown }
			| undefined;
		if (row?.user_version !== CACHE_VERSION) return false;
		database.prepare("SELECT path FROM files LIMIT 1").get();
		return true;
	} catch {
		return false;
	}
}

function createDatabase(path: string): SyncDatabase {
	const database = openDatabase(path);
	database.exec(SCHEMA);
	return database;
}

/** One transaction streams one session file directly into the cache. */
export class UsageCacheWriter {
	private readonly store: UsageCacheStore;
	private readonly filePath: string;
	private readonly insertMessage: SyncStatement;
	private readonly insertToolUsage: SyncStatement;
	private messageCount = 0;
	private toolUsageCount = 0;
	private done = false;

	constructor(
		store: UsageCacheStore,
		filePath: string,
		size: number,
		mtimeMs: number,
	) {
		this.store = store;
		this.filePath = filePath;
		const database = store.database;
		database.exec("BEGIN IMMEDIATE");
		database.prepare("DELETE FROM files WHERE path = ?").run(filePath);
		database
			.prepare(
				"INSERT INTO files(path, size, mtime_ms, session_id, cwd, message_count, tool_usage_count) VALUES (?, ?, ?, '', '', 0, 0)",
			)
			.run(filePath, size, mtimeMs);
		this.insertMessage = database.prepare(
			"INSERT INTO messages(file_path, ordinal, payload) VALUES (?, ?, ?)",
		);
		this.insertToolUsage = database.prepare(
			"INSERT INTO tool_usages(file_path, ordinal, payload) VALUES (?, ?, ?)",
		);
	}

	message(value: unknown): void {
		this.insertMessage.run(
			this.filePath,
			this.messageCount++,
			JSON.stringify(value),
		);
	}

	toolUsage(value: unknown): void {
		this.insertToolUsage.run(
			this.filePath,
			this.toolUsageCount++,
			JSON.stringify(value),
		);
	}

	finish(sessionId: string, cwd: string): void {
		if (this.done) return;
		this.store.database
			.prepare(
				"UPDATE files SET session_id = ?, cwd = ?, message_count = ?, tool_usage_count = ? WHERE path = ?",
			)
			.run(
				sessionId,
				cwd,
				this.messageCount,
				this.toolUsageCount,
				this.filePath,
			);
		this.store.database.exec("COMMIT");
		this.done = true;
	}

	rollback(): void {
		if (this.done) return;
		this.store.database.exec("ROLLBACK");
		this.done = true;
	}
}

/**
 * SQLite-backed extracted-record cache. Only file metadata is loaded into JS;
 * message and tool rows stay on disk and are consumed through iterators.
 */
export class UsageCacheStore {
	readonly database: SyncDatabase;
	private readonly cleanupDir: string | null;

	private constructor(database: SyncDatabase, cleanupDir: string | null) {
		this.database = database;
		this.cleanupDir = cleanupDir;
	}

	static open(cachePath: string | null): UsageCacheStore {
		if (cachePath === null) {
			const cleanupDir = mkdtempSync(join(tmpdir(), "pi-usage-cache-"));
			const path = join(cleanupDir, "cache.sqlite");
			const database = createDatabase(path);
			chmodSync(path, 0o600);
			return new UsageCacheStore(database, cleanupDir);
		}

		mkdirSync(dirname(cachePath), { recursive: true });
		let database: SyncDatabase | null = null;
		try {
			database = openDatabase(cachePath);
			if (validDatabase(database)) {
				chmodSync(cachePath, 0o600);
				return new UsageCacheStore(database, null);
			}
		} catch {
			// A missing, legacy JSON, or corrupt cache is replaced below.
		}
		database?.close();

		const replacement = `${cachePath}.${process.pid}.${Date.now()}.tmp`;
		rmSync(replacement, { force: true });
		const fresh = createDatabase(replacement);
		fresh.close();
		chmodSync(replacement, 0o600);
		renameSync(replacement, cachePath);
		database = openDatabase(cachePath);
		return new UsageCacheStore(database, null);
	}

	metadata(): Map<string, CachedFileMetadata> {
		const files = new Map<string, CachedFileMetadata>();
		const rows = this.database
			.prepare(
				"SELECT path, size, mtime_ms, session_id, cwd, message_count, tool_usage_count FROM files",
			)
			.iterate() as Iterable<{
			path: string;
			size: number;
			mtime_ms: number;
			session_id: string;
			cwd: string;
			message_count: number;
			tool_usage_count: number;
		}>;
		for (const row of rows) {
			files.set(row.path, {
				size: row.size,
				mtimeMs: row.mtime_ms,
				sessionId: row.session_id,
				cwd: row.cwd,
				messageCount: row.message_count,
				toolUsageCount: row.tool_usage_count,
			});
		}
		return files;
	}

	beginFile(filePath: string, size: number, mtimeMs: number): UsageCacheWriter {
		return new UsageCacheWriter(this, filePath, size, mtimeMs);
	}

	removeFile(filePath: string): void {
		this.database.prepare("DELETE FROM files WHERE path = ?").run(filePath);
	}

	removeMissing(livePaths: Set<string>): void {
		const remove = this.database.prepare("DELETE FROM files WHERE path = ?");
		this.database.exec("BEGIN IMMEDIATE");
		try {
			const rows = this.database
				.prepare("SELECT path FROM files")
				.iterate() as Iterable<{
				path: string;
			}>;
			for (const row of rows) {
				if (!livePaths.has(row.path)) remove.run(row.path);
			}
			this.database.exec("COMMIT");
		} catch (error) {
			this.database.exec("ROLLBACK");
			throw error;
		}
	}

	messages(filePath: string): Iterable<StoredRecordRow> {
		return this.database
			.prepare(
				"SELECT file_path AS filePath, payload FROM messages WHERE file_path = ? ORDER BY ordinal",
			)
			.iterate(filePath) as Iterable<StoredRecordRow>;
	}

	toolUsages(filePath?: string): Iterable<StoredRecordRow> {
		if (filePath !== undefined) {
			return this.database
				.prepare(
					"SELECT file_path AS filePath, payload FROM tool_usages WHERE file_path = ? ORDER BY ordinal",
				)
				.iterate(filePath) as Iterable<StoredRecordRow>;
		}
		return this.database
			.prepare(
				"SELECT file_path AS filePath, payload FROM tool_usages ORDER BY file_path, ordinal",
			)
			.iterate() as Iterable<StoredRecordRow>;
	}

	close(): void {
		this.database.close();
		if (this.cleanupDir)
			rmSync(this.cleanupDir, { recursive: true, force: true });
	}
}

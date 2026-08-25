import { lstatSync } from "node:fs";
import { lstat, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const legacyPrefix = "omlx/";
function normalizeStaleModelPatterns(patterns) {
	if (
		!Array.isArray(patterns) ||
		patterns.some((pattern) => typeof pattern !== "string" || pattern === "")
	) {
		throw new Error("Pi stale model patterns must be an array of non-empty strings");
	}
	return new Set(patterns.map((pattern) => pattern.toLowerCase()));
}

function normalizeModelReplacements(replacements) {
	if (
		typeof replacements !== "object" ||
		replacements === null ||
		Array.isArray(replacements) ||
		Object.entries(replacements).some(
			([source, target]) =>
				source === "" || typeof target !== "string" || target === "",
		)
	) {
		throw new Error("Pi model replacements must map non-empty strings to non-empty strings");
	}
	return new Map(
		Object.entries(replacements).map(([source, target]) => [
			source.toLowerCase(),
			target,
		]),
	);
}

function hasPrefix(model, prefix) {
	return model.slice(0, prefix.length).toLowerCase() === prefix;
}

function isStaleModelPattern(model, staleModelPatterns) {
	return staleModelPatterns.has(model.toLowerCase());
}

function legacyProviderOrder(localProvider) {
	if (localProvider === "omlx-hera") return ["omlx-hera", "omlx-clio"];
	if (localProvider === "omlx-clio") return ["omlx-clio", "omlx-hera"];
	throw new Error("Pi legacy oMLX migration requires a managed local provider");
}

function requireEnabledModels(settings) {
	if (
		typeof settings !== "object" ||
		settings === null ||
		Array.isArray(settings)
	) {
		throw new Error("Pi settings must be a JSON object");
	}
	const models = settings.enabledModels;
	if (models === undefined) return undefined;
	if (
		!Array.isArray(models) ||
		models.some((model) => typeof model !== "string")
	) {
		throw new Error("Pi enabledModels must be an array of strings");
	}
	return models;
}

function migratedModels(
	models,
	localProvider,
	staleModelPatterns,
	modelReplacements,
) {
	if (models === undefined || models.length === 0) return undefined;
	const hasLegacyModels = models.some((model) => hasPrefix(model, legacyPrefix));
	if (
		!hasLegacyModels &&
		!models.some((model) => isStaleModelPattern(model, staleModelPatterns))
	)
		return undefined;

	const providers = hasLegacyModels ? legacyProviderOrder(localProvider) : [];
	const existing = new Set(
		models
			.filter(
				(model) =>
					!hasPrefix(model, legacyPrefix) &&
					!isStaleModelPattern(model, staleModelPatterns),
			)
			.map((model) => model.toLowerCase()),
	);
	const result = [];
	const generated = new Set();
	let hasFactory = false;
	for (const model of models) {
		if (isStaleModelPattern(model, staleModelPatterns)) {
			const replacement = modelReplacements.get(model.toLowerCase());
			const key = replacement?.toLowerCase();
			if (
				replacement !== undefined &&
				!isStaleModelPattern(replacement, staleModelPatterns) &&
				!existing.has(key) &&
				!generated.has(key)
			) {
				generated.add(key);
				result.push(replacement);
			}
			continue;
		}
		if (hasPrefix(model, legacyPrefix)) {
			const suffix = model.slice(legacyPrefix.length);
			for (const provider of providers) {
				const candidate = `${provider}/${suffix}`;
				const replacement = modelReplacements.get(candidate.toLowerCase()) ?? candidate;
				const key = replacement.toLowerCase();
				if (
					!isStaleModelPattern(replacement, staleModelPatterns) &&
					!existing.has(key) &&
					!generated.has(key)
				) {
					generated.add(key);
					result.push(replacement);
				}
			}
		} else {
			const isFactory = model.toLowerCase() === "factory/*";
			if (!isFactory || !hasFactory) result.push(model);
			if (isFactory) hasFactory = true;
		}
	}
	if (!hasFactory) result.push("factory/*");
	return result;
}

export async function migrateEnabledModels({
	agentDir,
	localProvider,
	piRoot,
	dryRun = false,
	storage,
	modelReplacements = {},
	staleModelPatterns = [],
}) {
	const replacementModels = normalizeModelReplacements(modelReplacements);
	const staleModels = normalizeStaleModelPatterns(staleModelPatterns);
	const settingsPath = join(resolve(agentDir), "settings.json");
	let originalStat;
	try {
		originalStat = await lstat(settingsPath);
	} catch (error) {
		if (error?.code === "ENOENT") return false;
		throw error;
	}
	if (!originalStat.isFile()) {
		throw new Error("Pi settings.json must be a regular file");
	}
	if (dryRun) {
		const settings = JSON.parse(await readFile(settingsPath, "utf8"));
		return (
			migratedModels(
				requireEnabledModels(settings),
				localProvider,
				staleModels,
				replacementModels,
			) !== undefined
		);
	}

	let settingsStorage = storage;
	if (settingsStorage === undefined) {
		if (!piRoot) throw new Error("PI_CODING_AGENT_ROOT is required");
		const { FileSettingsStorage } = await import(
			pathToFileURL(
				join(resolve(piRoot), "dist", "core", "settings-manager.js"),
			).href
		);
		if (typeof FileSettingsStorage !== "function") {
			throw new Error("Pi FileSettingsStorage is unavailable");
		}
		settingsStorage = new FileSettingsStorage(agentDir, agentDir);
	}
	if (typeof settingsStorage?.withLock !== "function") {
		throw new Error("Pi settings storage is unavailable");
	}

	let changed = false;
	settingsStorage.withLock("global", (current) => {
		if (current === undefined) {
			throw new Error("Pi settings.json disappeared during migration");
		}
		const currentStat = lstatSync(settingsPath);
		if (
			!currentStat.isFile() ||
			currentStat.dev !== originalStat.dev ||
			currentStat.ino !== originalStat.ino
		) {
			throw new Error("Pi settings.json changed during migration");
		}
		const settings = JSON.parse(current);
		const next = migratedModels(
			requireEnabledModels(settings),
			localProvider,
			staleModels,
			replacementModels,
		);
		if (next === undefined) return undefined;
		changed = true;
		return JSON.stringify({ ...settings, enabledModels: next }, null, 2);
	});
	return changed;
}

if (
	process.argv[1] &&
	import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
	const dryRun = Object.hasOwn(process.env, "DRY_RUN");
	const modelReplacements = JSON.parse(
		process.env.PI_OMLX_MODEL_REPLACEMENTS ?? "null",
	);
	const staleModelPatterns = JSON.parse(
		process.env.PI_OMLX_STALE_MODEL_PATTERNS ?? "null",
	);
	await migrateEnabledModels({
		agentDir: process.env.PI_CODING_AGENT_DIR,
		localProvider: process.env.PI_OMLX_LOCAL_PROVIDER,
		piRoot: process.env.PI_CODING_AGENT_ROOT,
		dryRun,
		modelReplacements,
		staleModelPatterns,
	});
}

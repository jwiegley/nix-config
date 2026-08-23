import { lstatSync } from "node:fs";
import { lstat, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const legacyPrefix = "omlx/";

function hasPrefix(model, prefix) {
	return model.slice(0, prefix.length).toLowerCase() === prefix;
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

function migratedModels(models, localProvider) {
	if (
		models === undefined ||
		models.length === 0 ||
		!models.some((model) => hasPrefix(model, legacyPrefix))
	) {
		return undefined;
	}
	const providers = legacyProviderOrder(localProvider);
	const existing = new Set(
		models
			.filter((model) => !hasPrefix(model, legacyPrefix))
			.map((model) => model.toLowerCase()),
	);
	const result = [];
	const generated = new Set();
	let hasFactory = false;
	for (const model of models) {
		if (hasPrefix(model, legacyPrefix)) {
			const suffix = model.slice(legacyPrefix.length);
			for (const provider of providers) {
				const replacement = `${provider}/${suffix}`;
				const key = replacement.toLowerCase();
				if (!existing.has(key) && !generated.has(key)) {
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
}) {
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
			migratedModels(requireEnabledModels(settings), localProvider) !== undefined
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
		const next = migratedModels(requireEnabledModels(settings), localProvider);
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
	await migrateEnabledModels({
		agentDir: process.env.PI_CODING_AGENT_DIR,
		localProvider: process.env.PI_OMLX_LOCAL_PROVIDER,
		piRoot: process.env.PI_CODING_AGENT_ROOT,
		dryRun,
	});
}

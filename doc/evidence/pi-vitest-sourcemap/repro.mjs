import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const dist = resolve("node_modules/tsx/dist");
const vitestUtils = await import(
	pathToFileURL(resolve("node_modules/@vitest/utils/dist/source-map/node.js")).href
);
let matched = 0;
let threw = 0;

for (const name of readdirSync(dist)) {
	if (!/\.(?:cjs|mjs|js)$/.test(name)) continue;
	const path = resolve(dist, name);
	const code = readFileSync(path, "utf8");
	if (!code.includes("sourceMappingURL=data:application/json;base64,")) continue;
	matched++;
	try {
		const result = vitestUtils.extractSourcemapFromFile(code, path);
		console.log(`NO_THROW ${name} result=${JSON.stringify(result)}`);
	} catch (error) {
		threw++;
		console.error(`THROWS ${name} -> ${error}`);
	}
}

if (matched === 0) throw new Error("tsx bundle with an inline-source-map marker was not found");
process.exitCode = threw > 0 ? 1 : 0;

import {
	registerLocalProvider,
	type LocalModelEndpoints,
	type ManagedLocalModelEndpoint,
} from "./local-openai-provider.js";

function normalizedEndpoint(
	value: string | ManagedLocalModelEndpoint,
): ManagedLocalModelEndpoint {
	return typeof value === "string"
		? { baseUrl: value, apiKey: { env: "OMLX_API_KEY" } }
		: value;
}

export default async function piProviderOmlx(
	pi: Parameters<typeof registerLocalProvider>[0],
	localModelEndpoints: LocalModelEndpoints = {},
): Promise<void> {
	const configured = Object.entries(localModelEndpoints)
		.filter(([id]) => id === "omlx" || id.startsWith("omlx-"))
		.sort(([left], [right]) => left.localeCompare(right));
	const endpoints =
		configured.length > 0
			? configured
			: ([
				[
					"omlx",
					{
						baseUrl: "http://localhost:8000/v1",
						apiKey: { env: "OMLX_API_KEY" },
					},
				],
			] as const);

	for (const [id, value] of endpoints) {
		const endpoint = normalizedEndpoint(value);
		const apiKey = process.env[endpoint.apiKey.env];
		if (!apiKey) {
			process.emitWarning(
				`[${id}] Credential environment is unset; provider was not registered`,
			);
			continue;
		}
		await registerLocalProvider(pi, {
			id,
			name: id === "omlx" ? "oMLX" : `oMLX ${id.slice("omlx-".length)}`,
			baseUrl: endpoint.baseUrl,
			apiKey,
		});
	}
}

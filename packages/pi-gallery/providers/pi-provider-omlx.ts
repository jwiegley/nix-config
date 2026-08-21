import {
	type LocalModelEndpoints,
	registerLocalProvider,
} from "./local-openai-provider.js";

type OmlxEndpoint = LocalModelEndpoints[number] & {
	apiKey: NonNullable<LocalModelEndpoints[number]["apiKey"]>;
};

export default async function piProviderOmlx(
	pi: Parameters<typeof registerLocalProvider>[0],
	localModelEndpoints: readonly OmlxEndpoint[] = [],
): Promise<void> {
	for (const endpoint of localModelEndpoints) {
		const apiKey = process.env[endpoint.apiKey.env];
		if (!apiKey) {
			process.emitWarning(
				`[${endpoint.id}] Credential environment is unset; provider was not registered`,
			);
			continue;
		}
		await registerLocalProvider(pi, {
			id: endpoint.id,
			name: endpoint.name,
			baseUrl: endpoint.baseUrl,
			apiKey,
		});
	}
}

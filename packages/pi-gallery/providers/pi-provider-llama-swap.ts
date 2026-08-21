import {
	type LocalModelEndpoints,
	registerLocalProvider,
} from "./local-openai-provider.js";

export default async function piProviderLlamaSwap(
	pi: Parameters<typeof registerLocalProvider>[0],
	localModelEndpoints: LocalModelEndpoints = [],
): Promise<void> {
	for (const endpoint of localModelEndpoints) {
		await registerLocalProvider(pi, {
			id: endpoint.id,
			name: endpoint.name,
			baseUrl: endpoint.baseUrl,
			apiKey: "dummy-key",
		});
	}
}

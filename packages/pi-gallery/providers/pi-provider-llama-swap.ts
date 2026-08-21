import {
	registerLocalProvider,
	type LocalModelEndpoints,
} from "./local-openai-provider.js";

export default async function piProviderLlamaSwap(
	pi: Parameters<typeof registerLocalProvider>[0],
	localModelEndpoints: LocalModelEndpoints = {},
): Promise<void> {
	const configured = localModelEndpoints["llama-swap"];
	await registerLocalProvider(pi, {
		id: "llama-swap",
		name: "llama-swap",
		baseUrl:
			typeof configured === "string"
				? configured
				: (configured?.baseUrl ?? "http://localhost:8080/v1"),
		apiKey: "dummy-key",
	});
}

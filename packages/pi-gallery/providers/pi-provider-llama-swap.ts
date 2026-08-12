import { registerLocalProvider } from "./local-openai-provider.js";

export default async function piProviderLlamaSwap(
	pi: Parameters<typeof registerLocalProvider>[0],
	localModelEndpoints: Readonly<Record<string, string>> = {},
): Promise<void> {
	await registerLocalProvider(pi, {
		id: "llama-swap",
		name: "llama-swap",
		baseUrl: localModelEndpoints["llama-swap"] ?? "http://localhost:8080/v1",
		apiKey: "dummy-key",
	});
}

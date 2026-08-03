import { registerLocalProvider } from "./local-openai-provider.js";

export default async function piProviderLlamaSwap(
	pi: Parameters<typeof registerLocalProvider>[0],
): Promise<void> {
	await registerLocalProvider(pi, {
		id: "llama-swap",
		name: "llama-swap",
		baseUrl: "http://127.0.0.1:8080/v1",
		apiKey: "local-no-auth",
	});
}

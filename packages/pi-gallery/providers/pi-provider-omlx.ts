import { registerLocalProvider } from "./local-openai-provider.js";

export default async function piProviderOmlx(
	pi: Parameters<typeof registerLocalProvider>[0],
	localModelEndpoints: Readonly<Record<string, string>> = {},
): Promise<void> {
	await registerLocalProvider(pi, {
		id: "omlx",
		name: "oMLX",
		baseUrl: localModelEndpoints.omlx ?? "http://localhost:8000/v1",
		apiKey: "dummy-key",
	});
}

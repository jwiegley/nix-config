import { registerLocalProvider } from "./local-openai-provider.js";

export default async function piProviderOmlx(
	pi: Parameters<typeof registerLocalProvider>[0],
): Promise<void> {
	await registerLocalProvider(pi, {
		id: "omlx",
		name: "oMLX",
		baseUrl: "http://127.0.0.1:8000/v1",
		apiKey: "dummy-key",
	});
}

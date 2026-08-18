import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const piRoot = process.env.PI_CODING_AGENT_ROOT;
const extensionRoot = process.env.PI_MULTI_PASS_ROOT;
const agentDir = process.env.PI_CODING_AGENT_DIR;
const projectDir = process.env.PI_MULTI_PASS_PROJECT;
assert.ok(piRoot && extensionRoot && agentDir && projectDir);

const source = readFileSync(join(extensionRoot, "extensions/multi-sub.ts"), "utf8");
assert.doesNotMatch(source, /@mariozechner\/pi-ai\/oauth/);
assert.match(source, /builtinProviders\(\)/);
assert.doesNotMatch(source, /refreshToken\s*\(/);

mkdirSync(agentDir, { recursive: true });
mkdirSync(projectDir, { recursive: true });
writeFileSync(
  join(agentDir, "multi-pass.json"),
  JSON.stringify({
    subscriptions: [
      { provider: "anthropic", index: 2 },
      { provider: "openai-codex", index: 3 },
      { provider: "github-copilot", index: 4 },
      { provider: "google-gemini-cli", index: 5 },
      { provider: "google-antigravity", index: 6 },
    ],
    pools: [],
    chains: [],
    presets: [],
  }),
  { mode: 0o600 },
);

const records = new Map();
const fakeOAuth = (providerId) => ({
  name: `Fixture ${providerId}`,
  isSubscription: true,
  async login(interaction) {
    interaction.signal.throwIfAborted();
    const answer = await interaction.prompt({
      type: "text",
      message: `Fixture prompt for ${providerId}`,
    });
    interaction.signal.throwIfAborted();
    interaction.notify({ type: "progress", message: `Fixture progress for ${providerId}` });
    records.set(`${providerId}:login`, { signal: interaction.signal, answer });
    return {
      type: "oauth",
      access: `fixture-access-${providerId}`,
      refresh: `fixture-refresh-${providerId}`,
      expires: 4_102_444_800_000,
    };
  },
  async refresh(credential, signal) {
    signal.throwIfAborted();
    records.set(`${providerId}:refresh`, { signal, credential });
    return {
      ...credential,
      type: "oauth",
      access: `fixture-refreshed-${providerId}`,
    };
  },
  async toAuth(credential) {
    records.set(`${providerId}:auth`, credential);
    return {
      apiKey: credential.access,
      ...(providerId === "github-copilot"
        ? { baseUrl: "https://fixture.copilot.example.invalid" }
        : {}),
    };
  },
});

const oauthLoaders = await import(
  pathToFileURL(join(piRoot, "node_modules/@earendil-works/pi-ai/dist/auth/oauth/load.js"))
);
oauthLoaders.registerBundledOAuthFlowLoaders({
  anthropic: () => fakeOAuth("anthropic"),
  openaiCodex: () => fakeOAuth("openai-codex"),
  githubCopilot: () => fakeOAuth("github-copilot"),
  openrouter: () => fakeOAuth("openrouter"),
  kimiCoding: () => fakeOAuth("kimi-coding"),
  xai: () => fakeOAuth("xai"),
  radius: () => fakeOAuth("radius"),
});

globalThis.fetch = async () => {
  throw new Error("pi-multi-pass OAuth compatibility check attempted network access");
};

const { loadExtensions } = await import(
  pathToFileURL(join(piRoot, "dist/core/extensions/loader.js"))
);
const loaded = await loadExtensions([join(extensionRoot, "extensions/multi-sub.ts")], projectDir);
assert.deepEqual(loaded.errors, []);
assert.equal(loaded.extensions.length, 1);
assert.deepEqual(loaded.runtime.pendingProviderRegistrations, []);

const registrations = loaded.runtime.pendingNativeProviderRegistrations;
assert.deepEqual(
  registrations.map(({ provider }) => provider.id).sort(),
  ["anthropic-2", "github-copilot-4", "openai-codex-3"],
  "managed Pi must ignore providers removed from its native catalog",
);

for (const { provider } of registrations) {
  const baseProvider = provider.id.replace(/-\d+$/, "");
  assert.deepEqual(Object.keys(provider.auth), ["oauth"]);
  assert.ok(provider.auth.oauth);
  const models = provider.getModels();
  assert.ok(models.length > 0, `${provider.id} has no cloned models`);
  assert.ok(models.every((model) => model.provider === provider.id));

  const loginController = new AbortController();
  const events = [];
  const prompts = [];
  const credential = await provider.auth.oauth.login({
    signal: loginController.signal,
    async prompt(prompt) {
      prompts.push(prompt);
      return `fixture-answer-${baseProvider}`;
    },
    notify(event) {
      events.push(event);
    },
  });
  assert.equal(records.get(`${baseProvider}:login`).signal, loginController.signal);
  assert.equal(records.get(`${baseProvider}:login`).answer, `fixture-answer-${baseProvider}`);
  assert.equal(prompts.length, 1);
  assert.deepEqual(events, [
    { type: "progress", message: `Fixture progress for ${baseProvider}` },
  ]);
  if (baseProvider === "github-copilot") {
    assert.equal(typeof provider.filterModels, "function");
    assert.ok(models.length > 1);
    const filtered = provider.filterModels(models, {
      ...credential,
      availableModelIds: [models[0].id],
    });
    assert.deepEqual(filtered.map((model) => model.id), [models[0].id]);
  }

  const refreshController = new AbortController();
  const refreshed = await provider.auth.oauth.refresh(credential, refreshController.signal);
  assert.equal(records.get(`${baseProvider}:refresh`).signal, refreshController.signal);
  assert.equal(refreshed.access, `fixture-refreshed-${baseProvider}`);
  const auth = await provider.auth.oauth.toAuth(refreshed);
  assert.equal(auth.apiKey, refreshed.access);
  if (baseProvider === "github-copilot") {
    assert.equal(auth.baseUrl, "https://fixture.copilot.example.invalid");
  }

  const cancelled = new AbortController();
  cancelled.abort();
  await assert.rejects(
    provider.auth.oauth.refresh(credential, cancelled.signal),
    (error) => error?.name === "AbortError",
  );
}

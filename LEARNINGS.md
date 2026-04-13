# Clicky — Project Learnings

Lessons learned from setting up, configuring, and extending the Clicky codebase. Reference for future model integrations or re-setups from the open source repo.

---

## Adding a New AI Model (e.g. Gemini, or any future model)

### The pattern is: Worker route + Swift client + CompanionManager dispatch + UI button

Four files to touch, one to create:

1. **Worker route** (`worker/src/index.ts`) — Add a new route (e.g. `/gemini`) that receives the request body, extracts the model name, injects the API key, and proxies to the upstream API. Each API has its own auth mechanism (Anthropic uses a header, Gemini uses a query parameter). Add the new API key to the `Env` interface.

2. **Swift API client** (new file, e.g. `GeminiAPI.swift`) — Mirror the structure of `ClaudeAPI.swift` exactly: same method signatures, same URLSession config, same TLS warmup pattern. The differences are in request body format and SSE response parsing. Keep the same `analyzeImageStreaming()` interface so CompanionManager can call either client the same way.

3. **CompanionManager dispatch** — Add a lazy var for the new client, a computed property to detect which provider is selected (e.g. `selectedModel.hasPrefix("gemini-")`), and if/else dispatch at the two call sites (`sendTranscriptToClaudeWithScreenshot` and `performOnboardingDemoInteraction`).

4. **Model picker button** (`CompanionPanelView.swift`) — One line: `modelOptionButton(label: "Flash", modelID: "gemini-2.5-flash")`. The existing helper handles everything.

5. **CLAUDE.md** — Update the Key Files table, architecture section, worker routes, and secrets list.

### Key API format differences to watch for

| Aspect | Claude (Anthropic) | Gemini (Google) | OpenAI |
|--------|-------------------|-----------------|--------|
| Roles | `user` / `assistant` | `user` / `model` | `user` / `assistant` |
| Message structure | `messages[].content[]` | `contents[].parts[]` | `messages[].content[]` |
| Image embedding | `source.type: "base64"` | `inlineData.mimeType + data` | `image_url.url: "data:..."` |
| System prompt | Top-level `system` field | `systemInstruction.parts[]` | `messages[0].role: "system"` |
| SSE text extraction | `delta.type == "text_delta"` → `delta.text` | `candidates[0].content.parts[].text` | `choices[0].delta.content` |
| Stream end marker | `data: [DONE]` | Stream just ends | `data: [DONE]` |
| Max tokens field | `max_tokens` | `generationConfig.maxOutputTokens` | `max_completion_tokens` |
| Auth in worker | Header: `x-api-key` | Query param: `key=` | Header: `Authorization: Bearer` |

### Don't create a protocol abstraction

The codebase convention is "three similar lines is better than a premature abstraction." Each API client is a standalone class with compatible method signatures. CompanionManager uses if/else dispatch based on model prefix. This is intentional — it keeps each client self-contained and easy to modify independently.

---

## Cloudflare Worker Secrets — Getting Them Right

### The `wrangler secret put` interactive prompt can silently corrupt keys

We hit invalid API key errors for every service (Anthropic, AssemblyAI, ElevenLabs, Gemini) because the interactive `wrangler secret put` prompt was including trailing whitespace or newlines.

**Fix:** Pipe the key directly to avoid any trailing characters:
```bash
echo -n "YOUR_KEY" | npx wrangler secret put SECRET_NAME
```

**Always redeploy after updating secrets:**
```bash
npx wrangler deploy
```

### Test worker routes independently with curl before debugging the app

When an API key error appears in Xcode, test the worker directly first:
```bash
# Test AssemblyAI token endpoint
curl -X POST "https://your-worker.workers.dev/transcribe-token"

# Test Gemini (need a valid request body)
curl -X POST "https://your-worker.workers.dev/gemini" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-2.5-flash","contents":[{"role":"user","parts":[{"text":"hello"}]}]}'
```

This isolates whether the issue is the worker/key or the Swift client.

---

## Xcode Project Setup for Clicky

### New Swift files must be added to the Xcode target

Creating a `.swift` file on disk (via Claude Code, terminal, etc.) does NOT add it to the Xcode project. You must:
1. Drag the file from Finder into the Xcode project navigator
2. Or right-click → "Add Files to..." in Xcode
3. Verify **Target Membership** is checked in the File Inspector (Cmd+Option+1)

If the file shows a **?** icon in the sidebar, target membership isn't set.

### Never run xcodebuild from terminal

It invalidates TCC permissions (screen recording, accessibility, microphone). Always build with **Cmd+R** in Xcode.

### Signing just needs a free Apple ID

No paid developer account needed. Any Apple ID works — sign in via Xcode → Settings → Accounts. Select "Personal Team" under Signing & Capabilities.

---

## Menu Bar Icon Visibility

### MacBook notch hides overflow status items

On MacBooks with a notch (Air M2, Pro M1+), the menu bar has limited space between the app menus and the notch. If there are too many icons, macOS silently hides some — including Clicky's.

**Fixes applied:**
- Replaced custom-drawn triangle icon with SF Symbol (`cursorarrow.click.2`) for reliable rendering
- Added **Cmd+Shift+C** keyboard shortcut to toggle the panel without needing the icon
- Made the panel auto-open on launch
- Made the panel draggable with saved position

**User fix:** Hold Cmd and drag unneeded menu bar icons off the bar to free space.

---

## ElevenLabs Free Tier + Cloudflare Workers

ElevenLabs detects requests coming through Cloudflare Workers as proxy/VPN traffic and blocks free tier usage with "Unusual activity detected." 

**Workaround:** Fall back to macOS `NSSpeechSynthesizer` for free, offline TTS. The voice quality is lower but it works immediately with no API key.

**Fix:** A $5/mo ElevenLabs Starter plan removes the proxy restriction.

---

## API Cost Reference (as of April 2026)

| Service | Free Tier | Paid Cost |
|---------|-----------|-----------|
| Gemini 2.5 Flash | 500 req/day | ~$0.001/interaction |
| Claude Sonnet | None (pay-as-you-go) | ~$0.05–0.15/interaction |
| Claude Opus | None | ~$0.20–0.60/interaction |
| AssemblyAI | Some free credits | ~$0.65/hr audio (pennies for push-to-talk) |
| ElevenLabs | 10k chars/mo (blocked via proxy) | $5/mo starter |
| macOS System TTS | Unlimited, free | — |

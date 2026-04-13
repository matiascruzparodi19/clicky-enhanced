# Clicky Enhanced

An enhanced fork of [Clicky](https://github.com/farzaa/clicky) — the AI companion that lives in your macOS menu bar. It can see your screen, talk to you, and point at things.

![Clicky — an ai buddy that lives on your mac](clicky-demo.gif)

## What's New in This Fork

- **Gemini 2.5 Flash** — budget-friendly AI model option (free tier, 10-50x cheaper than Claude)
- **Claude Haiku** — lightweight Claude option for fast, cheap responses
- **Four-model picker** — switch between Haiku, Sonnet, Opus, and Flash from the menu bar panel
- **Cloudflare Worker /gemini route** — proxies to Google Gemini API alongside existing Claude routes
- **macOS system TTS fallback** — Clicky always speaks, even when ElevenLabs is unavailable
- **Specific error messages** — tells you which service failed (Gemini, Claude, or ElevenLabs)
- **Draggable panel** — move the control panel anywhere, it remembers position between opens
- **Cmd+Shift+C shortcut** — toggle the panel from anywhere without needing the menu bar icon
- **Panel auto-opens on launch** — easier access without hunting for the icon

## Get Started with Claude Code

The fastest way to set this up is with [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Once you have Claude Code running, paste this:

```
Hi Claude.

I just forked the clicky-enhanced repo. Read the CLAUDE.md and LEARNINGS.md.

I want to get Clicky running locally on my Mac. Help me set up everything — the
Cloudflare Worker with my own API keys (I want to use Gemini Flash), the
LocalConfig.swift with my proxy URL, and getting it building in Xcode. Walk me
through it step by step.
```

That's it. Claude will read the docs, set up your Worker, configure the proxy URLs, and walk you through the Xcode build.

## Manual Setup

### Prerequisites

- macOS 14.2+ (for ScreenCaptureKit)
- Xcode 15+
- Node.js 18+ (for the Cloudflare Worker)
- A [Cloudflare](https://cloudflare.com) account (free tier works)
- API keys for the services you want to use:

| Service | Required? | What It Does | Get a Key |
|---------|-----------|-------------|-----------|
| [Gemini](https://aistudio.google.com/apikey) | Pick at least one AI | Vision + chat (free tier) | aistudio.google.com |
| [Anthropic](https://console.anthropic.com) | Pick at least one AI | Vision + chat (pay-as-you-go) | console.anthropic.com |
| [AssemblyAI](https://www.assemblyai.com) | Yes | Voice transcription | assemblyai.com |
| [ElevenLabs](https://elevenlabs.io) | Optional | Natural-sounding TTS | elevenlabs.io |

ElevenLabs is optional — without it, Clicky falls back to the built-in macOS voice (free, works offline).

### 1. Deploy the Cloudflare Worker

The Worker is a proxy that holds your API keys so they never ship in the app.

```bash
cd worker
npm install
npx wrangler login
```

Add your API keys (each prompts you to paste):

```bash
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npx wrangler secret put GEMINI_API_KEY
```

Skip any you don't have — the app works with whatever services you configure.

Deploy:

```bash
npx wrangler deploy
```

Copy the URL it prints (e.g. `https://clicky-proxy.your-subdomain.workers.dev`).

### 2. Configure your Worker URL

```bash
cp leanring-buddy/LocalConfig.example.swift leanring-buddy/LocalConfig.swift
```

Open `leanring-buddy/LocalConfig.swift` and paste your Worker URL:

```swift
static let workerBaseURL = "https://clicky-proxy.your-subdomain.workers.dev"
```

This file is gitignored — your URL stays local.

### 3. Build and run

```bash
open leanring-buddy.xcodeproj
```

In Xcode:
1. Select the **leanring-buddy** scheme
2. Set your signing team (any free Apple ID works) under Signing & Capabilities
3. **Cmd+R** to build and run

The app appears in your **menu bar** (not the dock). Click the icon to open the panel, grant permissions, select your model, and push-to-talk with **Ctrl+Option**.

**Important:** Don't run `xcodebuild` from the terminal — it invalidates macOS TCC permissions.

### Permissions needed

- **Microphone** — push-to-talk voice capture
- **Accessibility** — global Ctrl+Option keyboard shortcut
- **Screen Recording** — screenshots sent to the AI

## Architecture

Full technical breakdown in `CLAUDE.md`. Short version:

Menu bar app with two transparent `NSPanel` windows — one for the control panel, one for the cursor overlay. Push-to-talk streams audio to AssemblyAI, sends transcript + screenshots to Claude or Gemini via SSE, speaks the response through ElevenLabs or macOS TTS. The AI can embed `[POINT:x,y:label:screenN]` tags to make the cursor fly to UI elements. Everything proxied through a Cloudflare Worker.

For a visual explainer of the full architecture, open `clicky-architecture.html` in your browser.

## Project Structure

```
leanring-buddy/                # Swift source
  CompanionManager.swift         # Central state machine + AI dispatch
  CompanionPanelView.swift       # Menu bar panel UI + model picker
  ClaudeAPI.swift                # Claude streaming client
  GeminiAPI.swift                # Gemini streaming client
  ElevenLabsTTSClient.swift      # Text-to-speech playback
  MenuBarPanelManager.swift      # Menu bar icon + panel lifecycle
  OverlayWindow.swift            # Blue cursor overlay + pointing
  AssemblyAI*.swift              # Real-time transcription
  BuddyDictation*.swift          # Push-to-talk pipeline
  LocalConfig.swift              # Your Worker URL (gitignored)
  LocalConfig.example.swift      # Template for LocalConfig.swift
worker/                        # Cloudflare Worker proxy
  src/index.ts                   # /chat, /gemini, /tts, /transcribe-token
CLAUDE.md                      # Full architecture doc
LEARNINGS.md                   # Setup tips + model integration guide
clicky-architecture.html       # Visual architecture explainer
```

## Credits

Based on [Clicky](https://github.com/farzaa/clicky) by [@farzatv](https://x.com/farzatv).

//
//  LocalConfig.example.swift
//  leanring-buddy
//
//  Copy this file to LocalConfig.swift and fill in your Cloudflare Worker URL.
//  LocalConfig.swift is gitignored — your secrets stay local.
//

import Foundation

enum LocalConfig {
    /// Base URL for your deployed Cloudflare Worker proxy.
    /// Run `npx wrangler deploy` in the worker/ directory to get this URL.
    static let workerBaseURL = "https://your-worker-name.your-subdomain.workers.dev"
}

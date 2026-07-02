//
//  OpenCodeConfigGenerator.swift
//  Motive
//

import Foundation

/// Generates the opencode.json configuration file with explicit dependency injection.
@MainActor
struct OpenCodeConfigGenerator {

    struct Inputs {
        let providerName: String
        let provider: ConfigManager.Provider
        let baseURL: String
        let modelName: String
        let apiKey: String
        let workspaceDirectory: URL
        let skillsSystemEnabled: Bool
        let compactionEnabled: Bool
        let memoryEnabled: Bool
        let agents: [AgentConfig]
        let defaultAgent: String
    }

    struct AgentConfig {
        let name: String
        let description: String
        let prompt: String
        let mode: String
        let permission: [String: Any]
    }

    /// Generate opencode.json configuration and write skill files.
    /// Returns the (configPath, configDir) tuple.
    @discardableResult
    static func generate(
        inputs: Inputs,
        permissionPolicy: ToolPermissionPolicy,
        skillRegistry: SkillRegistry,
        skillManager: SkillManager,
        promptBuilder: SystemPromptBuilder
    ) -> (configPath: String, configDir: String) {
        // Config now goes to workspace directory (~/.motive/config/)
        let configDir = inputs.workspaceDirectory.appendingPathComponent("config")
        let configPath = configDir.appendingPathComponent("opencode.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Determine provider name for OpenCode
        let providerName = inputs.providerName
        let baseURLValue = inputs.baseURL

        // System prompt - build using SystemPromptBuilder
        let systemPrompt = promptBuilder.build()

        // Build skill permissions using WHITELIST approach:
        // deny all, then explicitly allow enabled skills.
        // Skills are synced to $OPENCODE_CONFIG_DIR/skills/<n>/SKILL.md so
        // OpenCode's native `skill` tool discovers them; permissions gate access.
        var skillPermissions = ["*": "deny"]
        for entry in skillRegistry.entries where skillRegistry.isSkillEnabled(entry) {
            skillPermissions[entry.name] = "allow"
            Log.config(" Skill '\(entry.name)' is enabled -> allow")
        }

        var permissionRules = permissionPolicy.toOpenCodePermissionRules()
        permissionRules["skill"] = skillPermissions

        // Build agent configurations
        var agentDict: [String: Any] = [:]
        if inputs.agents.isEmpty {
            // Fallback: single agent
            agentDict["agent"] = [
                "description": "Default agent",
                "prompt": systemPrompt,
                "mode": "primary",
                "permission": permissionRules
            ] as [String: Any]
        } else {
            for agent in inputs.agents {
                agentDict[agent.name] = [
                    "description": agent.description,
                    "prompt": agent.prompt,
                    "mode": agent.mode,
                    "permission": agent.permission
                ] as [String: Any]
            }
        }

        var config: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "default_agent": inputs.defaultAgent,
            "enabled_providers": [providerName],
            // Permission rules from ToolPermissionPolicy (native enforcement)
            "permission": permissionRules,
            "agent": agentDict
        ]

        // Compaction configuration
        if inputs.compactionEnabled {
            config["compaction"] = [
                "auto": true,
                "prune": true
            ]
        }

        // Memory plugin configuration — inject if the deployed plugin entry exists
        if inputs.memoryEnabled {
            let pluginEntry = inputs.workspaceDirectory
                .appendingPathComponent("plugins/motive-memory/src/index.ts")
            let pluginPath = pluginEntry.path
            if FileManager.default.fileExists(atPath: pluginPath) {
                config["plugin"] = ["file://\(pluginPath)"]
                Log.config("Memory plugin enabled from \(pluginPath)")
            } else {
                Log.config("Memory enabled but plugin not found at \(pluginPath) — skipping plugin config")
            }
        } else {
            Log.config("Memory disabled — skipping memory plugin injection")
        }

        // Native instructions: point to persona files so OpenCode auto-injects them
        var instructions: [String] = []
        let personaFiles = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "MEMORY.md"]
        for file in personaFiles {
            let path = inputs.workspaceDirectory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: path.path) {
                instructions.append(path.path)
            }
        }
        if !instructions.isEmpty {
            config["instructions"] = instructions
        }

        // Skills paths configuration
        // NOTE: "skills" top-level key requires OpenCode >= v1.1.45.
        // For older versions, skills are already discovered via
        // syncSkillsToDirectory() writing to $OPENCODE_CONFIG_DIR/skills/.
        // Only emit this key when the binary is new enough.
        // TODO: enable once Motive ships with OpenCode >= 1.1.45
        // if inputs.skillsSystemEnabled {
        //     let skillsPath = inputs.workspaceDirectory.appendingPathComponent("skills").path
        //     config["skills"] = ["paths": [skillsPath]]
        // }

        // Add provider options.
        // Keep standard providers untouched (models.dev definitions stay authoritative).
        switch inputs.provider {
        case .lmstudio:
            let lmBaseURL = baseURLValue.isEmpty ? "http://127.0.0.1:1234/v1" : baseURLValue
            // Use the user-specified model or fall back to "default" which LM Studio
            // maps to whatever model is currently loaded.
            let lmModelID = inputs.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            var lmOptions: [String: Any] = ["baseURL": lmBaseURL]
            let lmAPIKey = inputs.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !lmAPIKey.isEmpty {
                lmOptions["apiKey"] = lmAPIKey
                Log.config(" LM Studio API key configured (required by server auth)")
            }

            if lmModelID.isEmpty {
                // No model specified — omit models dict so LM Studio uses whichever is loaded.
                // Do NOT send "default" as model ID; it confuses some LM Studio versions.
                config["provider"] = [
                    "lmstudio": [
                        "options": lmOptions,
                    ] as [String: Any],
                ]
                Log.config(" Provider 'lmstudio' configured with baseURL: \(lmBaseURL) (model auto-selected by server)")
            } else {
                config["provider"] = [
                    "lmstudio": [
                        "models": [
                            lmModelID: [
                                "name": lmModelID,
                                "tool_call": true,
                            ] as [String: Any],
                        ],
                        "options": lmOptions,
                    ] as [String: Any],
                ]
                Log.config(" Provider 'lmstudio' configured with baseURL: \(lmBaseURL), model: \(lmModelID)")
            }

        case .ollama:
            let ollamaURL = baseURLValue.isEmpty ? "http://localhost:11434/v1" : baseURLValue
            let modelID = inputs.modelName.isEmpty ? "llama3" : inputs.modelName
            config["provider"] = [
                "ollama": [
                    "npm": "@ai-sdk/openai-compatible",
                    "name": "Ollama",
                    "models": [
                        modelID: [
                            "name": modelID,
                            "tool_call": true,
                        ] as [String: Any],
                    ],
                    "options": [
                        "baseURL": ollamaURL,
                    ],
                ] as [String: Any],
            ]
            Log.config(" Provider 'ollama' configured with baseURL: \(ollamaURL), model: \(modelID)")

        default:
            let modelIDForProvider = inputs.modelName.trimmingCharacters(in: .whitespacesAndNewlines)

            if !baseURLValue.isEmpty {
                // Build options dict with baseURL, and include apiKey if set.
                // IMPORTANT: For OpenAI-compatible endpoints (e.g. LM Studio via openai provider)
                // that require server authentication, the API key must be in provider options AND
                // as the OPENAI_API_KEY env var. Some opencode provider adapters only read from
                // the config options dict, not the environment.
                var customOptions: [String: Any] = ["baseURL": baseURLValue]
                let customAPIKey = inputs.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !customAPIKey.isEmpty {
                    customOptions["apiKey"] = customAPIKey
                    Log.config(" Provider '\(providerName)' custom baseURL API key configured in options")
                }

                if !modelIDForProvider.isEmpty {
                    config["provider"] = [
                        providerName: [
                            "models": [
                                modelIDForProvider: [
                                    "name": modelIDForProvider,
                                    "tool_call": true,
                                ] as [String: Any],
                            ],
                            "options": customOptions,
                        ] as [String: Any],
                    ]
                    Log.config(" Provider '\(providerName)' configured with baseURL: \(baseURLValue), model: \(modelIDForProvider)")
                } else {
                    config["provider"] = [
                        providerName: [
                            "options": customOptions,
                        ] as [String: Any],
                    ]
                    Log.config(" Provider '\(providerName)' configured with baseURL: \(baseURLValue) (no model override)")
                }
            } else if !modelIDForProvider.isEmpty {
                config["provider"] = [
                    providerName: [
                        "models": [
                            modelIDForProvider: [
                                "name": modelIDForProvider,
                                "tool_call": true,
                            ] as [String: Any],
                        ],
                    ] as [String: Any],
                ]
                Log.config(" Provider '\(providerName)' configured with model override: \(modelIDForProvider)")
            }
        }

        // Merge MCP tools from skills (if enabled) — only skill-provided MCP tools, not built-in
        if inputs.skillsSystemEnabled {
            let skillMcp = skillRegistry.buildMcpConfigEntries()
            if !skillMcp.isEmpty {
                var existing = config["mcp"] as? [String: Any] ?? [:]
                for (key, value) in skillMcp where existing[key] == nil {
                    existing[key] = value
                }
                config["mcp"] = existing
            }
        }

        // Write config
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: configPath)
            Log.config(" Generated OpenCode config at \(configPath.path)")
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Log.config(" Config content: \(jsonString.prefix(500))")
            }

            // Write capability/MCP SKILL.md files (browser-automation etc.)
            skillManager.writeSkillFiles(to: inputs.workspaceDirectory)

            // Sync all enabled bundled/user skills so OpenCode's native `skill` tool discovers them.
            // This is the SINGLE mechanism for skill discovery — no system prompt listing needed.
            let skillsDir = inputs.workspaceDirectory.appendingPathComponent("skills")
            skillRegistry.syncSkillsToDirectory(skillsDir)
        } catch {
            Log.config(" ERROR - Failed to write OpenCode config: \(error)")
        }

        return (configPath: configPath.path, configDir: inputs.workspaceDirectory.path)
    }
}

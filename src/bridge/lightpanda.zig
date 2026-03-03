const std = @import("std");

pub const BridgeError = error{
    UnsupportedEngine,
    UnsupportedProvider,
};

pub const BrowserCompletion = struct {
    ok: bool,
    engine: []const u8,
    provider: []const u8,
    model: []const u8,
    status: []const u8,
    authMode: []const u8,
    guestBypassSupported: bool,
    popupBypassAction: []const u8,
    message: []const u8,
};

pub fn normalizeEngine(raw: []const u8) BridgeError![]const u8 {
    const engine = std.mem.trim(u8, raw, " \t\r\n");
    if (engine.len == 0) return "lightpanda";
    if (std.ascii.eqlIgnoreCase(engine, "lightpanda")) return "lightpanda";
    if (std.ascii.eqlIgnoreCase(engine, "playwright")) return error.UnsupportedEngine;
    if (std.ascii.eqlIgnoreCase(engine, "puppeteer")) return error.UnsupportedEngine;
    return error.UnsupportedEngine;
}

pub fn normalizeProvider(raw: []const u8) BridgeError![]const u8 {
    const provider = std.mem.trim(u8, raw, " \t\r\n");
    if (provider.len == 0) return "chatgpt";
    if (std.ascii.eqlIgnoreCase(provider, "openai") or std.ascii.eqlIgnoreCase(provider, "openai-chatgpt") or std.ascii.eqlIgnoreCase(provider, "chatgpt-web") or std.ascii.eqlIgnoreCase(provider, "chatgpt.com")) return "chatgpt";
    if (std.ascii.eqlIgnoreCase(provider, "openai-codex") or std.ascii.eqlIgnoreCase(provider, "codex-cli") or std.ascii.eqlIgnoreCase(provider, "openai-codex-cli")) return "codex";
    if (std.ascii.eqlIgnoreCase(provider, "anthropic") or std.ascii.eqlIgnoreCase(provider, "claude-cli") or std.ascii.eqlIgnoreCase(provider, "claude-code") or std.ascii.eqlIgnoreCase(provider, "claude-desktop")) return "claude";
    if (std.ascii.eqlIgnoreCase(provider, "google") or std.ascii.eqlIgnoreCase(provider, "google-gemini") or std.ascii.eqlIgnoreCase(provider, "google-gemini-cli") or std.ascii.eqlIgnoreCase(provider, "gemini-cli")) return "gemini";
    if (std.ascii.eqlIgnoreCase(provider, "qwen-portal") or std.ascii.eqlIgnoreCase(provider, "qwen-cli") or std.ascii.eqlIgnoreCase(provider, "qwen-chat") or std.ascii.eqlIgnoreCase(provider, "qwen35") or std.ascii.eqlIgnoreCase(provider, "qwen3.5") or std.ascii.eqlIgnoreCase(provider, "qwen-3.5") or std.ascii.eqlIgnoreCase(provider, "copaw") or std.ascii.eqlIgnoreCase(provider, "qwen-copaw") or std.ascii.eqlIgnoreCase(provider, "qwen-agent")) return "qwen";
    if (std.ascii.eqlIgnoreCase(provider, "minimax-portal") or std.ascii.eqlIgnoreCase(provider, "minimax-cli")) return "minimax";
    if (std.ascii.eqlIgnoreCase(provider, "kimi-code") or std.ascii.eqlIgnoreCase(provider, "kimi-coding") or std.ascii.eqlIgnoreCase(provider, "kimi-for-coding")) return "kimi";
    if (std.ascii.eqlIgnoreCase(provider, "opencode-zen") or std.ascii.eqlIgnoreCase(provider, "opencode-ai") or std.ascii.eqlIgnoreCase(provider, "opencode-go") or std.ascii.eqlIgnoreCase(provider, "opencode_free") or std.ascii.eqlIgnoreCase(provider, "opencodefree")) return "opencode";
    if (std.ascii.eqlIgnoreCase(provider, "zhipu") or std.ascii.eqlIgnoreCase(provider, "zhipu-ai") or std.ascii.eqlIgnoreCase(provider, "bigmodel") or std.ascii.eqlIgnoreCase(provider, "bigmodel-cn") or std.ascii.eqlIgnoreCase(provider, "zhipuai-coding") or std.ascii.eqlIgnoreCase(provider, "zhipu-coding")) return "zhipuai";
    if (std.ascii.eqlIgnoreCase(provider, "z.ai") or std.ascii.eqlIgnoreCase(provider, "z-ai") or std.ascii.eqlIgnoreCase(provider, "zaiweb") or std.ascii.eqlIgnoreCase(provider, "zai-web") or std.ascii.eqlIgnoreCase(provider, "glm") or std.ascii.eqlIgnoreCase(provider, "glm5") or std.ascii.eqlIgnoreCase(provider, "glm-5")) return "zai";
    if (std.ascii.eqlIgnoreCase(provider, "inception-labs") or std.ascii.eqlIgnoreCase(provider, "inceptionlabs") or std.ascii.eqlIgnoreCase(provider, "mercury") or std.ascii.eqlIgnoreCase(provider, "mercury2") or std.ascii.eqlIgnoreCase(provider, "mercury-2")) return "inception";
    if (std.ascii.eqlIgnoreCase(provider, "chatgpt") or std.ascii.eqlIgnoreCase(provider, "codex") or std.ascii.eqlIgnoreCase(provider, "claude") or std.ascii.eqlIgnoreCase(provider, "gemini") or std.ascii.eqlIgnoreCase(provider, "qwen") or std.ascii.eqlIgnoreCase(provider, "minimax") or std.ascii.eqlIgnoreCase(provider, "kimi") or std.ascii.eqlIgnoreCase(provider, "openrouter") or std.ascii.eqlIgnoreCase(provider, "opencode") or std.ascii.eqlIgnoreCase(provider, "zhipuai") or std.ascii.eqlIgnoreCase(provider, "zai") or std.ascii.eqlIgnoreCase(provider, "inception")) return provider;
    return error.UnsupportedProvider;
}

pub fn defaultModelForProvider(provider_raw: []const u8) []const u8 {
    const provider = normalizeProvider(provider_raw) catch "chatgpt";
    if (std.ascii.eqlIgnoreCase(provider, "codex")) return "gpt-5.2";
    if (std.ascii.eqlIgnoreCase(provider, "claude")) return "claude-opus-4";
    if (std.ascii.eqlIgnoreCase(provider, "gemini")) return "gemini-2.5-pro";
    if (std.ascii.eqlIgnoreCase(provider, "qwen")) return "qwen-max";
    if (std.ascii.eqlIgnoreCase(provider, "minimax")) return "minimax-m2.5";
    if (std.ascii.eqlIgnoreCase(provider, "kimi")) return "kimi-k2.5";
    if (std.ascii.eqlIgnoreCase(provider, "openrouter")) return "openrouter/auto";
    if (std.ascii.eqlIgnoreCase(provider, "opencode")) return "opencode/default";
    if (std.ascii.eqlIgnoreCase(provider, "zhipuai")) return "glm-4.6";
    if (std.ascii.eqlIgnoreCase(provider, "zai")) return "glm-5";
    if (std.ascii.eqlIgnoreCase(provider, "inception")) return "mercury-2";
    return "gpt-5.2";
}

pub fn supportsGuestBypass(provider_raw: []const u8) bool {
    const provider = normalizeProvider(provider_raw) catch return false;
    return std.ascii.eqlIgnoreCase(provider, "qwen") or
        std.ascii.eqlIgnoreCase(provider, "zai") or
        std.ascii.eqlIgnoreCase(provider, "inception");
}

pub fn popupBypassAction(provider_raw: []const u8) []const u8 {
    return if (supportsGuestBypass(provider_raw)) "stay_logged_out" else "not_applicable";
}

fn normalizeAuthMode(provider: []const u8, raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) {
        return if (supportsGuestBypass(provider)) "guest_or_code" else "device_code";
    }
    if (std.ascii.eqlIgnoreCase(trimmed, "guest") or
        std.ascii.eqlIgnoreCase(trimmed, "guest_bypass") or
        std.ascii.eqlIgnoreCase(trimmed, "stay_logged_out") or
        std.ascii.eqlIgnoreCase(trimmed, "stay-logged-out") or
        std.ascii.eqlIgnoreCase(trimmed, "continue_as_guest"))
    {
        return "guest";
    }
    if (std.ascii.eqlIgnoreCase(trimmed, "device_code") or
        std.ascii.eqlIgnoreCase(trimmed, "oauth_code") or
        std.ascii.eqlIgnoreCase(trimmed, "code"))
    {
        return "device_code";
    }
    return trimmed;
}

pub fn complete(engine_raw: []const u8, provider_raw: []const u8, model_raw: []const u8, auth_mode_raw: []const u8) BridgeError!BrowserCompletion {
    const engine = try normalizeEngine(engine_raw);
    const provider = try normalizeProvider(provider_raw);
    const model_trimmed = std.mem.trim(u8, model_raw, " \t\r\n");
    const model = if (model_trimmed.len > 0) model_trimmed else defaultModelForProvider(provider);
    const guest_bypass = supportsGuestBypass(provider);
    const auth_mode = normalizeAuthMode(provider, auth_mode_raw);
    const message = if (guest_bypass)
        "Lightpanda bridge ready; if popup appears choose 'Stay logged out' and continue as guest."
    else
        "Lightpanda browser bridge ready";
    return .{
        .ok = true,
        .engine = engine,
        .provider = provider,
        .model = model,
        .status = "completed",
        .authMode = auth_mode,
        .guestBypassSupported = guest_bypass,
        .popupBypassAction = popupBypassAction(provider),
        .message = message,
    };
}

test "lightpanda is the only browser provider" {
    try std.testing.expectError(error.UnsupportedEngine, normalizeEngine("playwright"));
    try std.testing.expectError(error.UnsupportedEngine, normalizeEngine("puppeteer"));
    const engine = try normalizeEngine("lightpanda");
    try std.testing.expect(std.mem.eql(u8, engine, "lightpanda"));
}

test "provider aliases normalize to canonical bridge providers" {
    try std.testing.expect(std.mem.eql(u8, try normalizeProvider("copaw"), "qwen"));
    try std.testing.expect(std.mem.eql(u8, try normalizeProvider("glm-5"), "zai"));
    try std.testing.expect(std.mem.eql(u8, try normalizeProvider("mercury2"), "inception"));
}

test "qwen profile exposes guest bypass metadata" {
    const completion = try complete("lightpanda", "qwen", "qwen3.5-plus", "");
    try std.testing.expect(std.mem.eql(u8, completion.engine, "lightpanda"));
    try std.testing.expect(std.mem.eql(u8, completion.provider, "qwen"));
    try std.testing.expect(std.mem.eql(u8, completion.authMode, "guest_or_code"));
    try std.testing.expect(completion.guestBypassSupported);
    try std.testing.expect(std.mem.eql(u8, completion.popupBypassAction, "stay_logged_out"));
}

test "chatgpt profile keeps code auth mode by default" {
    const completion = try complete("lightpanda", "chatgpt", "", "");
    try std.testing.expect(std.mem.eql(u8, completion.provider, "chatgpt"));
    try std.testing.expect(std.mem.eql(u8, completion.model, "gpt-5.2"));
    try std.testing.expect(std.mem.eql(u8, completion.authMode, "device_code"));
    try std.testing.expect(!completion.guestBypassSupported);
}

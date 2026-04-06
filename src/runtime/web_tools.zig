const std = @import("std");
const builtin = @import("builtin");
const time_util = @import("../util/time.zig");

pub const default_search_endpoint = "https://html.duckduckgo.com/html/";
pub const default_timeout_ms: u32 = 15_000;
pub const default_extract_max_chars: usize = 5_000;
pub const max_response_bytes: usize = 512 * 1024;

pub const SearchItem = struct {
    url: []u8,
    title: []u8,
    description: []u8,

    pub fn deinit(self: *SearchItem, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.title);
        allocator.free(self.description);
    }
};

pub const SearchData = struct {
    web: []SearchItem,
};

pub const SearchResult = struct {
    provider: []u8,
    requestUrl: []u8,
    latencyMs: i64,
    count: usize,
    data: SearchData,

    pub fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.requestUrl);
        for (self.data.web) |*item| item.deinit(allocator);
        allocator.free(self.data.web);
    }
};

pub const ExtractPage = struct {
    url: []u8,
    title: []u8,
    content: []u8,
    @"error": []u8,
    statusCode: u16,
    contentType: []u8,

    pub fn deinit(self: *ExtractPage, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.title);
        allocator.free(self.content);
        allocator.free(self.@"error");
        allocator.free(self.contentType);
    }
};

pub const ExtractResult = struct {
    count: usize,
    results: []ExtractPage,

    pub fn deinit(self: *ExtractResult, allocator: std.mem.Allocator) void {
        for (self.results) |*item| item.deinit(allocator);
        allocator.free(self.results);
    }
};

const HttpFetch = struct {
    body: []u8,
    statusCode: u16,
    latencyMs: i64,

    fn deinit(self: *HttpFetch, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

const ExtractedContent = struct {
    title: []u8,
    content: []u8,
    contentType: []u8,

    fn deinit(self: *ExtractedContent, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.content);
        allocator.free(self.contentType);
    }
};

pub fn search(
    allocator: std.mem.Allocator,
    query: []const u8,
    limit_raw: u32,
    endpoint_raw: []const u8,
    timeout_ms: u32,
) !SearchResult {
    const limit: usize = @max(@as(usize, 1), @as(usize, @intCast(if (limit_raw == 0) 5 else limit_raw)));
    const endpoint = std.mem.trim(u8, endpoint_raw, " \t\r\n");
    const search_endpoint = if (endpoint.len == 0) default_search_endpoint else endpoint;

    const request_url = try buildSearchUrlAlloc(allocator, search_endpoint, query, limit);
    errdefer allocator.free(request_url);

    var fetch = try fetchUrlAlloc(allocator, request_url, timeout_ms, "text/html, application/json, text/plain");
    defer fetch.deinit(allocator);

    const provider_name = try inferSearchProviderAlloc(allocator, search_endpoint);
    errdefer allocator.free(provider_name);

    const items = if (looksLikeJson(fetch.body))
        try parseSearchResultsJsonAlloc(allocator, fetch.body, limit)
    else
        try parseSearchResultsHtmlAlloc(allocator, fetch.body, limit);
    errdefer {
        for (items) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    return .{
        .provider = provider_name,
        .requestUrl = request_url,
        .latencyMs = fetch.latencyMs,
        .count = items.len,
        .data = .{ .web = items },
    };
}

pub fn extract(
    allocator: std.mem.Allocator,
    urls: []const []const u8,
    max_chars: usize,
    timeout_ms: u32,
) !ExtractResult {
    var pages: std.ArrayList(ExtractPage) = .empty;
    errdefer {
        for (pages.items) |*item| item.deinit(allocator);
        pages.deinit(allocator);
    }

    for (urls) |url_raw| {
        const url = std.mem.trim(u8, url_raw, " \t\r\n");
        if (url.len == 0) {
            try pages.append(allocator, .{
                .url = try allocator.dupe(u8, ""),
                .title = try allocator.dupe(u8, ""),
                .content = try allocator.dupe(u8, ""),
                .@"error" = try allocator.dupe(u8, "missing url"),
                .statusCode = 0,
                .contentType = try allocator.dupe(u8, "missing"),
            });
            continue;
        }

        var fetch = fetchUrlAlloc(allocator, url, timeout_ms, "text/html, application/json, text/plain") catch |err| {
            try pages.append(allocator, .{
                .url = try allocator.dupe(u8, url),
                .title = try allocator.dupe(u8, ""),
                .content = try allocator.dupe(u8, ""),
                .@"error" = try std.fmt.allocPrint(allocator, "web fetch failed: {s}", .{@errorName(err)}),
                .statusCode = 0,
                .contentType = try allocator.dupe(u8, "error"),
            });
            continue;
        };
        defer fetch.deinit(allocator);

        if (fetch.statusCode < 200 or fetch.statusCode >= 300) {
            try pages.append(allocator, .{
                .url = try allocator.dupe(u8, url),
                .title = try allocator.dupe(u8, ""),
                .content = try allocator.dupe(u8, trimAndTruncate(fetch.body, max_chars)),
                .@"error" = try std.fmt.allocPrint(allocator, "http status {d}", .{fetch.statusCode}),
                .statusCode = fetch.statusCode,
                .contentType = try allocator.dupe(u8, inferContentType(fetch.body)),
            });
            continue;
        }

        var extracted = try extractContentAlloc(allocator, url, fetch.body, max_chars);
        defer extracted.deinit(allocator);

        try pages.append(allocator, .{
            .url = try allocator.dupe(u8, url),
            .title = try allocator.dupe(u8, extracted.title),
            .content = try allocator.dupe(u8, extracted.content),
            .@"error" = try allocator.dupe(u8, ""),
            .statusCode = fetch.statusCode,
            .contentType = try allocator.dupe(u8, extracted.contentType),
        });
    }

    return .{
        .count = pages.items.len,
        .results = try pages.toOwnedSlice(allocator),
    };
}

fn inferSearchProviderAlloc(allocator: std.mem.Allocator, endpoint: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, endpoint, "duckduckgo") != null) return allocator.dupe(u8, "duckduckgo-html");
    return allocator.dupe(u8, "http-search");
}

fn buildSearchUrlAlloc(
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    query: []const u8,
    limit: usize,
) ![]u8 {
    const encoded_query = try urlEncodeAlloc(allocator, query);
    defer allocator.free(encoded_query);
    const limit_text = try std.fmt.allocPrint(allocator, "{d}", .{limit});
    defer allocator.free(limit_text);

    const with_query = if (std.mem.indexOf(u8, endpoint, "{query}") != null)
        try std.mem.replaceOwned(u8, allocator, endpoint, "{query}", encoded_query)
    else
        try allocator.dupe(u8, endpoint);
    defer allocator.free(with_query);

    const with_limit = if (std.mem.indexOf(u8, with_query, "{limit}") != null)
        try std.mem.replaceOwned(u8, allocator, with_query, "{limit}", limit_text)
    else
        try allocator.dupe(u8, with_query);
    defer allocator.free(with_limit);

    if (std.mem.indexOf(u8, with_limit, "{query}") == null and std.mem.indexOf(u8, with_limit, "q=") == null) {
        return std.fmt.allocPrint(allocator, "{s}{s}q={s}&limit={s}", .{
            with_limit,
            if (std.mem.indexOfScalar(u8, with_limit, '?') == null) "?" else if (std.mem.endsWith(u8, with_limit, "?") or std.mem.endsWith(u8, with_limit, "&")) "" else "&",
            encoded_query,
            limit_text,
        });
    }
    return allocator.dupe(u8, with_limit);
}

fn fetchUrlAlloc(
    allocator: std.mem.Allocator,
    url: []const u8,
    timeout_ms: u32,
    accept: []const u8,
) !HttpFetch {
    _ = timeout_ms;
    if (builtin.os.tag == .freestanding or builtin.os.tag == .wasi) return error.WebFetchUnsupported;

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = std.Io.Threaded.global_single_threaded.io(),
    };
    defer client.deinit();

    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    var headers = [_]std.http.Header{
        .{ .name = "accept", .value = accept },
        .{ .name = "user-agent", .value = "openclaw-zig-web-tools/0.1" },
    };

    const started_ms = time_util.nowMs();
    const fetch_result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .keep_alive = false,
        .extra_headers = headers[0..],
        .response_writer = &response_body.writer,
    });

    return .{
        .body = try response_body.toOwnedSlice(),
        .statusCode = @as(u16, @intCast(@intFromEnum(fetch_result.status))),
        .latencyMs = time_util.nowMs() - started_ms,
    };
}

fn parseSearchResultsJsonAlloc(
    allocator: std.mem.Allocator,
    body: []const u8,
    limit: usize,
) ![]SearchItem {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        return allocator.alloc(SearchItem, 0);
    };
    defer parsed.deinit();

    var list_ptr: ?*const std.json.Array = null;

    switch (parsed.value) {
        .array => |*arr| list_ptr = arr,
        .object => |obj| {
            if (obj.get("results")) |value| {
                if (value == .array) list_ptr = &value.array;
            }
            if (list_ptr == null) {
                if (obj.get("items")) |value| {
                    if (value == .array) list_ptr = &value.array;
                }
            }
            if (list_ptr == null) {
                if (obj.get("data")) |value| {
                    if (value == .object) {
                        if (value.object.get("web")) |web_value| {
                            if (web_value == .array) list_ptr = &web_value.array;
                        }
                    }
                }
            }
        },
        else => {},
    }

    const list = list_ptr orelse return allocator.alloc(SearchItem, 0);
    var out: std.ArrayList(SearchItem) = .empty;
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit(allocator);
    }

    for (list.items) |entry| {
        if (out.items.len >= limit) break;
        if (entry != .object) continue;

        const url = jsonObjectString(entry.object, &.{ "url", "href", "link" }) orelse continue;
        const title = jsonObjectString(entry.object, &.{ "title", "name" }) orelse url;
        const description = jsonObjectString(entry.object, &.{ "description", "snippet", "text", "content" }) orelse "";
        try out.append(allocator, .{
            .url = try allocator.dupe(u8, url),
            .title = try allocator.dupe(u8, title),
            .description = try allocator.dupe(u8, description),
        });
    }

    return out.toOwnedSlice(allocator);
}

fn parseSearchResultsHtmlAlloc(
    allocator: std.mem.Allocator,
    body: []const u8,
    limit: usize,
) ![]SearchItem {
    var out: std.ArrayList(SearchItem) = .empty;
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit(allocator);
    }

    var cursor: usize = 0;
    while (cursor < body.len and out.items.len < limit) {
        const anchor_idx = findNextResultAnchor(body, cursor) orelse break;
        const href = extractHrefAt(body, anchor_idx) orelse {
            cursor = anchor_idx + 2;
            continue;
        };
        const anchor_close = std.mem.indexOfPos(u8, body, anchor_idx, ">") orelse break;
        const anchor_end = std.mem.indexOfPos(u8, body, anchor_close + 1, "</a>") orelse break;

        const title_raw = body[anchor_close + 1 .. anchor_end];
        const title = try cleanHtmlSnippetAlloc(allocator, title_raw, 240);
        errdefer allocator.free(title);
        const url = try decodeHrefAlloc(allocator, href);
        errdefer allocator.free(url);

        const snippet_window_end = @min(body.len, anchor_end + 1200);
        const description_raw = findNearbySnippet(body[anchor_end..snippet_window_end]);
        const description = try cleanHtmlSnippetAlloc(allocator, description_raw, 320);
        errdefer allocator.free(description);

        try out.append(allocator, .{
            .url = url,
            .title = title,
            .description = description,
        });
        cursor = anchor_end + 4;
    }

    return out.toOwnedSlice(allocator);
}

fn extractContentAlloc(
    allocator: std.mem.Allocator,
    url: []const u8,
    body: []const u8,
    max_chars: usize,
) !ExtractedContent {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (looksLikeHtml(trimmed)) {
        const maybe_title = try extractTitleAlloc(allocator, trimmed);
        defer allocator.free(maybe_title);
        const content = try htmlToTextAlloc(allocator, trimmed, max_chars);
        errdefer allocator.free(content);
        return .{
            .title = if (maybe_title.len > 0) try allocator.dupe(u8, maybe_title) else try allocator.dupe(u8, url),
            .content = content,
            .contentType = try allocator.dupe(u8, "text/html"),
        };
    }

    if (looksLikeJson(trimmed)) {
        return .{
            .title = try allocator.dupe(u8, url),
            .content = try allocator.dupe(u8, trimAndTruncate(trimmed, max_chars)),
            .contentType = try allocator.dupe(u8, "application/json"),
        };
    }

    return .{
        .title = try allocator.dupe(u8, url),
        .content = try allocator.dupe(u8, trimAndTruncate(trimmed, max_chars)),
        .contentType = try allocator.dupe(u8, "text/plain"),
    };
}

fn extractTitleAlloc(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    const open_idx = indexOfIgnoreCase(html, "<title", 0) orelse return allocator.dupe(u8, "");
    const start = std.mem.indexOfPos(u8, html, open_idx, ">") orelse return allocator.dupe(u8, "");
    const close_idx = indexOfIgnoreCase(html, "</title>", start + 1) orelse return allocator.dupe(u8, "");
    return cleanHtmlSnippetAlloc(allocator, html[start + 1 .. close_idx], 240);
}

fn htmlToTextAlloc(allocator: std.mem.Allocator, html: []const u8, max_chars: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    var in_script = false;
    var in_style = false;
    var last_was_space = true;

    while (i < html.len) {
        if (html[i] == '<') {
            if (startsWithIgnoreCaseAt(html, i, "<script")) {
                in_script = true;
            } else if (startsWithIgnoreCaseAt(html, i, "</script")) {
                in_script = false;
                try appendBoundary(&out, allocator, &last_was_space);
            } else if (startsWithIgnoreCaseAt(html, i, "<style")) {
                in_style = true;
            } else if (startsWithIgnoreCaseAt(html, i, "</style")) {
                in_style = false;
                try appendBoundary(&out, allocator, &last_was_space);
            } else if (isBlockBoundaryTag(html, i)) {
                try appendBoundary(&out, allocator, &last_was_space);
            }

            const close_idx = std.mem.indexOfPos(u8, html, i, ">") orelse break;
            i = close_idx + 1;
            continue;
        }

        if (in_script or in_style) {
            i += 1;
            continue;
        }

        if (html[i] == '&') {
            if (decodeEntity(html, i)) |decoded| {
                switch (decoded.char) {
                    ' ', '\n', '\t', '\r' => try appendBoundary(&out, allocator, &last_was_space),
                    else => {
                        if (out.items.len >= max_chars) break;
                        try out.append(allocator, decoded.char);
                        last_was_space = false;
                    },
                }
                i = decoded.next_index;
                continue;
            }
        }

        const ch = html[i];
        if (std.ascii.isWhitespace(ch)) {
            try appendBoundary(&out, allocator, &last_was_space);
        } else if (std.ascii.isControl(ch) and ch != '\n' and ch != '\t') {
            // skip
        } else {
            if (out.items.len >= max_chars) break;
            try out.append(allocator, ch);
            last_was_space = false;
        }
        i += 1;
    }

    return trimOwned(allocator, try out.toOwnedSlice(allocator));
}

fn appendBoundary(out: *std.ArrayList(u8), allocator: std.mem.Allocator, last_was_space: *bool) !void {
    if (last_was_space.*) return;
    try out.append(allocator, ' ');
    last_was_space.* = true;
}

fn isBlockBoundaryTag(html: []const u8, idx: usize) bool {
    const tags = [_][]const u8{ "<br", "<p", "</p", "<div", "</div", "<li", "</li", "<tr", "</tr", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "</h1", "</h2", "</h3", "</h4", "</h5", "</h6" };
    for (tags) |tag| {
        if (startsWithIgnoreCaseAt(html, idx, tag)) return true;
    }
    return false;
}

const DecodedEntity = struct {
    char: u8,
    next_index: usize,
};

fn decodeEntity(html: []const u8, idx: usize) ?DecodedEntity {
    const candidates = [_]struct { entity: []const u8, char: u8 }{
        .{ .entity = "&nbsp;", .char = ' ' },
        .{ .entity = "&amp;", .char = '&' },
        .{ .entity = "&lt;", .char = '<' },
        .{ .entity = "&gt;", .char = '>' },
        .{ .entity = "&quot;", .char = '"' },
        .{ .entity = "&#39;", .char = '\'' },
    };
    for (candidates) |candidate| {
        if (startsWithIgnoreCaseAt(html, idx, candidate.entity)) {
            return .{ .char = candidate.char, .next_index = idx + candidate.entity.len };
        }
    }
    return null;
}

fn cleanHtmlSnippetAlloc(allocator: std.mem.Allocator, html: []const u8, max_chars: usize) ![]u8 {
    const text = try htmlToTextAlloc(allocator, html, max_chars);
    return text;
}

fn findNextResultAnchor(body: []const u8, cursor: usize) ?usize {
    const patterns = [_][]const u8{
        "class=\"result__a\"",
        "class='result__a'",
        "class=\"result-link\"",
        "class='result-link'",
        "data-testid=\"result-title-a\"",
    };
    var best: ?usize = null;
    for (patterns) |pattern| {
        if (std.mem.indexOfPos(u8, body, cursor, pattern)) |idx| {
            const anchor_start = std.mem.lastIndexOfScalar(u8, body[cursor .. idx + pattern.len], '<') orelse continue;
            const absolute = cursor + anchor_start;
            if (best == null or absolute < best.?) best = absolute;
        }
    }
    if (best != null) return best;
    if (std.mem.indexOfPos(u8, body, cursor, "<a ")) |idx| return idx;
    return null;
}

fn extractHrefAt(body: []const u8, anchor_idx: usize) ?[]const u8 {
    const close_idx = std.mem.indexOfPos(u8, body, anchor_idx, ">") orelse return null;
    const anchor_tag = body[anchor_idx..close_idx];
    if (extractAttr(anchor_tag, "href")) |href| return href;
    return null;
}

fn extractAttr(tag: []const u8, attr_name: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (cursor < tag.len) : (cursor += 1) {
        const idx = indexOfIgnoreCase(tag, attr_name, cursor) orelse return null;
        const after_name = idx + attr_name.len;
        if (after_name >= tag.len) return null;
        var pos = after_name;
        while (pos < tag.len and std.ascii.isWhitespace(tag[pos])) : (pos += 1) {}
        if (pos >= tag.len or tag[pos] != '=') {
            cursor = after_name;
            continue;
        }
        pos += 1;
        while (pos < tag.len and std.ascii.isWhitespace(tag[pos])) : (pos += 1) {}
        if (pos >= tag.len) return null;
        const quote = tag[pos];
        if (quote == '"' or quote == '\'') {
            const value_start = pos + 1;
            const value_end_rel = std.mem.indexOfScalarPos(u8, tag, value_start, quote) orelse return null;
            return tag[value_start..value_end_rel];
        }
        const value_start = pos;
        var value_end = value_start;
        while (value_end < tag.len and !std.ascii.isWhitespace(tag[value_end]) and tag[value_end] != '>') : (value_end += 1) {}
        return tag[value_start..value_end];
    }
    return null;
}

fn findNearbySnippet(segment: []const u8) []const u8 {
    const patterns = [_][]const u8{ "result__snippet", "result-snippet", "snippet", "description" };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, segment, pattern)) |pattern_idx| {
            const start_tag = std.mem.lastIndexOfScalar(u8, segment[0 .. pattern_idx + pattern.len], '<') orelse continue;
            const content_start = std.mem.indexOfPos(u8, segment, start_tag, ">") orelse continue;
            const end_tag = std.mem.indexOfPos(u8, segment, content_start + 1, "</") orelse continue;
            if (end_tag > content_start + 1) return segment[content_start + 1 .. end_tag];
        }
    }
    const fallback_end = @min(segment.len, 320);
    return segment[0..fallback_end];
}

fn decodeHrefAlloc(allocator: std.mem.Allocator, href: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, href, "//")) {
        return std.fmt.allocPrint(allocator, "https:{s}", .{href});
    }
    if (std.mem.indexOf(u8, href, "uddg=") != null) {
        const uddg_idx = std.mem.indexOf(u8, href, "uddg=").? + 5;
        const end_idx = std.mem.indexOfScalarPos(u8, href, uddg_idx, '&') orelse href.len;
        const encoded = href[uddg_idx..end_idx];
        return urlDecodeAlloc(allocator, encoded);
    }
    return urlDecodeAlloc(allocator, href);
}

fn jsonObjectString(obj: std.json.ObjectMap, keys: []const []const u8) ?[]const u8 {
    for (keys) |key| {
        if (obj.get(key)) |value| {
            if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) return value.string;
        }
    }
    return null;
}

fn inferContentType(body: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (looksLikeHtml(trimmed)) return "text/html";
    if (looksLikeJson(trimmed)) return "application/json";
    return "text/plain";
}

fn looksLikeHtml(body: []const u8) bool {
    return startsWithIgnoreCase(body, "<!doctype") or startsWithIgnoreCase(body, "<html") or startsWithIgnoreCase(body, "<body") or indexOfIgnoreCase(body, "<title", 0) != null;
}

fn looksLikeJson(body: []const u8) bool {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (trimmed.len == 0) return false;
    return trimmed[0] == '{' or trimmed[0] == '[';
}

fn trimAndTruncate(body: []const u8, max_chars: usize) []const u8 {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    return if (trimmed.len <= max_chars) trimmed else trimmed[0..max_chars];
}

fn trimOwned(allocator: std.mem.Allocator, text: []u8) ![]u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.ptr == text.ptr and trimmed.len == text.len) return text;
    const out = try allocator.dupe(u8, trimmed);
    allocator.free(text);
    return out;
}

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return startsWithIgnoreCaseAt(haystack, 0, needle);
}

fn startsWithIgnoreCaseAt(haystack: []const u8, idx: usize, needle: []const u8) bool {
    if (idx + needle.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle);
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8, start: usize) ?usize {
    if (needle.len == 0) return start;
    var idx = start;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return idx;
    }
    return null;
}

fn urlEncodeAlloc(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (raw) |ch| {
        const is_safe = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == '~';
        if (is_safe) {
            try out.append(allocator, ch);
        } else if (ch == ' ') {
            try out.appendSlice(allocator, "%20");
        } else {
            const encoded = try std.fmt.allocPrint(allocator, "%{X:0>2}", .{ch});
            defer allocator.free(encoded);
            try out.appendSlice(allocator, encoded);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn urlDecodeAlloc(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var idx: usize = 0;
    while (idx < raw.len) : (idx += 1) {
        const ch = raw[idx];
        if (ch == '%' and idx + 2 < raw.len) {
            const hex = raw[idx + 1 .. idx + 3];
            const value = std.fmt.parseInt(u8, hex, 16) catch {
                try out.append(allocator, ch);
                continue;
            };
            try out.append(allocator, value);
            idx += 2;
            continue;
        }
        if (ch == '+') {
            try out.append(allocator, ' ');
            continue;
        }
        try out.append(allocator, ch);
    }
    return out.toOwnedSlice(allocator);
}

test "web tools search parses json provider results" {
    const allocator = std.testing.allocator;
    const body =
        \\{"results":[
        \\  {"url":"http://127.0.0.1:19091/page-1","title":"Hermes Port Mock","description":"Mock snippet"},
        \\  {"url":"http://127.0.0.1:19091/page-2","title":"Second","description":"Another"}
        \\]}
    ;
    const items = try parseSearchResultsJsonAlloc(allocator, body, 5);
    defer {
        for (items) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqualStrings("Hermes Port Mock", items[0].title);
}

test "web tools html to text strips tags and entities" {
    const allocator = std.testing.allocator;
    const html =
        \\<html><head><title>Alpha &amp; Beta</title><style>.x{}</style></head>
        \\<body><h1>Hello</h1><p>ZAR &amp; Hermes</p><script>ignored()</script></body></html>
    ;
    const title = try extractTitleAlloc(allocator, html);
    defer allocator.free(title);
    try std.testing.expectEqualStrings("Alpha & Beta", title);

    const text = try htmlToTextAlloc(allocator, html, 200);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ZAR & Hermes") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ignored") == null);
}

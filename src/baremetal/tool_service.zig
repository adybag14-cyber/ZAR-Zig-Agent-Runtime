const std = @import("std");
const abi = @import("abi.zig");
const app_runtime = @import("app_runtime.zig");
const disk_installer = @import("disk_installer.zig");
const display_output = @import("display_output.zig");
const filesystem = @import("filesystem.zig");
const framebuffer_console = @import("framebuffer_console.zig");
const package_store = @import("package_store.zig");
const storage_backend = @import("storage_backend.zig");
const trust_store = @import("trust_store.zig");
const tool_exec = @import("tool_exec.zig");
const tool_layout = @import("tool_layout.zig");

pub const Error = tool_exec.Error || package_store.Error || trust_store.Error || std.mem.Allocator.Error || error{
    EmptyRequest,
    InvalidFrame,
    ResponseTooLarge,
};

pub const FramedCommandRequest = struct {
    request_id: u32,
    command: []const u8,
};

pub const RequestOp = enum {
    command,
    execute,
    get,
    put,
    stat,
    list,
    install,
    manifest,
    package_install,
    package_list,
    package_info,
    package_app,
    package_display,
    package_run,
    package_asset_put,
    package_asset_list,
    package_asset_get,
    app_list,
    app_info,
    app_state,
    app_trust,
    app_connector,
    app_run,
    display_info,
    display_modes,
    display_set,
    trust_install,
    trust_list,
    trust_info,
    trust_active,
    trust_select,
    trust_delete,
};

pub const PutRequest = struct {
    path: []const u8,
    body: []const u8,
};

pub const PackagePathRequest = struct {
    package_name: []const u8,
    relative_path: []const u8,
};

pub const PackagePutRequest = struct {
    package_name: []const u8,
    relative_path: []const u8,
    body: []const u8,
};

pub const PackageDisplayRequest = struct {
    package_name: []const u8,
    width: u16,
    height: u16,
};

pub const NamedValueRequest = struct {
    package_name: []const u8,
    value: []const u8,
};

pub const DisplayModeRequest = struct {
    width: u16,
    height: u16,
};

pub const FramedRequest = struct {
    request_id: u32,
    operation: union(RequestOp) {
        command: []const u8,
        execute: []const u8,
        get: []const u8,
        put: PutRequest,
        stat: []const u8,
        list: []const u8,
        install: void,
        manifest: void,
        package_install: PutRequest,
        package_list: void,
        package_info: []const u8,
        package_app: []const u8,
        package_display: PackageDisplayRequest,
        package_run: []const u8,
        package_asset_put: PackagePutRequest,
        package_asset_list: []const u8,
        package_asset_get: PackagePathRequest,
        app_list: void,
        app_info: []const u8,
        app_state: []const u8,
        app_trust: NamedValueRequest,
        app_connector: NamedValueRequest,
        app_run: []const u8,
        display_info: void,
        display_modes: void,
        display_set: DisplayModeRequest,
        trust_install: PutRequest,
        trust_list: void,
        trust_info: []const u8,
        trust_active: void,
        trust_select: []const u8,
        trust_delete: []const u8,
    },
};

const ConsumedRequest = struct {
    framed: FramedRequest,
    consumed_len: usize,
};

pub fn handleCommandRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const trimmed = std.mem.trim(u8, request, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyRequest;

    var result = try tool_exec.runCapture(allocator, trimmed, stdout_limit, stderr_limit);
    defer result.deinit(allocator);

    if (result.exit_code == 0 and result.stderr.len == 0) {
        if (result.stdout.len > response_limit) return error.ResponseTooLarge;
        return allocator.dupe(u8, result.stdout);
    }

    const detail = if (result.stderr.len != 0) result.stderr else result.stdout;
    const response = try std.fmt.allocPrint(allocator, "ERR exit={d}\n{s}", .{ result.exit_code, detail });
    errdefer allocator.free(response);
    if (response.len > response_limit) return error.ResponseTooLarge;
    return response;
}

pub fn parseFramedCommandRequest(request: []const u8) Error!FramedCommandRequest {
    const framed = try parseFramedRequest(request);
    return switch (framed.operation) {
        .command => |command| .{ .request_id = framed.request_id, .command = command },
        else => error.InvalidFrame,
    };
}

pub fn parseFramedRequest(request: []const u8) Error!FramedRequest {
    const consumed = try parseFramedRequestPrefix(request);
    if (trimLeftWhitespace(request[consumed.consumed_len..]).len != 0) return error.InvalidFrame;
    return consumed.framed;
}

pub fn handleFramedCommandRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const framed = try parseFramedCommandRequest(request);
    const payload_limit = payloadLimitForResponse(response_limit);
    const payload = try handleCommandRequest(allocator, framed.command, stdout_limit, stderr_limit, payload_limit);
    defer allocator.free(payload);

    return formatFramedResponse(allocator, framed.request_id, payload, response_limit);
}

pub fn handleFramedRequest(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const framed = try parseFramedRequest(request);
    return handleFramedResponse(allocator, framed, stdout_limit, stderr_limit, response_limit);
}

pub fn handleFramedRequestBatch(
    allocator: std.mem.Allocator,
    request: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    var response: std.ArrayList(u8) = .empty;
    errdefer response.deinit(allocator);

    var remaining = request;
    var saw_frame = false;
    while (true) {
        const trimmed = trimLeftWhitespace(remaining);
        if (trimmed.len == 0) break;

        const consumed = try parseFramedRequestPrefix(remaining);
        saw_frame = true;
        remaining = remaining[consumed.consumed_len..];

        const response_remaining = response_limit -| response.items.len;
        if (response_remaining == 0) return error.ResponseTooLarge;

        const frame_response = try handleFramedResponse(
            allocator,
            consumed.framed,
            stdout_limit,
            stderr_limit,
            response_remaining,
        );
        defer allocator.free(frame_response);

        if (response.items.len + frame_response.len > response_limit) return error.ResponseTooLarge;
        try response.appendSlice(allocator, frame_response);
    }

    if (!saw_frame) return error.EmptyRequest;
    return response.toOwnedSlice(allocator);
}

fn handleFramedResponse(
    allocator: std.mem.Allocator,
    framed: FramedRequest,
    stdout_limit: usize,
    stderr_limit: usize,
    response_limit: usize,
) Error![]u8 {
    const payload_limit = payloadLimitForResponse(response_limit);
    const payload = try handleFramedPayload(allocator, framed, stdout_limit, stderr_limit, payload_limit);
    defer allocator.free(payload);

    return formatFramedResponse(allocator, framed.request_id, payload, response_limit);
}

const TokenSplit = struct {
    token: []const u8,
    rest: []const u8,
};

fn payloadLimitForResponse(response_limit: usize) usize {
    return if (response_limit > 32) response_limit - 32 else response_limit;
}

fn parseFramedRequestPrefix(request: []const u8) Error!ConsumedRequest {
    const trimmed = trimLeftWhitespace(request);
    if (trimmed.len == 0) return error.EmptyRequest;

    const prefix_len = request.len - trimmed.len;
    const newline_index = std.mem.indexOfScalar(u8, trimmed, '\n');
    const header_len = newline_index orelse trimmed.len;
    const header = std.mem.trim(u8, trimmed[0..header_len], " \t\r\n");
    if (header.len == 0) return error.EmptyRequest;
    if (!std.mem.startsWith(u8, header, "REQ ")) return error.InvalidFrame;

    const body = trimLeftWhitespace(header["REQ ".len..]);
    if (body.len == 0) return error.InvalidFrame;

    const request_id_part = try splitFirstToken(body);
    const request_id = std.fmt.parseUnsigned(u32, request_id_part.token, 10) catch return error.InvalidFrame;
    const remainder = request_id_part.rest;
    if (remainder.len == 0) return error.InvalidFrame;

    const op_part = splitFirstToken(remainder) catch {
        const consumed_len = if (newline_index) |idx| prefix_len + idx + 1 else request.len;
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .command = remainder },
            },
            .consumed_len = consumed_len,
        };
    };

    if (std.ascii.eqlIgnoreCase(op_part.token, "CMD")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .command = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .command = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "EXEC")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .execute = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .execute = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "GET")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .get = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .get = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "STAT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .stat = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .stat = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "LIST")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            const consumed_len = prefix_len + newline_index.? + 1;
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .list = op_part.rest } },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "INSTALL")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .install = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .install = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "MANIFEST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .manifest = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .manifest = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGRUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGAPP")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_app = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_app = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGDISPLAY")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const width_part = try splitFirstToken(package_name_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        if (height_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .package_display = .{
                .package_name = package_name_part.token,
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGLS")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .package_asset_list = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .package_asset_list = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGGET")) {
        const name_part = try splitFirstToken(op_part.rest);
        if (name_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{
                    .request_id = request_id,
                    .operation = .{ .package_asset_get = .{
                        .package_name = name_part.token,
                        .relative_path = name_part.rest,
                    } },
                },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .package_asset_get = .{
                    .package_name = name_part.token,
                    .relative_path = name_part.rest,
                } },
            },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPSTATE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_state = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_state = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPTRUST")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const trust_name_part = try splitFirstToken(package_name_part.rest);
        if (trust_name_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_trust = .{
                .package_name = package_name_part.token,
                .value = trust_name_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPCONNECTOR")) {
        const package_name_part = try splitFirstToken(op_part.rest);
        const connector_part = try splitFirstToken(package_name_part.rest);
        if (connector_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .app_connector = .{
                .package_name = package_name_part.token,
                .value = connector_part.token,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "APPRUN")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .app_run = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .app_run = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYINFO")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_info = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_info = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYMODES")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .display_modes = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .display_modes = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "DISPLAYSET")) {
        const width_part = try splitFirstToken(op_part.rest);
        const height_part = try splitFirstToken(width_part.rest);
        if (height_part.rest.len != 0) return error.InvalidFrame;
        const request_value = FramedRequest{
            .request_id = request_id,
            .operation = .{ .display_set = .{
                .width = std.fmt.parseInt(u16, width_part.token, 10) catch return error.InvalidFrame,
                .height = std.fmt.parseInt(u16, height_part.token, 10) catch return error.InvalidFrame,
            } },
        };
        if (newline_index != null) {
            return .{
                .framed = request_value,
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = request_value,
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTLIST")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_list = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_list = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTINFO")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_info = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_info = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTACTIVE")) {
        if (op_part.rest.len != 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_active = {} } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_active = {} } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTSELECT")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_select = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_select = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTDELETE")) {
        if (op_part.rest.len == 0) return error.InvalidFrame;
        if (newline_index != null) {
            return .{
                .framed = .{ .request_id = request_id, .operation = .{ .trust_delete = op_part.rest } },
                .consumed_len = prefix_len + newline_index.? + 1,
            };
        }
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .trust_delete = op_part.rest } },
            .consumed_len = request.len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PKGPUT")) {
        const name_part = try splitFirstToken(op_part.rest);
        const path_part = try splitFirstToken(name_part.rest);
        const length_part = try splitFirstToken(path_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .package_asset_put = .{
                    .package_name = name_part.token,
                    .relative_path = path_part.token,
                    .body = body_payload,
                } },
            },
            .consumed_len = prefix_len + payload_start + body_len,
        };
    }

    if (std.ascii.eqlIgnoreCase(op_part.token, "PUT") or
        std.ascii.eqlIgnoreCase(op_part.token, "PKG") or
        std.ascii.eqlIgnoreCase(op_part.token, "TRUSTPUT"))
    {
        const path_part = try splitFirstToken(op_part.rest);
        const length_part = try splitFirstToken(path_part.rest);
        if (length_part.rest.len != 0) return error.InvalidFrame;
        const body_len = std.fmt.parseUnsigned(usize, length_part.token, 10) catch return error.InvalidFrame;
        const body_start = newline_index orelse return error.InvalidFrame;
        const payload_start = body_start + 1;
        if (trimmed.len < payload_start + body_len) return error.InvalidFrame;
        const body_payload = trimmed[payload_start .. payload_start + body_len];
        const consumed_len = prefix_len + payload_start + body_len;
        if (std.ascii.eqlIgnoreCase(op_part.token, "PUT")) {
            return .{
                .framed = .{
                    .request_id = request_id,
                    .operation = .{ .put = .{ .path = path_part.token, .body = body_payload } },
                },
                .consumed_len = consumed_len,
            };
        }
        if (std.ascii.eqlIgnoreCase(op_part.token, "TRUSTPUT")) {
            return .{
                .framed = .{
                    .request_id = request_id,
                    .operation = .{ .trust_install = .{ .path = path_part.token, .body = body_payload } },
                },
                .consumed_len = consumed_len,
            };
        }
        return .{
            .framed = .{
                .request_id = request_id,
                .operation = .{ .package_install = .{ .path = path_part.token, .body = body_payload } },
            },
            .consumed_len = consumed_len,
        };
    }

    if (newline_index != null) {
        return .{
            .framed = .{ .request_id = request_id, .operation = .{ .command = remainder } },
            .consumed_len = prefix_len + newline_index.? + 1,
        };
    }
    return .{
        .framed = .{ .request_id = request_id, .operation = .{ .command = remainder } },
        .consumed_len = request.len,
    };
}

fn handleFramedPayload(
    allocator: std.mem.Allocator,
    framed: FramedRequest,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    return switch (framed.operation) {
        .command => |command| try handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit),
        .execute => |command| try handleExecRequest(allocator, command, stdout_limit, stderr_limit, payload_limit),
        .get => |path| try handleGetRequest(allocator, path, payload_limit),
        .put => |put_request| try handlePutRequest(allocator, put_request.path, put_request.body, payload_limit),
        .stat => |path| try handleStatRequest(allocator, path, payload_limit),
        .list => |path| try handleListRequest(allocator, path, payload_limit),
        .install => try handleInstallRequest(allocator, payload_limit),
        .manifest => try handleManifestRequest(allocator, payload_limit),
        .package_install => |package_request| try handlePackageInstallRequest(allocator, package_request.path, package_request.body, payload_limit),
        .package_list => try handlePackageListRequest(allocator, payload_limit),
        .package_info => |package_name| try handlePackageInfoRequest(allocator, package_name, payload_limit),
        .package_app => |package_name| try handlePackageAppRequest(allocator, package_name, payload_limit),
        .package_display => |package_display| try handlePackageDisplayRequest(allocator, package_display.package_name, package_display.width, package_display.height, payload_limit),
        .package_run => |package_name| try handlePackageRunRequest(allocator, package_name, stdout_limit, stderr_limit, payload_limit),
        .package_asset_put => |asset_request| try handlePackageAssetPutRequest(allocator, asset_request.package_name, asset_request.relative_path, asset_request.body, payload_limit),
        .package_asset_list => |package_name| try handlePackageAssetListRequest(allocator, package_name, payload_limit),
        .package_asset_get => |asset_request| try handlePackageAssetGetRequest(allocator, asset_request.package_name, asset_request.relative_path, payload_limit),
        .app_list => try handleAppListRequest(allocator, payload_limit),
        .app_info => |package_name| try handleAppInfoRequest(allocator, package_name, payload_limit),
        .app_state => |package_name| try handleAppStateRequest(allocator, package_name, payload_limit),
        .app_trust => |app_request| try handleAppTrustRequest(allocator, app_request.package_name, app_request.value, payload_limit),
        .app_connector => |app_request| try handleAppConnectorRequest(allocator, app_request.package_name, app_request.value, payload_limit),
        .app_run => |package_name| try handleAppRunRequest(allocator, package_name, stdout_limit, stderr_limit, payload_limit),
        .display_info => try handleDisplayInfoRequest(allocator, payload_limit),
        .display_modes => try handleDisplayModesRequest(allocator, payload_limit),
        .display_set => |display_mode| try handleDisplaySetRequest(allocator, display_mode.width, display_mode.height, payload_limit),
        .trust_install => |trust_request| try handleTrustInstallRequest(allocator, trust_request.path, trust_request.body, payload_limit),
        .trust_list => try handleTrustListRequest(allocator, payload_limit),
        .trust_info => |trust_name| try handleTrustInfoRequest(allocator, trust_name, payload_limit),
        .trust_active => try handleTrustActiveRequest(allocator, payload_limit),
        .trust_select => |trust_name| try handleTrustSelectRequest(allocator, trust_name, payload_limit),
        .trust_delete => |trust_name| try handleTrustDeleteRequest(allocator, trust_name, payload_limit),
    };
}

fn splitFirstToken(text: []const u8) Error!TokenSplit {
    const trimmed = trimLeftWhitespace(text);
    if (trimmed.len == 0) return error.InvalidFrame;

    var idx: usize = 0;
    while (idx < trimmed.len and !std.ascii.isWhitespace(trimmed[idx])) : (idx += 1) {}
    return .{
        .token = trimmed[0..idx],
        .rest = trimLeftWhitespace(trimmed[idx..]),
    };
}

fn formatFramedResponse(
    allocator: std.mem.Allocator,
    request_id: u32,
    payload: []const u8,
    response_limit: usize,
) Error![]u8 {
    const response = try std.fmt.allocPrint(allocator, "RESP {d} {d}\n{s}", .{ request_id, payload.len, payload });
    errdefer allocator.free(response);
    if (response.len > response_limit) return error.ResponseTooLarge;
    return response;
}

fn handleGetRequest(allocator: std.mem.Allocator, path: []const u8, payload_limit: usize) Error![]u8 {
    return filesystem.readFileAlloc(allocator, path, payload_limit) catch |err| {
        return formatOperationError(allocator, "GET", err, payload_limit);
    };
}

fn handleExecRequest(
    allocator: std.mem.Allocator,
    command: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var result = try tool_exec.runCapture(allocator, command, stdout_limit, stderr_limit);
    defer result.deinit(allocator);

    var response: std.ArrayList(u8) = .empty;
    errdefer response.deinit(allocator);

    const header = try std.fmt.allocPrint(
        allocator,
        "exit={d} stdout_len={d} stderr_len={d}\nstdout:\n",
        .{ result.exit_code, result.stdout.len, result.stderr.len },
    );
    defer allocator.free(header);
    try response.appendSlice(allocator, header);
    try response.appendSlice(allocator, result.stdout);
    if (result.stdout.len == 0 or result.stdout[result.stdout.len - 1] != '\n') {
        try response.append(allocator, '\n');
    }
    try response.appendSlice(allocator, "stderr:\n");
    try response.appendSlice(allocator, result.stderr);
    if (result.stderr.len == 0 or result.stderr[result.stderr.len - 1] != '\n') {
        try response.append(allocator, '\n');
    }

    if (response.items.len > payload_limit) return error.ResponseTooLarge;
    return response.toOwnedSlice(allocator);
}

fn handlePutRequest(allocator: std.mem.Allocator, path: []const u8, body: []const u8, payload_limit: usize) Error![]u8 {
    ensureParentDirectory(path) catch |err| {
        return formatOperationError(allocator, "PUT", err, payload_limit);
    };
    filesystem.writeFile(path, body, 0) catch |err| {
        return formatOperationError(allocator, "PUT", err, payload_limit);
    };

    const response = try std.fmt.allocPrint(allocator, "WROTE {d} bytes to {s}\n", .{ body.len, path });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleStatRequest(allocator: std.mem.Allocator, path: []const u8, payload_limit: usize) Error![]u8 {
    const stat = filesystem.statSummary(path) catch |err| {
        return formatOperationError(allocator, "STAT", err, payload_limit);
    };
    const kind = switch (stat.kind) {
        .directory => "directory",
        .file => "file",
        else => "unknown",
    };
    const response = try std.fmt.allocPrint(allocator, "path={s} kind={s} size={d}\n", .{ path, kind, stat.size });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleListRequest(allocator: std.mem.Allocator, path: []const u8, payload_limit: usize) Error![]u8 {
    return filesystem.listDirectoryAlloc(allocator, path, payload_limit) catch |err| {
        return formatOperationError(allocator, "LIST", err, payload_limit);
    };
}

fn handleInstallRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    disk_installer.installDefaultLayout(1) catch |err| {
        return formatOperationError(allocator, "INSTALL", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "INSTALLED {s}\n", .{disk_installer.install_manifest_path});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleManifestRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    var manifest_buf: [192]u8 = undefined;
    const manifest = disk_installer.installManifestForCurrentBackend(manifest_buf[0..]) catch |err| {
        return formatOperationError(allocator, "MANIFEST", err, payload_limit);
    };
    if (manifest.len > payload_limit) return error.ResponseTooLarge;
    return allocator.dupe(u8, manifest);
}

fn handlePackageInstallRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    body: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.installScriptPackage(package_name, body, 0) catch |err| {
        return formatOperationError(allocator, "PKG", err, payload_limit);
    };

    var entrypoint_buf: [filesystem.max_path_len]u8 = undefined;
    const entrypoint = package_store.entrypointPath(package_name, &entrypoint_buf) catch |err| {
        return formatOperationError(allocator, "PKG", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "INSTALLED {s} -> {s}\n", .{ package_name, entrypoint });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return package_store.listPackagesAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGLIST", err, payload_limit);
    };
}

fn handlePackageInfoRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.manifestAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGINFO", err, payload_limit);
    };
}

fn handlePackageAppRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.appManifestAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGAPP", err, payload_limit);
    };
}

fn handlePackageDisplayRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    width: u16,
    height: u16,
    payload_limit: usize,
) Error![]u8 {
    package_store.configureDisplayMode(package_name, width, height, 0) catch |err| {
        return formatOperationError(allocator, "PKGDISPLAY", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DISPLAY {s} {d}x{d}\n", .{ package_name, width, height });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageAssetPutRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    relative_path: []const u8,
    body: []const u8,
    payload_limit: usize,
) Error![]u8 {
    package_store.installPackageAsset(package_name, relative_path, body, 0) catch |err| {
        return formatOperationError(allocator, "PKGPUT", err, payload_limit);
    };

    var asset_buf: [filesystem.max_path_len]u8 = undefined;
    const asset_path = package_store.assetPath(package_name, relative_path, &asset_buf) catch |err| {
        return formatOperationError(allocator, "PKGPUT", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "ASSET {s} -> {s}\n", .{ package_name, asset_path });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handlePackageAssetListRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return package_store.listPackageAssetsAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGLS", err, payload_limit);
    };
}

fn handlePackageAssetGetRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    relative_path: []const u8,
    payload_limit: usize,
) Error![]u8 {
    return package_store.readPackageAssetAlloc(allocator, package_name, relative_path, payload_limit) catch |err| {
        return formatOperationError(allocator, "PKGGET", err, payload_limit);
    };
}

fn handlePackageRunRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "run-package {s}", .{package_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handleAppListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return app_runtime.listAppsAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPLIST", err, payload_limit);
    };
}

fn handleAppInfoRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.infoAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPINFO", err, payload_limit);
    };
}

fn handleAppStateRequest(allocator: std.mem.Allocator, package_name: []const u8, payload_limit: usize) Error![]u8 {
    return app_runtime.stateAlloc(allocator, package_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "APPSTATE", err, payload_limit);
    };
}

fn handleAppTrustRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    trust_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    const selected_name = if (std.ascii.eqlIgnoreCase(trust_name, "none")) "" else trust_name;
    package_store.configureTrustBundle(package_name, selected_name, 0) catch |err| {
        return formatOperationError(allocator, "APPTRUST", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "APPTRUST {s} {s}\n",
        .{ package_name, if (selected_name.len == 0) "none" else selected_name },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppConnectorRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    connector_name: []const u8,
    payload_limit: usize,
) Error![]u8 {
    const connector_type = package_store.parseConnectorType(connector_name) catch |err| {
        return formatOperationError(allocator, "APPCONNECTOR", err, payload_limit);
    };
    package_store.configureConnectorType(package_name, connector_type, 0) catch |err| {
        return formatOperationError(allocator, "APPCONNECTOR", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(
        allocator,
        "APPCONNECTOR {s} {s}\n",
        .{ package_name, package_store.connectorNameFromType(connector_type) },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleAppRunRequest(
    allocator: std.mem.Allocator,
    package_name: []const u8,
    stdout_limit: usize,
    stderr_limit: usize,
    payload_limit: usize,
) Error![]u8 {
    var command_buf: [96]u8 = undefined;
    const command = std.fmt.bufPrint(&command_buf, "app-run {s}", .{package_name}) catch return error.InvalidFrame;
    return handleCommandRequest(allocator, command, stdout_limit, stderr_limit, payload_limit);
}

fn handleTrustInstallRequest(
    allocator: std.mem.Allocator,
    trust_name: []const u8,
    body: []const u8,
    payload_limit: usize,
) Error![]u8 {
    trust_store.installBundle(trust_name, body, 0) catch |err| {
        return formatOperationError(allocator, "TRUSTPUT", err, payload_limit);
    };

    var bundle_path_buffer: [filesystem.max_path_len]u8 = undefined;
    const bundle_path = trust_store.bundlePath(trust_name, &bundle_path_buffer) catch |err| {
        return formatOperationError(allocator, "TRUSTPUT", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "TRUSTED {s} -> {s}\n", .{ trust_name, bundle_path });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayInfoRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    const output = display_output.statePtr();
    const response = try std.fmt.allocPrint(
        allocator,
        "backend={s} controller={s} connector={s} connected={d} hardware_backed={d} current={d}x{d} preferred={d}x{d} scanouts={d} active={d} capabilities=0x{x}\n",
        .{
            displayBackendName(output.backend),
            displayControllerName(output.controller),
            displayConnectorName(output.connector_type),
            output.connected,
            output.hardware_backed,
            output.current_width,
            output.current_height,
            output.preferred_width,
            output.preferred_height,
            output.scanout_count,
            output.active_scanout,
            output.capability_flags,
        },
    );
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleDisplayModesRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    ensureDisplayReady();
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    var index: u16 = 0;
    while (index < framebuffer_console.supportedModeCount()) : (index += 1) {
        const line = try std.fmt.allocPrint(
            allocator,
            "mode {d} {d}x{d}\n",
            .{ index, framebuffer_console.supportedModeWidth(index), framebuffer_console.supportedModeHeight(index) },
        );
        defer allocator.free(line);
        if (out.items.len + line.len > payload_limit) return error.ResponseTooLarge;
        try out.appendSlice(allocator, line);
    }

    return out.toOwnedSlice(allocator);
}

fn handleDisplaySetRequest(allocator: std.mem.Allocator, width: u16, height: u16, payload_limit: usize) Error![]u8 {
    framebuffer_console.setMode(width, height) catch |err| {
        return formatOperationError(allocator, "DISPLAYSET", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DISPLAY {d}x{d}\n", .{ width, height });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleTrustListRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return trust_store.listBundlesAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "TRUSTLIST", err, payload_limit);
    };
}

fn handleTrustInfoRequest(allocator: std.mem.Allocator, trust_name: []const u8, payload_limit: usize) Error![]u8 {
    return trust_store.infoAlloc(allocator, trust_name, payload_limit) catch |err| {
        return formatOperationError(allocator, "TRUSTINFO", err, payload_limit);
    };
}

fn handleTrustActiveRequest(allocator: std.mem.Allocator, payload_limit: usize) Error![]u8 {
    return trust_store.activeBundleInfoAlloc(allocator, payload_limit) catch |err| {
        return formatOperationError(allocator, "TRUSTACTIVE", err, payload_limit);
    };
}

fn handleTrustSelectRequest(allocator: std.mem.Allocator, trust_name: []const u8, payload_limit: usize) Error![]u8 {
    trust_store.selectBundle(trust_name, 0) catch |err| {
        return formatOperationError(allocator, "TRUSTSELECT", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "SELECTED {s}\n", .{trust_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn handleTrustDeleteRequest(allocator: std.mem.Allocator, trust_name: []const u8, payload_limit: usize) Error![]u8 {
    trust_store.deleteBundle(trust_name, 0) catch |err| {
        return formatOperationError(allocator, "TRUSTDELETE", err, payload_limit);
    };
    const response = try std.fmt.allocPrint(allocator, "DELETED {s}\n", .{trust_name});
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn displayBackendName(value: u8) []const u8 {
    return switch (value) {
        abi.display_backend_bga => "bga",
        abi.display_backend_virtio_gpu => "virtio-gpu",
        else => "none",
    };
}

fn displayControllerName(value: u8) []const u8 {
    return switch (value) {
        abi.display_controller_bochs_bga => "bochs-bga",
        abi.display_controller_virtio_gpu => "virtio-gpu",
        else => "none",
    };
}

fn displayConnectorName(value: u8) []const u8 {
    return switch (value) {
        abi.display_connector_displayport => "displayport",
        abi.display_connector_hdmi => "hdmi",
        abi.display_connector_embedded_displayport => "embedded-displayport",
        abi.display_connector_virtual => "virtual",
        else => "none",
    };
}

fn resetPersistentStateForTest() void {
    storage_backend.resetForTest();
    filesystem.resetForTest();
    tool_layout.resetForTest();
    display_output.resetForTest();
    framebuffer_console.resetForTest();
}

fn formatOperationError(
    allocator: std.mem.Allocator,
    operation: []const u8,
    err: anyerror,
    payload_limit: usize,
) Error![]u8 {
    const response = try std.fmt.allocPrint(allocator, "ERR {s}: {s}\n", .{ operation, @errorName(err) });
    errdefer allocator.free(response);
    if (response.len > payload_limit) return error.ResponseTooLarge;
    return response;
}

fn trimLeftWhitespace(text: []const u8) []const u8 {
    var index: usize = 0;
    while (index < text.len and std.ascii.isWhitespace(text[index])) : (index += 1) {}
    return text[index..];
}

fn ensureParentDirectory(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0 or std.mem.eql(u8, parent, "/")) return;
    try filesystem.createDirPath(parent);
}

fn ensureDisplayReady() void {
    if (display_output.statePtr().backend == abi.display_backend_none) {
        _ = framebuffer_console.init();
    }
}

test "baremetal tool service returns stdout for successful commands" {
    const response = try handleCommandRequest(std.testing.allocator, "echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("tcp-service-ok\n", response);
}

test "baremetal tool service wraps failing command responses" {
    const response = try handleCommandRequest(std.testing.allocator, "missing-command", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "ERR exit=127\n"));
    try std.testing.expect(std.mem.indexOf(u8, response, "unknown command") != null);
}

test "baremetal tool service parses framed command requests" {
    const framed = try parseFramedCommandRequest("REQ 7 echo tcp-service-ok");
    try std.testing.expectEqual(@as(u32, 7), framed.request_id);
    try std.testing.expectEqualStrings("echo tcp-service-ok", framed.command);

    const explicit = try parseFramedCommandRequest("REQ 8 CMD echo tcp-service-ok");
    try std.testing.expectEqual(@as(u32, 8), explicit.request_id);
    try std.testing.expectEqualStrings("echo tcp-service-ok", explicit.command);
}

test "baremetal tool service parses typed framed requests" {
    const put = try parseFramedRequest("REQ 11 PUT /tools/cache/tool.txt 4\nedge");
    try std.testing.expectEqual(@as(u32, 11), put.request_id);
    switch (put.operation) {
        .put => |payload| {
            try std.testing.expectEqualStrings("/tools/cache/tool.txt", payload.path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const get = try parseFramedRequest("REQ 12 GET /tools/cache/tool.txt");
    switch (get.operation) {
        .get => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }

    const exec = try parseFramedRequest("REQ 12 EXEC echo tcp-service-ok");
    switch (exec.operation) {
        .execute => |command| try std.testing.expectEqualStrings("echo tcp-service-ok", command),
        else => return error.InvalidFrame,
    }

    const stat = try parseFramedRequest("REQ 13 STAT /tools/cache/tool.txt");
    switch (stat.operation) {
        .stat => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }

    const list = try parseFramedRequest("REQ 14 LIST /tools/cache");
    switch (list.operation) {
        .list => |path| try std.testing.expectEqualStrings("/tools/cache", path),
        else => return error.InvalidFrame,
    }

    const pkg = try parseFramedRequest("REQ 15 PKG demo 4\nedge");
    switch (pkg.operation) {
        .package_install => |payload| {
            try std.testing.expectEqualStrings("demo", payload.path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const pkg_list = try parseFramedRequest("REQ 16 PKGLIST");
    switch (pkg_list.operation) {
        .package_list => {},
        else => return error.InvalidFrame,
    }

    const pkg_info = try parseFramedRequest("REQ 17 PKGINFO demo");
    switch (pkg_info.operation) {
        .package_info => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_app = try parseFramedRequest("REQ 18 PKGAPP demo");
    switch (pkg_app.operation) {
        .package_app => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_display = try parseFramedRequest("REQ 19 PKGDISPLAY demo 1280 720");
    switch (pkg_display.operation) {
        .package_display => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqual(@as(u16, 1280), payload.width);
            try std.testing.expectEqual(@as(u16, 720), payload.height);
        },
        else => return error.InvalidFrame,
    }

    const pkg_run = try parseFramedRequest("REQ 20 PKGRUN demo");
    switch (pkg_run.operation) {
        .package_run => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_put = try parseFramedRequest("REQ 21 PKGPUT demo config/app.json 4\nedge");
    switch (pkg_put.operation) {
        .package_asset_put => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("config/app.json", payload.relative_path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const pkg_ls = try parseFramedRequest("REQ 22 PKGLS demo");
    switch (pkg_ls.operation) {
        .package_asset_list => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const pkg_get = try parseFramedRequest("REQ 23 PKGGET demo config/app.json");
    switch (pkg_get.operation) {
        .package_asset_get => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("config/app.json", payload.relative_path);
        },
        else => return error.InvalidFrame,
    }

    const display_info = try parseFramedRequest("REQ 24 DISPLAYINFO");
    switch (display_info.operation) {
        .display_info => {},
        else => return error.InvalidFrame,
    }

    const display_modes = try parseFramedRequest("REQ 25 DISPLAYMODES");
    switch (display_modes.operation) {
        .display_modes => {},
        else => return error.InvalidFrame,
    }

    const display_set = try parseFramedRequest("REQ 26 DISPLAYSET 800 600");
    switch (display_set.operation) {
        .display_set => |payload| {
            try std.testing.expectEqual(@as(u16, 800), payload.width);
            try std.testing.expectEqual(@as(u16, 600), payload.height);
        },
        else => return error.InvalidFrame,
    }

    const trust_put = try parseFramedRequest("REQ 27 TRUSTPUT fs55-root 4\nedge");
    switch (trust_put.operation) {
        .trust_install => |payload| {
            try std.testing.expectEqualStrings("fs55-root", payload.path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const trust_list = try parseFramedRequest("REQ 28 TRUSTLIST");
    switch (trust_list.operation) {
        .trust_list => {},
        else => return error.InvalidFrame,
    }

    const trust_info = try parseFramedRequest("REQ 29 TRUSTINFO fs55-root");
    switch (trust_info.operation) {
        .trust_info => |trust_name| try std.testing.expectEqualStrings("fs55-root", trust_name),
        else => return error.InvalidFrame,
    }

    const trust_active = try parseFramedRequest("REQ 30 TRUSTACTIVE");
    switch (trust_active.operation) {
        .trust_active => {},
        else => return error.InvalidFrame,
    }

    const trust_select = try parseFramedRequest("REQ 31 TRUSTSELECT fs55-root");
    switch (trust_select.operation) {
        .trust_select => |trust_name| try std.testing.expectEqualStrings("fs55-root", trust_name),
        else => return error.InvalidFrame,
    }

    const trust_delete = try parseFramedRequest("REQ 32 TRUSTDELETE fs55-root");
    switch (trust_delete.operation) {
        .trust_delete => |trust_name| try std.testing.expectEqualStrings("fs55-root", trust_name),
        else => return error.InvalidFrame,
    }

    const app_list = try parseFramedRequest("REQ 33 APPLIST");
    switch (app_list.operation) {
        .app_list => {},
        else => return error.InvalidFrame,
    }

    const app_info = try parseFramedRequest("REQ 34 APPINFO demo");
    switch (app_info.operation) {
        .app_info => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_state = try parseFramedRequest("REQ 35 APPSTATE demo");
    switch (app_state.operation) {
        .app_state => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const app_trust = try parseFramedRequest("REQ 36 APPTRUST demo fs55-root");
    switch (app_trust.operation) {
        .app_trust => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("fs55-root", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_connector = try parseFramedRequest("REQ 37 APPCONNECTOR demo virtual");
    switch (app_connector.operation) {
        .app_connector => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("virtual", payload.value);
        },
        else => return error.InvalidFrame,
    }

    const app_run = try parseFramedRequest("REQ 38 APPRUN demo");
    switch (app_run.operation) {
        .app_run => |package_name| try std.testing.expectEqualStrings("demo", package_name),
        else => return error.InvalidFrame,
    }

    const install = try parseFramedRequest("REQ 39 INSTALL");
    switch (install.operation) {
        .install => {},
        else => return error.InvalidFrame,
    }

    const manifest = try parseFramedRequest("REQ 40 MANIFEST");
    switch (manifest.operation) {
        .manifest => {},
        else => return error.InvalidFrame,
    }
}

test "baremetal tool service parses framed request prefixes for batches" {
    const batched = "REQ 11 GET /tools/cache/tool.txt\nREQ 12 STAT /tools/cache/tool.txt";
    const first = try parseFramedRequestPrefix(batched);
    try std.testing.expectEqual(@as(usize, "REQ 11 GET /tools/cache/tool.txt\n".len), first.consumed_len);
    switch (first.framed.operation) {
        .get => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }

    const second = try parseFramedRequestPrefix(batched[first.consumed_len..]);
    switch (second.framed.operation) {
        .stat => |path| try std.testing.expectEqualStrings("/tools/cache/tool.txt", path),
        else => return error.InvalidFrame,
    }
}

test "baremetal tool service parses framed package asset prefixes for batches" {
    const batched = "REQ 21 PKGPUT demo config/app.json 4\nedge\nREQ 22 DISPLAYINFO";
    const first = try parseFramedRequestPrefix(batched);
    try std.testing.expectEqual(@as(usize, "REQ 21 PKGPUT demo config/app.json 4\nedge".len), first.consumed_len);
    switch (first.framed.operation) {
        .package_asset_put => |payload| {
            try std.testing.expectEqualStrings("demo", payload.package_name);
            try std.testing.expectEqualStrings("config/app.json", payload.relative_path);
            try std.testing.expectEqualStrings("edge", payload.body);
        },
        else => return error.InvalidFrame,
    }

    const second = try parseFramedRequestPrefix(batched[first.consumed_len..]);
    switch (second.framed.operation) {
        .display_info => {},
        else => return error.InvalidFrame,
    }
}

test "baremetal tool service rejects invalid framed requests" {
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("echo tcp-service-ok"));
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("REQ nope echo tcp-service-ok"));
    try std.testing.expectError(error.InvalidFrame, parseFramedCommandRequest("REQ 7"));
    try std.testing.expectError(error.InvalidFrame, parseFramedRequest("REQ 11 PUT /tools/cache/tool.txt nope\nedge"));
    try std.testing.expectError(error.InvalidFrame, parseFramedRequest("REQ 11 PUT /tools/cache/tool.txt 5\nedge"));
}

test "baremetal tool service returns framed responses for successful commands" {
    const response = try handleFramedCommandRequest(std.testing.allocator, "REQ 7 echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expectEqualStrings("RESP 7 15\ntcp-service-ok\n", response);
}

test "baremetal tool service returns framed responses for failing commands" {
    const response = try handleFramedCommandRequest(std.testing.allocator, "REQ 9 missing-command", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 9 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "ERR exit=127\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "unknown command") != null);
}

test "baremetal tool service returns structured exec responses" {
    const response = try handleFramedRequest(std.testing.allocator, "REQ 10 EXEC echo tcp-service-ok", 256, 256, 256);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 10 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "exit=0 stdout_len=15 stderr_len=0\nstdout:\ntcp-service-ok\nstderr:\n") != null);
}

test "baremetal tool service returns structured exec stderr for failures" {
    const response = try handleFramedRequest(std.testing.allocator, "REQ 11 EXEC missing-command", 256, 256, 512);
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.startsWith(u8, response, "RESP 11 "));
    try std.testing.expect(std.mem.indexOf(u8, response, "exit=127") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "stderr:\nunknown command") != null);
}

test "baremetal tool service handles framed filesystem requests" {
    resetPersistentStateForTest();

    const put_response = try handleFramedRequest(std.testing.allocator, "REQ 11 PUT /tools/cache/tool.txt 4\nedge", 256, 256, 256);
    defer std.testing.allocator.free(put_response);
    try std.testing.expectEqualStrings("RESP 11 39\nWROTE 4 bytes to /tools/cache/tool.txt\n", put_response);

    const get_response = try handleFramedRequest(std.testing.allocator, "REQ 12 GET /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(get_response);
    try std.testing.expectEqualStrings("RESP 12 4\nedge", get_response);

    const stat_response = try handleFramedRequest(std.testing.allocator, "REQ 13 STAT /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(stat_response);
    try std.testing.expectEqualStrings("RESP 13 44\npath=/tools/cache/tool.txt kind=file size=4\n", stat_response);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 14 LIST /tools/cache", 256, 256, 256);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 14 16\nfile tool.txt 4\n", list_response);
}

test "baremetal tool service uploads and runs persisted scripts" {
    resetPersistentStateForTest();

    const script = "write-file /tools/out/data.txt tcp-service-persisted";
    const put_script_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 21 PUT /tools/scripts/net.oc {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(put_script_request);
    const put_script_response = try handleFramedRequest(std.testing.allocator, put_script_request, 512, 256, 512);
    defer std.testing.allocator.free(put_script_response);
    try std.testing.expectEqualStrings("RESP 21 40\nWROTE 52 bytes to /tools/scripts/net.oc\n", put_script_response);

    const run_script_response = try handleFramedRequest(std.testing.allocator, "REQ 22 CMD run-script /tools/scripts/net.oc", 512, 256, 512);
    defer std.testing.allocator.free(run_script_response);
    try std.testing.expectEqualStrings("RESP 22 38\nwrote 21 bytes to /tools/out/data.txt\n", run_script_response);

    const read_output_response = try handleFramedRequest(std.testing.allocator, "REQ 23 GET /tools/out/data.txt", 512, 256, 512);
    defer std.testing.allocator.free(read_output_response);
    try std.testing.expectEqualStrings("RESP 23 21\ntcp-service-persisted", read_output_response);

    const readback = try filesystem.readFileAlloc(std.testing.allocator, "/tools/out/data.txt", 64);
    defer std.testing.allocator.free(readback);
    try std.testing.expectEqualStrings("tcp-service-persisted", readback);
}

test "baremetal tool service installs lists and runs persisted packages" {
    resetPersistentStateForTest();

    const script = "mkdir /pkg/out\nwrite-file /pkg/out/result.txt pkg-service-data\necho pkg-service-ok";
    const install_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 31 PKG demo {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(install_request);

    const install_response = try handleFramedRequest(std.testing.allocator, install_request, 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expect(std.mem.startsWith(u8, install_response, "RESP 31 "));
    try std.testing.expect(std.mem.indexOf(u8, install_response, "INSTALLED demo -> /packages/demo/bin/main.oc\n") != null);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 32 PKGLIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 32 5\ndemo\n", list_response);

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 33 PKGINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 33 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "name=demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "root=/packages/demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "asset_root=/packages/demo/assets") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "asset_count=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "display_height=400") != null);

    const app_response = try handleFramedRequest(std.testing.allocator, "REQ 34 PKGAPP demo", 512, 256, 512);
    defer std.testing.allocator.free(app_response);
    try std.testing.expect(std.mem.startsWith(u8, app_response, "RESP 34 "));
    try std.testing.expect(std.mem.indexOf(u8, app_response, "entrypoint=/packages/demo/bin/main.oc") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_response, "display_width=640") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_response, "display_height=400") != null);

    const pkg_display_response = try handleFramedRequest(std.testing.allocator, "REQ 35 PKGDISPLAY demo 1280 720", 512, 256, 512);
    defer std.testing.allocator.free(pkg_display_response);
    try std.testing.expectEqualStrings("RESP 35 22\nDISPLAY demo 1280x720\n", pkg_display_response);

    const asset_body = "{\"mode\":\"tcp\"}";
    const asset_put_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 36 PKGPUT demo config/app.json {d}\n{s}", .{ asset_body.len, asset_body });
    defer std.testing.allocator.free(asset_put_request);
    const asset_put_response = try handleFramedRequest(std.testing.allocator, asset_put_request, 512, 256, 512);
    defer std.testing.allocator.free(asset_put_response);
    try std.testing.expectEqualStrings("RESP 36 52\nASSET demo -> /packages/demo/assets/config/app.json\n", asset_put_response);

    const asset_list_response = try handleFramedRequest(std.testing.allocator, "REQ 37 PKGLS demo", 512, 256, 512);
    defer std.testing.allocator.free(asset_list_response);
    try std.testing.expectEqualStrings("RESP 37 11\ndir config\n", asset_list_response);

    const asset_get_response = try handleFramedRequest(std.testing.allocator, "REQ 38 PKGGET demo config/app.json", 512, 256, 512);
    defer std.testing.allocator.free(asset_get_response);
    try std.testing.expectEqualStrings("RESP 38 14\n{\"mode\":\"tcp\"}", asset_get_response);

    const asset_readback = try filesystem.readFileAlloc(std.testing.allocator, "/packages/demo/assets/config/app.json", 64);
    defer std.testing.allocator.free(asset_readback);
    try std.testing.expectEqualStrings(asset_body, asset_readback);

    const run_response = try handleFramedRequest(std.testing.allocator, "REQ 39 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(run_response);
    try std.testing.expect(std.mem.startsWith(u8, run_response, "RESP 39 "));
    try std.testing.expect(std.mem.indexOf(u8, run_response, "pkg-service-ok\n") != null);

    const display = display_output.statePtr();
    try std.testing.expectEqual(@as(u16, 1280), display.current_width);
    try std.testing.expectEqual(@as(u16, 720), display.current_height);

    const readback = try filesystem.readFileAlloc(std.testing.allocator, "/pkg/out/result.txt", 64);
    defer std.testing.allocator.free(readback);
    try std.testing.expectEqualStrings("pkg-service-data", readback);

    const package_dir_response = try handleFramedRequest(std.testing.allocator, "REQ 40 LIST /packages/demo", 512, 256, 512);
    defer std.testing.allocator.free(package_dir_response);
    const package_dir_listing = try filesystem.listDirectoryAlloc(std.testing.allocator, "/packages/demo", 128);
    defer std.testing.allocator.free(package_dir_listing);
    const expected_package_dir_response = try std.fmt.allocPrint(std.testing.allocator, "RESP 40 {d}\n{s}", .{ package_dir_listing.len, package_dir_listing });
    defer std.testing.allocator.free(expected_package_dir_response);
    try std.testing.expectEqualStrings(expected_package_dir_response, package_dir_response);
}

test "baremetal tool service reports display info and supported modes" {
    resetPersistentStateForTest();

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 61 DISPLAYINFO", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 61 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "backend=bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "controller=bochs-bga") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "current=640x400") != null);

    const modes_response = try handleFramedRequest(std.testing.allocator, "REQ 62 DISPLAYMODES", 512, 256, 512);
    defer std.testing.allocator.free(modes_response);
    try std.testing.expect(std.mem.startsWith(u8, modes_response, "RESP 62 "));
    try std.testing.expect(std.mem.indexOf(u8, modes_response, "mode 0 640x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, modes_response, "mode 4 1280x1024") != null);

    const set_response = try handleFramedRequest(std.testing.allocator, "REQ 63 DISPLAYSET 800 600", 512, 256, 512);
    defer std.testing.allocator.free(set_response);
    try std.testing.expectEqualStrings("RESP 63 16\nDISPLAY 800x600\n", set_response);

    const updated_info = try handleFramedRequest(std.testing.allocator, "REQ 64 DISPLAYINFO", 512, 256, 512);
    defer std.testing.allocator.free(updated_info);
    try std.testing.expect(std.mem.indexOf(u8, updated_info, "current=800x600") != null);
}

test "baremetal tool service rotates queries and deletes trust bundles" {
    resetPersistentStateForTest();

    const install_response = try handleFramedRequest(std.testing.allocator, "REQ 41 TRUSTPUT fs55-root 9\nroot-cert", 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expect(std.mem.startsWith(u8, install_response, "RESP 41 "));
    try std.testing.expect(std.mem.indexOf(u8, install_response, "TRUSTED fs55-root -> /runtime/trust/bundles/fs55-root.der\n") != null);

    const install_backup_response = try handleFramedRequest(std.testing.allocator, "REQ 42 TRUSTPUT fs55-backup 11\nbackup-cert", 512, 256, 512);
    defer std.testing.allocator.free(install_backup_response);
    try std.testing.expect(std.mem.startsWith(u8, install_backup_response, "RESP 42 "));
    try std.testing.expect(std.mem.indexOf(u8, install_backup_response, "TRUSTED fs55-backup -> /runtime/trust/bundles/fs55-backup.der\n") != null);

    const list_response = try handleFramedRequest(std.testing.allocator, "REQ 43 TRUSTLIST", 512, 256, 512);
    defer std.testing.allocator.free(list_response);
    try std.testing.expectEqualStrings("RESP 43 22\nfs55-root\nfs55-backup\n", list_response);

    const info_response = try handleFramedRequest(std.testing.allocator, "REQ 44 TRUSTINFO fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(info_response);
    try std.testing.expect(std.mem.startsWith(u8, info_response, "RESP 44 "));
    try std.testing.expect(std.mem.indexOf(u8, info_response, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, info_response, "selected=0") != null);

    const select_response = try handleFramedRequest(std.testing.allocator, "REQ 45 TRUSTSELECT fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(select_response);
    try std.testing.expectEqualStrings("RESP 45 19\nSELECTED fs55-root\n", select_response);

    const active_response = try handleFramedRequest(std.testing.allocator, "REQ 46 TRUSTACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(active_response);
    try std.testing.expect(std.mem.startsWith(u8, active_response, "RESP 46 "));
    try std.testing.expect(std.mem.indexOf(u8, active_response, "name=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, active_response, "selected=1") != null);

    const rotate_response = try handleFramedRequest(std.testing.allocator, "REQ 47 TRUSTSELECT fs55-backup", 512, 256, 512);
    defer std.testing.allocator.free(rotate_response);
    try std.testing.expectEqualStrings("RESP 47 21\nSELECTED fs55-backup\n", rotate_response);

    const delete_response = try handleFramedRequest(std.testing.allocator, "REQ 48 TRUSTDELETE fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(delete_response);
    try std.testing.expectEqualStrings("RESP 48 18\nDELETED fs55-root\n", delete_response);

    const remaining_list_response = try handleFramedRequest(std.testing.allocator, "REQ 49 TRUSTLIST", 512, 256, 512);
    defer std.testing.allocator.free(remaining_list_response);
    try std.testing.expectEqualStrings("RESP 49 12\nfs55-backup\n", remaining_list_response);

    const selected_info_response = try handleFramedRequest(std.testing.allocator, "REQ 50 TRUSTACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(selected_info_response);
    try std.testing.expect(std.mem.indexOf(u8, selected_info_response, "name=fs55-backup") != null);
    try std.testing.expect(std.mem.indexOf(u8, selected_info_response, "selected=1") != null);
}

test "baremetal tool service configures and runs app lifecycle requests" {
    resetPersistentStateForTest();

    try trust_store.installBundle("fs55-root", "root-cert", 0);
    try package_store.installScriptPackage("demo", "mkdir /pkg/out\nwrite-file /pkg/out/app.txt app-service-data\necho app-service-ok", 1);

    const app_list_response = try handleFramedRequest(std.testing.allocator, "REQ 51 APPLIST", 512, 256, 512);
    defer std.testing.allocator.free(app_list_response);
    try std.testing.expectEqualStrings("RESP 51 5\ndemo\n", app_list_response);

    const app_connector_response = try handleFramedRequest(std.testing.allocator, "REQ 52 APPCONNECTOR demo virtual", 512, 256, 512);
    defer std.testing.allocator.free(app_connector_response);
    try std.testing.expectEqualStrings("RESP 52 26\nAPPCONNECTOR demo virtual\n", app_connector_response);

    const app_trust_response = try handleFramedRequest(std.testing.allocator, "REQ 53 APPTRUST demo fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(app_trust_response);
    try std.testing.expectEqualStrings("RESP 53 24\nAPPTRUST demo fs55-root\n", app_trust_response);

    const app_info_response = try handleFramedRequest(std.testing.allocator, "REQ 54 APPINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(app_info_response);
    try std.testing.expect(std.mem.startsWith(u8, app_info_response, "RESP 54 "));
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "trust_bundle=fs55-root") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_info_response, "state_path=/runtime/apps/demo/last_run.txt") != null);

    const app_run_response = try handleFramedRequest(std.testing.allocator, "REQ 55 APPRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(app_run_response);
    try std.testing.expect(std.mem.startsWith(u8, app_run_response, "RESP 55 "));
    try std.testing.expect(std.mem.indexOf(u8, app_run_response, "app-service-ok\n") != null);

    const app_state_response = try handleFramedRequest(std.testing.allocator, "REQ 56 APPSTATE demo", 512, 256, 512);
    defer std.testing.allocator.free(app_state_response);
    try std.testing.expect(std.mem.startsWith(u8, app_state_response, "RESP 56 "));
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "exit_code=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "requested_connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "actual_connector=virtual") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_state_response, "trust_bundle=fs55-root") != null);
}

test "baremetal tool service handles batched trust requests" {
    resetPersistentStateForTest();

    const batch_request =
        "REQ 51 TRUSTPUT fs55-root 9\nroot-cert\nREQ 52 TRUSTPUT fs55-backup 11\nbackup-cert\nREQ 53 TRUSTSELECT fs55-backup\nREQ 54 TRUSTACTIVE\nREQ 55 TRUSTDELETE fs55-root\nREQ 56 TRUSTLIST";
    const batch_response = try handleFramedRequestBatch(std.testing.allocator, batch_request, 512, 256, 768);
    defer std.testing.allocator.free(batch_response);

    const expected_install = try handleFramedRequest(std.testing.allocator, "REQ 51 TRUSTPUT fs55-root 9\nroot-cert", 512, 256, 512);
    defer std.testing.allocator.free(expected_install);
    const expected_install_backup = try handleFramedRequest(std.testing.allocator, "REQ 52 TRUSTPUT fs55-backup 11\nbackup-cert", 512, 256, 512);
    defer std.testing.allocator.free(expected_install_backup);
    const expected_select = try handleFramedRequest(std.testing.allocator, "REQ 53 TRUSTSELECT fs55-backup", 512, 256, 512);
    defer std.testing.allocator.free(expected_select);
    const expected_active = try handleFramedRequest(std.testing.allocator, "REQ 54 TRUSTACTIVE", 512, 256, 512);
    defer std.testing.allocator.free(expected_active);
    const expected_delete = try handleFramedRequest(std.testing.allocator, "REQ 55 TRUSTDELETE fs55-root", 512, 256, 512);
    defer std.testing.allocator.free(expected_delete);
    const expected_list = try handleFramedRequest(std.testing.allocator, "REQ 56 TRUSTLIST", 512, 256, 512);
    defer std.testing.allocator.free(expected_list);
    const expected = try std.mem.concat(std.testing.allocator, u8, &.{ expected_install, expected_install_backup, expected_select, expected_active, expected_delete, expected_list });
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, batch_response);
}

test "baremetal tool service installs default runtime layout and returns manifest" {
    resetPersistentStateForTest();

    const install_response = try handleFramedRequest(std.testing.allocator, "REQ 34 INSTALL", 512, 256, 512);
    defer std.testing.allocator.free(install_response);
    try std.testing.expectEqualStrings("RESP 34 40\nINSTALLED /runtime/install/manifest.txt\n", install_response);

    var manifest_buf: [192]u8 = undefined;
    const expected_manifest = try disk_installer.installManifestForCurrentBackend(manifest_buf[0..]);
    const manifest_response = try handleFramedRequest(std.testing.allocator, "REQ 35 MANIFEST", 512, 256, 512);
    defer std.testing.allocator.free(manifest_response);
    const expected_response = try std.fmt.allocPrint(std.testing.allocator, "RESP 35 {d}\n{s}", .{ expected_manifest.len, expected_manifest });
    defer std.testing.allocator.free(expected_response);
    try std.testing.expectEqualStrings(expected_response, manifest_response);

    const loader_cfg = try filesystem.readFileAlloc(std.testing.allocator, disk_installer.loader_cfg_path, 160);
    defer std.testing.allocator.free(loader_cfg);
    try std.testing.expect(std.mem.indexOf(u8, loader_cfg, "default=bootstrap") != null);
}

test "baremetal tool service handles batched filesystem requests" {
    resetPersistentStateForTest();

    const batch_request = "REQ 11 PUT /tools/cache/tool.txt 4\nedge\nREQ 12 GET /tools/cache/tool.txt\nREQ 13 STAT /tools/cache/tool.txt";
    const batch_response = try handleFramedRequestBatch(std.testing.allocator, batch_request, 256, 256, 512);
    defer std.testing.allocator.free(batch_response);

    const expected_put = try handleFramedRequest(std.testing.allocator, "REQ 11 PUT /tools/cache/tool.txt 4\nedge", 256, 256, 256);
    defer std.testing.allocator.free(expected_put);
    const expected_get = try handleFramedRequest(std.testing.allocator, "REQ 12 GET /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(expected_get);
    const expected_stat = try handleFramedRequest(std.testing.allocator, "REQ 13 STAT /tools/cache/tool.txt", 256, 256, 256);
    defer std.testing.allocator.free(expected_stat);
    const expected = try std.mem.concat(std.testing.allocator, u8, &.{ expected_put, expected_get, expected_stat });
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, batch_response);
}

test "baremetal tool service handles batched package requests" {
    resetPersistentStateForTest();

    const script = "mkdir /pkg/out\nwrite-file /pkg/out/result.txt pkg-service-data\necho pkg-service-ok";
    const install_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 31 PKG demo {d}\n{s}", .{ script.len, script });
    defer std.testing.allocator.free(install_request);
    const asset_body = "{\"mode\":\"tcp\"}";
    const asset_request = try std.fmt.allocPrint(std.testing.allocator, "REQ 32 PKGPUT demo config/app.json {d}\n{s}", .{ asset_body.len, asset_body });
    defer std.testing.allocator.free(asset_request);
    const batch_request = try std.mem.concat(std.testing.allocator, u8, &.{
        install_request,
        "\n",
        asset_request,
        "\nREQ 33 PKGLS demo\nREQ 34 PKGGET demo config/app.json\nREQ 35 PKGLIST\nREQ 36 PKGINFO demo\nREQ 37 PKGAPP demo\nREQ 38 PKGDISPLAY demo 1280 720\nREQ 39 PKGRUN demo\nREQ 40 DISPLAYSET 800 600\nREQ 41 DISPLAYINFO\nREQ 42 DISPLAYMODES",
    });
    defer std.testing.allocator.free(batch_request);
    const batch_response = try handleFramedRequestBatch(std.testing.allocator, batch_request, 512, 256, 2048);
    defer std.testing.allocator.free(batch_response);

    const expected_install = try handleFramedRequest(std.testing.allocator, install_request, 512, 256, 512);
    defer std.testing.allocator.free(expected_install);
    const expected_asset = try handleFramedRequest(std.testing.allocator, asset_request, 512, 256, 512);
    defer std.testing.allocator.free(expected_asset);
    const expected_asset_list = try handleFramedRequest(std.testing.allocator, "REQ 33 PKGLS demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_asset_list);
    const expected_asset_get = try handleFramedRequest(std.testing.allocator, "REQ 34 PKGGET demo config/app.json", 512, 256, 512);
    defer std.testing.allocator.free(expected_asset_get);
    const expected_list = try handleFramedRequest(std.testing.allocator, "REQ 35 PKGLIST", 512, 256, 512);
    defer std.testing.allocator.free(expected_list);
    const expected_info = try handleFramedRequest(std.testing.allocator, "REQ 36 PKGINFO demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_info);
    const expected_app = try handleFramedRequest(std.testing.allocator, "REQ 37 PKGAPP demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_app);
    const expected_pkg_display = try handleFramedRequest(std.testing.allocator, "REQ 38 PKGDISPLAY demo 1280 720", 512, 256, 512);
    defer std.testing.allocator.free(expected_pkg_display);
    const expected_run = try handleFramedRequest(std.testing.allocator, "REQ 39 PKGRUN demo", 512, 256, 512);
    defer std.testing.allocator.free(expected_run);
    const expected_display_set = try handleFramedRequest(std.testing.allocator, "REQ 40 DISPLAYSET 800 600", 512, 256, 512);
    defer std.testing.allocator.free(expected_display_set);
    const expected_display_info = try handleFramedRequest(std.testing.allocator, "REQ 41 DISPLAYINFO", 512, 256, 512);
    defer std.testing.allocator.free(expected_display_info);
    const expected_display_modes = try handleFramedRequest(std.testing.allocator, "REQ 42 DISPLAYMODES", 512, 256, 512);
    defer std.testing.allocator.free(expected_display_modes);
    const expected = try std.mem.concat(std.testing.allocator, u8, &.{ expected_install, expected_asset, expected_asset_list, expected_asset_get, expected_list, expected_info, expected_app, expected_pkg_display, expected_run, expected_display_set, expected_display_info, expected_display_modes });
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualStrings(expected, batch_response);
}

test "baremetal tool service rejects invalid mid-batch frames" {
    resetPersistentStateForTest();
    try filesystem.createDirPath("/tools/cache");
    try filesystem.writeFile("/tools/cache/tool.txt", "edge", 0);

    try std.testing.expectError(
        error.InvalidFrame,
        handleFramedRequestBatch(
            std.testing.allocator,
            "REQ 11 GET /tools/cache/tool.txt\nREQ nope GET /tools/cache/tool.txt",
            256,
            256,
            512,
        ),
    );
}

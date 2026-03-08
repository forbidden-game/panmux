const std = @import("std");

pub const Params = struct {
    title: ?[]const u8 = null,
    body: ?[]const u8 = null,
    state: ?[]const u8 = null,
    tab_index: ?u32 = null,
    tab_id: ?[]const u8 = null,
    surface_id: ?[]const u8 = null,
};

pub const Request = struct {
    method: []const u8,
    params: Params = .{},
};

pub const TabInfo = struct {
    index: u32,
    title: []const u8,
    cwd: ?[]const u8 = null,
    state: ?[]const u8 = null,
    tab_id: []const u8,
    surface_id: ?[]const u8 = null,
    selected: bool,
    needs_attention: bool,
    loading: bool,
};

pub const Response = struct {
    ok: bool,
    @"error": ?[]const u8 = null,
    tabs: ?[]const TabInfo = null,
};

pub const json_opts: std.json.Stringify.Options = .{
    .whitespace = .minified,
};

pub const OwnedParams = struct {
    title: ?[:0]u8 = null,
    body: ?[:0]u8 = null,
    state: ?[:0]u8 = null,
    tab_index: ?u32 = null,
    tab_id: ?[:0]u8 = null,
    surface_id: ?[:0]u8 = null,

    pub fn clone(alloc: std.mem.Allocator, params: Params) !OwnedParams {
        var result: OwnedParams = .{ .tab_index = params.tab_index };
        errdefer result.deinit(alloc);

        if (params.title) |value| result.title = try alloc.dupeZ(u8, value);
        if (params.body) |value| result.body = try alloc.dupeZ(u8, value);
        if (params.state) |value| result.state = try alloc.dupeZ(u8, value);
        if (params.tab_id) |value| result.tab_id = try alloc.dupeZ(u8, value);
        if (params.surface_id) |value| result.surface_id = try alloc.dupeZ(u8, value);

        return result;
    }

    pub fn deinit(self: *OwnedParams, alloc: std.mem.Allocator) void {
        if (self.title) |value| alloc.free(value);
        if (self.body) |value| alloc.free(value);
        if (self.state) |value| alloc.free(value);
        if (self.tab_id) |value| alloc.free(value);
        if (self.surface_id) |value| alloc.free(value);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedParams) Params {
        return .{
            .title = if (self.title) |value| value else null,
            .body = if (self.body) |value| value else null,
            .state = if (self.state) |value| value else null,
            .tab_index = self.tab_index,
            .tab_id = if (self.tab_id) |value| value else null,
            .surface_id = if (self.surface_id) |value| value else null,
        };
    }
};

pub const OwnedRequest = struct {
    method: [:0]u8,
    params: OwnedParams,

    pub fn clone(alloc: std.mem.Allocator, request: Request) !OwnedRequest {
        return .{
            .method = try alloc.dupeZ(u8, request.method),
            .params = try OwnedParams.clone(alloc, request.params),
        };
    }

    pub fn deinit(self: *OwnedRequest, alloc: std.mem.Allocator) void {
        alloc.free(self.method);
        self.params.deinit(alloc);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedRequest) Request {
        return .{
            .method = self.method,
            .params = self.params.borrowed(),
        };
    }
};

pub const OwnedTabInfo = struct {
    index: u32,
    title: [:0]u8,
    cwd: ?[:0]u8 = null,
    state: ?[:0]u8 = null,
    tab_id: [:0]u8,
    surface_id: ?[:0]u8 = null,
    selected: bool,
    needs_attention: bool,
    loading: bool,

    pub fn clone(alloc: std.mem.Allocator, info: TabInfo) !OwnedTabInfo {
        var result: OwnedTabInfo = .{
            .index = info.index,
            .title = try alloc.dupeZ(u8, info.title),
            .tab_id = try alloc.dupeZ(u8, info.tab_id),
            .selected = info.selected,
            .needs_attention = info.needs_attention,
            .loading = info.loading,
        };
        errdefer result.deinit(alloc);

        if (info.cwd) |value| result.cwd = try alloc.dupeZ(u8, value);
        if (info.state) |value| result.state = try alloc.dupeZ(u8, value);
        if (info.surface_id) |value| result.surface_id = try alloc.dupeZ(u8, value);

        return result;
    }

    pub fn deinit(self: *OwnedTabInfo, alloc: std.mem.Allocator) void {
        alloc.free(self.title);
        if (self.cwd) |value| alloc.free(value);
        if (self.state) |value| alloc.free(value);
        alloc.free(self.tab_id);
        if (self.surface_id) |value| alloc.free(value);
        self.* = undefined;
    }
};

pub const OwnedResponse = struct {
    ok: bool,
    @"error": ?[:0]u8 = null,
    tabs: ?[]OwnedTabInfo = null,

    pub fn success() OwnedResponse {
        return .{ .ok = true };
    }

    pub fn failure(alloc: std.mem.Allocator, message: []const u8) !OwnedResponse {
        return .{
            .ok = false,
            .@"error" = try alloc.dupeZ(u8, message),
        };
    }

    pub fn deinit(self: *OwnedResponse, alloc: std.mem.Allocator) void {
        if (self.@"error") |value| alloc.free(value);
        if (self.tabs) |tabs| {
            for (tabs) |*tab| tab.deinit(alloc);
            alloc.free(tabs);
        }
        self.* = undefined;
    }
};

pub fn hasExplicitTarget(params: Params) bool {
    return params.tab_index != null or params.tab_id != null or params.surface_id != null;
}

pub fn parseRequestLeaky(alloc: std.mem.Allocator, line: []const u8) !Request {
    return try std.json.parseFromSliceLeaky(
        Request,
        alloc,
        line,
        .{ .allocate = .alloc_if_needed, .ignore_unknown_fields = true },
    );
}

pub fn writeRequest(writer: *std.Io.Writer, request: Request) !void {
    try writer.print("{f}\n", .{std.json.fmt(request, json_opts)});
}

pub fn writeResponse(writer: *std.Io.Writer, response: Response) !void {
    try writer.print("{f}\n", .{std.json.fmt(response, json_opts)});
}

pub fn writeOwnedResponse(writer: *std.Io.Writer, response: OwnedResponse) !void {
    try writer.print("{f}\n", .{std.json.fmt(response, json_opts)});
}

const std = @import("std");
const types = @import("types.zig");
const http = std.http;
const json = std.json;
const Allocator = std.mem.Allocator;

const AgentConfig = types.AgentConfig;

pub const NetworkClient = struct {
    allocator: Allocator,
    config: AgentConfig,
    client: http.Client,
    
    pub fn init(allocator: Allocator, config: AgentConfig) NetworkClient {
        return NetworkClient{
            .allocator = allocator,
            .config = config,
            .client = http.Client{ .allocator = allocator },
        };
    }
    
    pub fn deinit(self: *NetworkClient) void {
        self.client.deinit();
    }
    
    pub fn sendRequest(self: *NetworkClient, endpoint: []const u8, data: []const u8) ![]const u8 {
        const uri_str = try std.fmt.allocPrint(self.allocator, "http://{s}:{d}/{s}", .{ self.config.callback_host, self.config.callback_port, endpoint });
        defer self.allocator.free(uri_str);
        
        const uri = std.Uri.parse(uri_str) catch return error.InvalidUri;
        
        var header_buffer: [1024]u8 = undefined;
        var req = self.client.open(.POST, uri, .{
            .server_header_buffer = &header_buffer,
            .extra_headers = &.{
                .{ .name = "user-agent", .value = self.config.user_agent },
                .{ .name = "content-type", .value = "application/json" },
            },
        }) catch return error.RequestFailed;
        defer req.deinit();
        
        req.transfer_encoding = .{ .content_length = data.len };
        try req.send();
        try req.writeAll(data);
        try req.finish();
        try req.wait();
        
        const body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        return body;
    }
};

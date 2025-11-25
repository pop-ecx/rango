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
        const uri_str = try std.fmt.allocPrint(self.allocator, "{s}:{d}/{s}", .{ self.config.callback_host, self.config.callback_port, endpoint });
        defer self.allocator.free(uri_str);

        const extra_headers = &[_]http.Header{
            .{ .name = "user-agent", .value = self.config.user_agent },
            .{ .name = "content-type", .value = "application/json" },
        };

        var response_body = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_body.deinit();

        _ = try self.client.fetch(.{
            .method = .POST,
            .location = .{ .url = uri_str },
            .extra_headers = extra_headers,
            .payload = data,
            .response_writer = &response_body.writer,
        });

        return try response_body.toOwnedSlice();
    }
};

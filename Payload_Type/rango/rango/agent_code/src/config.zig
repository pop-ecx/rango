
const types = @import("types.zig");

pub const uuid: []const u8 = "e35485e7-cd4c-4d5c-b465-6cc77623b16e";
pub const payload_uuid: []const u8 = "e35485e7-cd4c-4d5c-b465-6cc77623b16e";
pub const agentConfig: types.AgentConfig = .{
    .callback_host = "http://127.0.0.1",
    .callback_port = 80,
    .user_agent = "",
    .sleep_interval = 10,
    .jitter = 23.0,
    .kill_date = null,
};

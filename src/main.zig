// required software
// Windows, Linux, macOS etc.: curl, tar

// https://techcommunity.microsoft.com/t5/containers/tar-and-curl-come-to-windows/ba-p/382409
// https://github.com/libarchive/libarchive/wiki/LibarchiveFormats

// location of zig directory
// Windows: c:\zig
// others (Linux, etc.): ~/bin/zig

// only tested on Windows and macOS

const builtin = @import("builtin");
const std = @import("std");
const ChildProcess = std.ChildProcess;
const fs = std.fs;
const print = std.debug.print;

const home_env = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
const ext = if (builtin.os.tag == .windows) ".zip" else ".tar.xz";

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // Change directory to ~/Downloads
    const home = try std.process.getEnvVarOwned(arena, home_env);
    const current_dir_path = try fs.path.join(arena, &[_][]const u8{ home, "Downloads" });
    try std.os.chdir(current_dir_path);

    // Download index.json
    const curl_json = [_][]const u8{ "curl", "-OL", "https://ziglang.org/download/index.json" };
    _ = try ChildProcess.exec(.{ .allocator = arena, .argv = &curl_json });

    // load index.json
    const json_path = try fs.path.join(arena, &[_][]const u8{ current_dir_path, "index.json" });
    const file = try fs.cwd().readFileAlloc(arena, json_path, std.math.maxInt(usize));

    const json_platform = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag);

    // parse index.json to get URL
    var parsed = try std.json.parseFromSlice(std.json.Value, arena, file, .{});
    const url =
        parsed.value.object.get("master").?.object.get(json_platform).?.object.get("tarball").?.string;

    print("url: {s}\n", .{url});

    // download file (.zip or .tar.xz)
    const curl_zig = [_][]const u8{ "curl", "-OL", url };
    _ = try ChildProcess.exec(.{ .allocator = arena, .argv = &curl_zig });

    // get file name from url
    const uri = try std.Uri.parse(url);
    const filename = fs.path.basename(uri.path);
    print("filename: {s}\n", .{filename});

    // unarchive the file
    const extraction = [_][]const u8{ "tar", "xf", filename };
    const ret = try ChildProcess.exec(.{ .allocator = arena, .argv = &extraction });
    print("{s}\n", .{ret.stdout});

    // Remove extension (.zip or .tar.xz) from file name
    var iter_fn = std.mem.splitSequence(u8, filename, ext);
    const filename_without_ext = iter_fn.next().?;

    // determine the destination path
    const new_path = if (builtin.os.tag == .windows) "C:\\zig" else try fs.path.join(arena, &[_][]const u8{ home, "bin", "zig" });

    // delete zig directory if it already exists
    try fs.cwd().deleteTree(new_path);

    // move zig directory
    try std.os.rename(filename_without_ext, new_path);
}

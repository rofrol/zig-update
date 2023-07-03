// required software
// Windows: curl, tar
// others (Linux, etc.): curl, tar

// location of zig directory
// Windows: c:\zig
// others (Linux, etc.): ~/bin/zig

// only tested on Windows

const builtin = @import("builtin");
const std = @import("std");
const ChildProcess = std.ChildProcess;
const fs = std.fs;
const json = std.json;
const math = std.math;
const mem = std.mem;
const os = std.os;
const print = std.debug.print;
const process = std.process;

const home_env = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
const os_tag = if (builtin.os.tag == .windows) "x86_64-windows" else "x86_64-linux";
const ext = if (builtin.os.tag == .windows) ".zip" else ".tar.xz";

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // Change directory to ~/Downloads
    const home = try process.getEnvVarOwned(arena, home_env);
    const current_dir_path = try fs.path.join(arena, &[_][]const u8{ home, "Downloads" });
    try os.chdir(current_dir_path);

    // Download index.json
    const curl_json = [_][]const u8{ "curl", "-OL", "https://ziglang.org/download/index.json" };
    _ = try ChildProcess.exec(.{ .allocator = arena, .argv = &curl_json });

    // load index.json
    const json_path = try fs.path.join(arena, &[_][]const u8{ current_dir_path, "index.json" });
    const file = try fs.cwd().readFileAlloc(arena, json_path, math.maxInt(usize));

    // parse index.json to get URL
    var parsed = try json.parseFromSlice(json.Value, arena, file, .{});
    const url =
        parsed.value.object.get("master").?.object.get(os_tag).?.object.get("tarball").?.string;

    // download file (.zip or .tar.xz)
    const curl_zig = [_][]const u8{ "curl", "-OL", url };
    _ = try ChildProcess.exec(.{ .allocator = arena, .argv = &curl_zig });

    // get file name from url
    var iter = mem.splitBackwardsScalar(u8, url, '/');
    const filename = iter.next().?;

    // unarchive the file
    // https://techcommunity.microsoft.com/t5/containers/tar-and-curl-come-to-windows/ba-p/382409
    // https://github.com/libarchive/libarchive/wiki/LibarchiveFormats
    const extraction = [_][]const u8{ "tar", "xf", filename };
    const ret = try ChildProcess.exec(.{ .allocator = arena, .argv = &extraction });
    print("{s}\n", .{ret.stdout});

    // Remove extension (.zip or .tar.xz) from file name
    var iter_fn = std.mem.splitSequence(u8, filename, ext);
    const filename_without_ext = iter_fn.next().?;

    // determine the destination path
    const new_path = if (builtin.os.tag == .windows) blk: {
        break :blk "C:\\zig";
    } else blk: {
        const path = try fs.path.join(arena, &[_][]const u8{ home, "bin", "zig" });
        break :blk path;
    };

    // delete zig directory if it already exists
    try fs.cwd().deleteTree(new_path);

    // move zig directory
    try os.rename(filename_without_ext, new_path);
}

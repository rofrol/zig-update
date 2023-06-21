// zig build-exe -Doptimize=ReleaseFast zig_update.zig

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
const seven_zip = if (builtin.os.tag == .windows) "7za" else "7z";
const ext = if (builtin.os.tag == .windows) ".zip" else ".tar.xz";

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // ディレクトリを~/Downloadsに変更
    const home = try process.getEnvVarOwned(arena, home_env);
    const current_dir_path = try fs.path.join(arena, &[_][]const u8{ home, "Downloads" });
    try os.chdir(current_dir_path);

    // index.jsonをダウンロード
    const curl_json = [_][]const u8{ "curl", "-OL", "https://ziglang.org/download/index.json" };
    _ = try ChildProcess.exec(.{ .allocator = arena, .argv = &curl_json });

    // index.jsonを読み込む
    const json_path = try fs.path.join(arena, &[_][]const u8{ current_dir_path, "index.json" });
    const file = try fs.cwd().readFileAlloc(arena, json_path, math.maxInt(usize));

    // index.jsonをパースしてURLを取得
    var parsed = try json.parseFromSlice(json.Value, arena, file, .{});
    defer parsed.deinit();
    const url =
        parsed.value.object.get("master").?.object.get(os_tag).?.object.get("tarball").?.string;

    // ファイル(.zip or .tar.xz)をダウンロード
    const curl_zig = [_][]const u8{ "curl", "-OL", url };
    _ = try ChildProcess.exec(.{ .allocator = arena, .argv = &curl_zig });

    // URLからファイル名を取得
    var iter = mem.splitBackwardsScalar(u8, url, '/');
    const filename = iter.next().?;

    // ファイルを解凍
    // https://qiita.com/h_pon_heapon/items/d7f7d38d11bfe15eebf8
    const extraction = [_][]const u8{ seven_zip, "x", "-aoa", filename };
    const ret = try ChildProcess.exec(.{ .allocator = arena, .argv = &extraction });
    print("{s}\n", .{ret.stdout});

    // ファイル名から拡張子(.zip or .tar.xz)を除去
    var iter_fn = std.mem.splitSequence(u8, filename, ext);
    const filename_without_ext = iter_fn.next().?;

    // 移動先のパスを決定
    const new_path = if (builtin.os.tag == .windows) blk: {
        break :blk "C:\\zig";
    } else blk: {
        const path = try fs.path.join(arena, &[_][]const u8{ home, "bin", "zig" });
        break :blk path;
    };

    // 既にzigディレクトリが存在すれば削除
    try fs.cwd().deleteTree(new_path);

    // zigディレクトリを移動する
    try os.rename(filename_without_ext, new_path);
}
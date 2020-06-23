const std = @import("std");
const time = std.time;
const Timer = time.Timer;

const smaz = @import("main.zig");
const examples = @import("examples.zig").examples;

const KiB = 1024;
const MiB = 1024 * KiB;

inline fn compress() !usize {
    const iterations = 10000;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        for (examples) |str| {
            var compress_reader = std.io.fixedBufferStream(str);
            var compress_writer = std.io.null_writer;

            try smaz.compress(compress_reader.reader(), compress_writer);
        }
    }

    var sum: usize = 0;
    for (examples) |str| sum += str.len;
    return sum * iterations;
}

inline fn decompress() !usize {
    var compress_buffers = [_][1024]u8{undefined} ** examples.len;
    var compressed = [_][]const u8{&[_]u8{}} ** examples.len;

    for (examples) |str, i| {
        var compress_reader = std.io.fixedBufferStream(str);
        var compress_writer = std.io.fixedBufferStream(&compress_buffers[i]);

        try smaz.compress(compress_reader.reader(), compress_writer.writer());

        compressed[i] = compress_writer.getWritten();
    }

    const iterations = 10000;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        for (compressed) |str| {
            var decompress_reader = std.io.fixedBufferStream(str);
            var decompress_writer = std.io.null_writer;

            try smaz.decompress(decompress_reader.reader(), decompress_writer);
        }
    }

    var sum: usize = 0;
    for (compressed) |str| sum += str.len;
    return sum * iterations;
}

fn benchmark(comptime f: fn () anyerror!usize) !u64 {
    var timer = try Timer.start();
    const start = timer.lap();
    const bytes = try f();
    const end = timer.read();

    const elapsed_s = @intToFloat(f64, end - start) / time.ns_per_s;
    const throughput = @floatToInt(u64, @intToFloat(f64, bytes) / elapsed_s);

    return throughput;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const throughput_compression = try benchmark(compress);
    const throughput_decompression = try benchmark(decompress);

    try stdout.print("compression throughput: {} KiB/s\n", .{throughput_compression / KiB});
    try stdout.print("decompression throughput: {} MiB/s\n", .{throughput_decompression / MiB});
}

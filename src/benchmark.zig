const std = @import("std");
const time = std.time;
const Io = std.Io;

const smaz = @import("smaz");
const examples = smaz.example_strings;

const KiB = 1024;
const MiB = 1024 * KiB;

fn compress() !usize {
    const iterations = 10000;

    var discarding_buf: [4096]u8 = undefined;

    for (0..iterations) |_| {
        for (examples) |str| {
            var compress_reader: Io.Reader = .fixed(str);
            var compress_writer: Io.Writer.Discarding = .init(&discarding_buf);

            try smaz.compress(&compress_reader, &compress_writer.writer);
        }
    }

    var sum: usize = 0;
    for (examples) |str| sum += str.len;
    return sum * iterations;
}

fn decompress() !usize {
    var compress_buffers = [_][1024]u8{undefined} ** examples.len;
    var compressed = [_][]const u8{&[_]u8{}} ** examples.len;

    for (examples, &compress_buffers, &compressed) |str, *buf, *out| {
        var compress_reader: Io.Reader = .fixed(str);
        var compress_writer: Io.Writer = .fixed(buf);

        try smaz.compress(&compress_reader, &compress_writer);

        out.* = compress_writer.buffered();
    }

    var discarding_buf: [4096]u8 = undefined;

    const iterations = 10000;
    for (0..iterations) |_| {
        for (compressed) |str| {
            var decompress_reader: Io.Reader = .fixed(str);
            var decompress_writer: Io.Writer.Discarding = .init(&discarding_buf);

            try smaz.decompress(&decompress_reader, &decompress_writer.writer);
        }
    }

    var sum: usize = 0;
    for (compressed) |str| sum += str.len;
    return sum * iterations;
}

fn benchmark(comptime f: fn () anyerror!usize, io: Io) !u64 {
    const start = Io.Timestamp.now(io, .real);
    const bytes = try f();
    const end = Io.Timestamp.now(io, .real);

    const elapsed_ns = start.durationTo(end).toNanoseconds();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / time.ns_per_s;
    const throughput: u64 = @intFromFloat(@as(f64, @floatFromInt(bytes)) / elapsed_s);

    std.debug.print("bytes: {}\n", .{bytes});
    return throughput;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);

    const throughput_compression = try benchmark(compress, io);
    const throughput_decompression = try benchmark(decompress, io);

    try stdout.interface.print("compression throughput: {} MiB/s\n", .{throughput_compression / MiB});
    try stdout.interface.print("decompression throughput: {} MiB/s\n", .{throughput_decompression / MiB});

    try stdout.interface.flush();
}

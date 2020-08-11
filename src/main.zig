const std = @import("std");
const ComptimeStringHashMap = @import("comptime_hash_map/comptime_hash_map.zig").ComptimeStringHashMap;
const testing = std.testing;

/// Reverse compression codebook, used for decompression
const smaz_rcb = [_][]const u8{
    " ",      "the",   "e",     "t",   "a",     "of",   "o",    "and",  "i",   "n",    "s",   "e ",      "r",   " th",
    " t",     "in",    "he",    "th",  "h",     "he ",  "to",   "\r\n", "l",   "s ",   "d",   " a",      "an",  "er",
    "c",      " o",    "d ",    "on",  " of",   "re",   "of ",  "t ",   ", ",  "is",   "u",   "at",      "   ", "n ",
    "or",     "which", "f",     "m",   "as",    "it",   "that", "\n",   "was", "en",   "  ",  " w",      "es",  " an",
    " i",     "\r",    "f ",    "g",   "p",     "nd",   " s",   "nd ",  "ed ", "w",    "ed",  "http://", "for", "te",
    "ing",    "y ",    "The",   " c",  "ti",    "r ",   "his",  "st",   " in", "ar",   "nt",  ",",       " to", "y",
    "ng",     " h",    "with",  "le",  "al",    "to ",  "b",    "ou",   "be",  "were", " b",  "se",      "o ",  "ent",
    "ha",     "ng ",   "their", "\"",  "hi",    "from", " f",   "in ",  "de",  "ion",  "me",  "v",       ".",   "ve",
    "all",    "re ",   "ri",    "ro",  "is ",   "co",   "f t",  "are",  "ea",  ". ",   "her", " m",      "er ", " p",
    "es ",    "by",    "they",  "di",  "ra",    "ic",   "not",  "s, ",  "d t", "at ",  "ce",  "la",      "h ",  "ne",
    "as ",    "tio",   "on ",   "n t", "io",    "we",   " a ",  "om",   ", a", "s o",  "ur",  "li",      "ll",  "ch",
    "had",    "this",  "e t",   "g ",  "e\r\n", " wh",  "ere",  " co",  "e o", "a ",   "us",  " d",      "ss",  "\n\r\n",
    "\r\n\r", "=\"",   " be",   " e",  "s a",   "ma",   "one",  "t t",  "or ", "but",  "el",  "so",      "l ",  "e s",
    "s,",     "no",    "ter",   " wa", "iv",    "ho",   "e a",  " r",   "hat", "s t",  "ns",  "ch ",     "wh",  "tr",
    "ut",     "/",     "have",  "ly ", "ta",    " ha",  " on",  "tha",  "-",   " l",   "ati", "en ",     "pe",  " re",
    "there",  "ass",   "si",    " fo", "wa",    "ec",   "our",  "who",  "its", "z",    "fo",  "rs",      ">",   "ot",
    "un",     "<",     "im",    "th ", "nc",    "ate",  "><",   "ver",  "ad",  " we",  "ly",  "ee",      " n",  "id",
    " cl",    "ac",    "il",    "</",  "rt",    " wi",  "div",  "e, ",  " it", "whi",  " ma", "ge",      "x",   "e c",
    "men",    ".com",
};

const smaz_cb_kvs = comptime blk: {
    const KV = struct {
        @"0": []const u8,
        @"1": u8,
    };
    var result: []const KV = &[_]KV{};
    for (smaz_rcb) |s, i| {
        result = result ++ &[_]KV{KV{ .@"0" = s, .@"1" = i }};
    }
    break :blk result;
};

const smaz_cb = comptime blk: {
    @setEvalBranchQuota(10000);
    break :blk ComptimeStringHashMap(u8, smaz_cb_kvs);
};

inline fn flushVerbatim(writer: anytype, verb: []const u8) !void {
    if (verb.len == 0) {
        return;
    } else if (verb.len == 1) {
        try writer.writeByte(254);
    } else {
        try writer.writeAll(&[_]u8{ 255, @intCast(u8, verb.len - 1) });
    }
    try writer.writeAll(verb);
}

pub fn compress(reader: anytype, writer: anytype) !void {
    var verb: [256]u8 = undefined;
    var verb_len: usize = 0;

    var buf: [7]u8 = undefined;
    var amt = try reader.read(&buf);
    while (amt > 0) {
        var len = amt;
        search: while (len > 0) : (len -= 1) {
            if (smaz_cb.get(buf[0..len])) |i| {
                // Match found, flush verbatim buffer
                try flushVerbatim(writer, verb[0..verb_len]);
                verb_len = 0;

                // Print
                try writer.writeByte(@intCast(u8, i.*));

                // Advance buffer
                std.mem.copy(u8, buf[0 .. amt - len], buf[len..amt]);
                amt -= len;
                break :search;
            }
        } else {
            if (verb_len < verb.len) {
                verb[verb_len] = buf[0];
                verb_len += 1;
            } else {
                try flushVerbatim(writer, &verb);
                verb[0] = buf[0];
                verb_len = 1;
            }

            std.mem.copy(u8, buf[0 .. amt - 1], buf[1..amt]);
            amt -= 1;
        }

        // Try to fill up buffer
        amt += try reader.read(buf[amt..]);
    }

    // Flush verbatim buffer
    try flushVerbatim(writer, verb[0..verb_len]);
}

pub fn decompress(reader: anytype, writer: anytype) !void {
    while (true) {
        const c = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };

        switch (c) {
            254 => {
                const byte = reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => |e| return e,
                };
                try writer.writeByte(byte);
            },
            255 => {
                var buf: [256]u8 = undefined;
                const b = reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => |e| return e,
                };
                const len = @intCast(usize, b) + 1;

                const amt = try reader.readAll(buf[0..len]);
                if (amt < len) return;

                try writer.writeAll(buf[0..len]);
            },
            else => try writer.writeAll(smaz_rcb[c]),
        }
    }
}

test "compress and decompress examples" {
    const strings = @import("examples.zig").examples;
    for (strings) |str| {
        var compress_reader = std.io.fixedBufferStream(str);
        var compress_buf: [1024]u8 = undefined;
        var compress_writer = std.io.fixedBufferStream(&compress_buf);

        try compress(compress_reader.reader(), compress_writer.writer());
        const compressed = compress_writer.getWritten();

        var decompress_reader = std.io.fixedBufferStream(compressed);
        var decompress_buf: [1024]u8 = undefined;
        var decompress_writer = std.io.fixedBufferStream(&decompress_buf);

        try decompress(decompress_reader.reader(), decompress_writer.writer());
        const decompressed = decompress_writer.getWritten();

        testing.expectEqualSlices(u8, str, decompressed);
    }
}

test "fuzzy testing" {
    var rand_buf: [8]u8 = undefined;
    try std.crypto.randomBytes(rand_buf[0..]);
    const seed = std.mem.readIntLittle(u64, rand_buf[0..8]);

    var r = std.rand.DefaultPrng.init(seed);

    const n = 1000;
    const max_len = 1000;
    var buf: [max_len]u8 = undefined;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const len = r.random.uintLessThan(usize, max_len);
        for (buf[0..len]) |*x| x.* = r.random.int(u8);
        const str = buf[0..len];

        var compress_reader = std.io.fixedBufferStream(str);
        var compress_buf: [4096]u8 = undefined;
        var compress_writer = std.io.fixedBufferStream(&compress_buf);

        try compress(compress_reader.reader(), compress_writer.writer());
        const compressed = compress_writer.getWritten();

        var decompress_reader = std.io.fixedBufferStream(compressed);
        var decompress_buf: [4096]u8 = undefined;
        var decompress_writer = std.io.fixedBufferStream(&decompress_buf);

        try decompress(decompress_reader.reader(), decompress_writer.writer());
        const decompressed = decompress_writer.getWritten();

        testing.expectEqualSlices(u8, str, decompressed);
    }
}

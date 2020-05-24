const std = @import("std");
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

const smaz_cb = [_][]const u8{""} ** 256;

pub fn flushVerbatim(out_stream: var, verb: []const u8) !void {
    if (verb.len == 0) {
        return;
    } else if (verb.len == 1) {
        try out_stream.writeByte(254);
    } else {
        try out_stream.writeAll(&[_]u8{ 255, @intCast(u8, verb.len - 1) });
    }
    try out_stream.writeAll(verb);
}

pub fn compress(in_stream: var, out_stream: var) !void {
    var verb: [256]u8 = undefined;
    var verb_len: usize = 0;

    var buf: [7]u8 = undefined;
    var amt = try in_stream.read(&buf);
    while (amt > 0) {
        search: for (smaz_rcb) |str, i| {
            if (amt >= str.len) {
                if (std.mem.eql(u8, buf[0..str.len], str)) {
                    // Match found, flush verbatim buffer
                    try flushVerbatim(out_stream, verb[0..verb_len]);
                    verb_len = 0;

                    // Print
                    try out_stream.writeByte(@intCast(u8, i));

                    // Advance buffer
                    std.mem.copy(u8, buf[0 .. amt - str.len], buf[str.len..amt]);
                    amt -= str.len;
                    break :search;
                }
            }
        } else {
            if (verb_len < verb.len) {
                verb[verb_len] = buf[0];
                verb_len += 1;
            } else {
                try flushVerbatim(out_stream, &verb);
                verb[0] = buf[0];
                verb_len = 1;
            }

            std.mem.copy(u8, buf[0 .. amt - 1], buf[1..amt]);
            amt -= 1;
        }

        // Try to fill up buffer
        amt += try in_stream.read(buf[amt..]);
    }

    // Flush verbatim buffer
    try flushVerbatim(out_stream, verb[0..verb_len]);
}

test "compress" {}

pub fn decompress(in_stream: var, out_stream: var) !void {
    while (true) {
        const c = in_stream.readByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };

        switch (c) {
            254 => {
                const byte = in_stream.readByte() catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => |e| return e,
                };
                try out_stream.writeByte(byte);
            },
            255 => {
                var buf: [256]u8 = undefined;
                const b = in_stream.readByte() catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => |e| return e,
                };
                const len = b + 1;

                const amt = try in_stream.readAll(buf[0..len]);
                if (amt < len) return;

                try out_stream.writeAll(buf[0..len]);
            },
            else => try out_stream.writeAll(smaz_rcb[c]),
        }
    }
}

test "decompress" {}

test "compress and decompress examples" {
    const strings = [_][]const u8{
        "This is a small string",
        "foobar",
        "the end",
        "not-a-g00d-Exampl333",
        "Smaz is a simple compression library",
        "Nothing is more difficult, and therefore more precious, than to be able to decide",
        "this is an example of what works very well with smaz",
        "1000 numbers 2000 will 10 20 30 compress very little",
        "and now a few italian sentences:",
        "Nel mezzo del cammin di nostra vita, mi ritrovai in una selva oscura",
        "Mi illumino di immenso",
        "L'autore di questa libreria vive in Sicilia",
        "try it against urls",
        "http://google.com",
        "http://programming.reddit.com",
        "http://github.com/antirez/smaz/tree/master",
        "/media/hdb1/music/Alben/The Bla",
    };

    for (strings) |str| {
        var compress_in_stream = std.io.fixedBufferStream(str);
        var compress_buf: [1024]u8 = undefined;
        var compress_out_stream = std.io.fixedBufferStream(&compress_buf);

        try compress(compress_in_stream.inStream(), compress_out_stream.outStream());
        const compressed = compress_out_stream.getWritten();

        var decompress_in_stream = std.io.fixedBufferStream(compressed);
        var decompress_buf: [1024]u8 = undefined;
        var decompress_out_stream = std.io.fixedBufferStream(&decompress_buf);

        try decompress(decompress_in_stream.inStream(), decompress_out_stream.outStream());
        const decompressed = decompress_out_stream.getWritten();

        testing.expectEqualSlices(u8, str, decompressed);
    }
}

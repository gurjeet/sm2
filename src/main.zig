const std = @import("std");
const eql = std.mem.eql;

const delimiter: u8 = '"';

const Skip = struct {
    fn whitespace(file: std.fs.File) !void {
        var buf: [1]u8 = [_]u8{0};
        while (true) {
            _ = try file.read(&buf);
            if (isWhitespace(buf[0])) break;
        }
    }

    fn until(file: std.fs.File, stopAt: u8) !void {
        var buf: [1]u8 = [_]u8{0};
        while (true) {
            _ = try file.read(&buf);
            if (buf[0] == stopAt) break;
        }
    }

    fn isWhitespace(byte: u8) bool {
        return byte == '\n' or byte == '\r' or byte == ' ';
    }
};

const String = struct {
    fn read(file: std.fs.File, allocator: std.mem.Allocator, stopAt: u8) ![]u8 {
        var buf: []u8 = try allocator.alloc(u8, 81);
        var bytebuf = [_]u8{0};
        var i: usize = 0;

        while (i < 80) {
            _ = try file.read(&bytebuf);
            if (bytebuf[0] == '\n' or bytebuf[0] == '\r' or bytebuf[0] == stopAt) break;
            buf[i] = bytebuf[0];
            i += 1;
        }
        buf[i] = 0;
        return buf;
    }
};

const Number = struct {
    fn read(comptime T: type, file: std.fs.File) !T {
        // Allocate space for 20 digits which holds 64 bit numbers.
        var buf = [_]u8{0} ** 20;
        var bytebuf = [_]u8{0};
        var i: usize = 0;

        while (true) {
            _ = try file.read(&bytebuf);
            if ((bytebuf[0] < '0' or bytebuf[0] > '9') and bytebuf[0] != '.' and bytebuf[0] != 'e') break;
            buf[i] = bytebuf[0];
            i += 1;
        }

        if (T == f64) {
            return try std.fmt.parseFloat(f64, buf[0..i]);
        }
        return try std.fmt.parseInt(T, buf[0..i], 10);
    }
};

// The amount of times a memory has been repeated.
// Reset to zero when falls below a threshold of 0.5 ("completely forgotten").
const Repetition = struct {
    const Type = u64;
};

// How well the memory was remembered (0 - not at all, 5 - perfectly)
const ResponseQuality = struct {
    const max = 5.0;
    const min = 0.0;

    const Type = f64;

    fn from(r: Type) Type {
        return std.math.max(std.math.min(max, r), min);
    }
};

const EFactor = struct {
    const Type = f64;
    const start: Type = 2.5;
    const minimum: Type = 1.3;

    fn next(ef: Type, q: ResponseQuality.Type) Type {
        const delta = ResponseQuality.max - q;
        return std.math.max(ef + (0.1 - delta * (0.08 + delta * 0.02)), minimum);
    }
};

const Question = struct {
    const Type = []const u8;
};

const Answer = struct {
    const Type = []const u8;
};

const MemoryUnit = struct {
    repetition: Repetition.Type,
    ef: EFactor.Type,
    question: Question.Type,
    answer: Answer.Type,

    last_practice: i64,
    offset: ?u64,

    fn new(question: Question.Type, answer: Answer.Type) @This() {
        return @This(){
            .repetition = 0,
            .ef = EFactor.start,
            .question = question,
            .answer = answer,
            .last_practice = 0,
            .offset = null,
        };
    }

    fn next(self: *@This(), q: ResponseQuality.Type) @This() {
        const has_forgotten = q < std.math.round(ResponseQuality.max / 2.0);
        return MemoryUnit{
            .repetition = if (has_forgotten) 0 else self.repetition + 1,
            .ef = EFactor.next(self.ef, q),
            .question = self.question,
            .answer = self.answer,
            .last_practice = self.last_practice,
            .offset = self.offset,
        };
    }

    fn nextInterval(self: *@This()) f64 {
        return switch (self.repetition) {
            0 => 0.0,
            1 => 1.0,
            2 => 6.0,
            else => 6 * std.math.pow(f64, self.ef, @intToFloat(f64, self.repetition) - 1),
        };
    }

    fn staleness(self: *@This()) f64 {
        const days_diff = @intToFloat(f64, std.time.timestamp() - self.last_practice) / 60.0 / 60.0 / 24.0;
        return self.nextInterval() - days_diff;
    }

    fn read(file: std.fs.File, allocator: std.mem.Allocator) !*@This(){
        const offset = try file.getPos();
        const last_practice = try Number.read(i64, file);
        const ef = try Number.read(f64, file);
        const repetition = try Number.read(u64, file);
        try Skip.until(file, '"');
        const question = try String.read(file, allocator, delimiter);
        try Skip.until(file, '"');
        const answer = try String.read(file, allocator, delimiter);
        try Skip.whitespace(file);

        var memory_unit: *MemoryUnit = try allocator.create(MemoryUnit);
        memory_unit.* = MemoryUnit{
            .repetition = repetition,
            .ef = ef,
            .question = question,
            .answer = answer,
            .last_practice = last_practice,
            .offset = offset,
        };
        return memory_unit;
    }
};

const PracticeSession = struct {
    file: std.fs.File,

    fn fromFile(file_path: []const u8) !PracticeSession {
        const file = try std.fs.cwd().openFile(file_path, .{ .mode = std.fs.File.OpenMode.read_write });

        return PracticeSession{
            .file = file,
        };
    }

    fn nextMemoryUnit(self: @This()) !*MemoryUnit {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        try self.file.seekTo(0);

        var mu_soonest: *MemoryUnit = try allocator.create(MemoryUnit);
        mu_soonest.* = MemoryUnit.new("ok", "no");
        mu_soonest.last_practice = 4294967295;


        while (MemoryUnit.read(self.file, allocator) catch null) |mu_next| {
            std.debug.print("{0any} {1any}\n", .{ mu_next.staleness(), mu_soonest.staleness() });
            if (mu_next.staleness() < mu_soonest.staleness()) {
              std.debug.print("a\n", .{ });
              mu_soonest.* = mu_next.*;
            }
        }


        return mu_soonest;
    }

    fn respond(self: @This(), memory_unit: *MemoryUnit, r: ResponseQuality.Type) !void {
        const next = memory_unit.next(r);
        if (memory_unit.offset) |offset| try self.file.seekTo(offset);
        try std.fmt.formatInt(std.time.timestamp(), 10, std.fmt.Case.upper, .{}, self.file.writer());
        try self.file.seekBy(1); // " "
        try std.fmt.formatFloatDecimal(next.ef, .{ .precision = 2 }, self.file.writer());
        try self.file.seekBy(1); // " "
        try std.fmt.formatInt(next.repetition, 10, std.fmt.Case.upper, .{ .width = 2, .fill = '0' }, self.file.writer());
    }
};

pub fn main() !void {
    const stdout = std.io.getStdOut();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    const arg1 = args.next();

    var practice_session: PracticeSession = undefined;

    if (arg1) |file_path| {
        practice_session = try PracticeSession.fromFile(file_path);
    } else {
        try stdout.writer().print("Usage: sr <filename> [-a|-n|-r]\n", .{});
        return;
    }

    const memory_unit = try practice_session.nextMemoryUnit();

    const arg2 = args.next();
    if (arg2) |flag| {
        if (memory_unit.staleness() >= 0.0) {
            if (eql(u8, flag, "-r")) {
                if (args.next()) |response_str| {
                    const response = try std.fmt.parseFloat(f64, response_str);
                    try practice_session.respond(memory_unit, ResponseQuality.from(response));
                }
            }
            if (eql(u8, flag, "-a")) {
                try stdout.writer().print("{0s}\n", .{memory_unit.answer});
            }
        }
        if (eql(u8, flag, "-n")) {
            try stdout.writer().print("{0d}\n", .{memory_unit.staleness()});
        }
    } else {
        if (memory_unit.staleness() <= 0) {
            try stdout.writer().print("{0s}\n", .{memory_unit.question});
        }
    }
}

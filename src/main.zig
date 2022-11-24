const std = @import("std");
const eql = std.mem.eql;

const Test = struct {
    inline fn isWhitespace(byte: u8) bool {
        return byte == '\n' or byte == '\r' or byte == ' ';
    }

    inline fn isQuote(byte: u8) bool {
        return byte == '"';
    }

    inline fn isNumber(byte: u8) bool {
        return (byte < '0' or byte > '9') and byte != '.' and byte != 'e';
    }
};

const File = struct {
    fn skipUntil(comptime stopAtFn: fn (u8) callconv(.Inline) bool, file: std.fs.File) !void {
        var byte: [1]u8 = .{0};
        while (true) {
            _ = try file.read(&byte);
            if (stopAtFn(byte[0])) break;
        }
    }

    fn readUntil(comptime stopAtFn: fn (u8) callconv(.Inline) bool, file: std.fs.File, buf: []u8) !usize {
        var byte: [1]u8 = .{0};
        var i: usize = 0;

        while (true) : (i += 1) {
            _ = try file.read(&byte);
            if (stopAtFn(byte[0])) break;
            buf[i] = byte[0];
        }

        return i;
    }
};

const Number = struct {
    fn read(comptime T: type, file: std.fs.File) !T {
        var buf: [20]u8 = .{0};

        const bytes_read = try File.readUntil(Test.isNumber, file, &buf);

        if (T == f64) {
            return try std.fmt.parseFloat(f64, buf[0..bytes_read]);
        }
        return try std.fmt.parseInt(T, buf[0..bytes_read], 10);
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

    fn next(self: @This(), q: ResponseQuality.Type) @This() {
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

    fn nextInterval(self: @This()) f64 {
        return switch (self.repetition) {
            0 => 0.0,
            1 => 1.0,
            2 => 6.0,
            else => 6 * std.math.pow(f64, self.ef, @intToFloat(f64, self.repetition) - 1),
        };
    }

    fn staleness(self: @This()) f64 {
        const delta = @intToFloat(f64, std.time.timestamp() - self.last_practice) / 60.0 / 60.0 / 24.0;
        return self.nextInterval() - delta;
    }

    fn read(file: std.fs.File, allocator: std.mem.Allocator) !@This() {
        const offset = try file.getPos();
        const last_practice = try Number.read(i64, file);
        const ef = try Number.read(f64, file);
        const repetition = try Number.read(u64, file);
        try File.skipUntil(Test.isQuote, file);

        var question = try allocator.alloc(u8, 80);
        try File.readUntil(Test.isQuote, file, question);
        try File.skipUntil(Test.isQuote, file);

        var answer = try allocator.alloc(u8, 80);
        try File.readUntil(Test.isQuote, file, answer);
        try File.skipUntil(Test.isWhitespace, file);

        return @This(){
            .repetition = repetition,
            .ef = ef,
            .question = question,
            .answer = answer,
            .last_practice = last_practice,
            .offset = offset,
        };
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

    fn nextMemoryUnit(self: @This()) !MemoryUnit {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        try self.file.seekTo(0);

        var mu_soonest: MemoryUnit = MemoryUnit.new("", "");
        mu_soonest.last_practice = 9223372036854775807;

        while (MemoryUnit.read(self.file, allocator) catch null) |mu_next| {
            if (mu_next.staleness() < mu_soonest.staleness()) mu_soonest = mu_next;
        }

        return mu_soonest;
    }

    fn respond(self: @This(), memory_unit: MemoryUnit, r: ResponseQuality.Type) !void {
        const next = memory_unit.next(r);
        if (memory_unit.offset) |offset| try self.file.seekTo(offset);
        try std.fmt.formatInt(std.time.timestamp(), 10, std.fmt.Case.upper, .{}, self.file.writer());
        try self.file.seekBy(1); // " " calculate via comptime?
        try std.fmt.formatFloatDecimal(next.ef, .{ .precision = 2 }, self.file.writer());
        try self.file.seekBy(1); // " " calculate via comptime?
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
        try stdout.writer().print("Usage: sr <filename> [-a|-f|-n|-r]\n", .{});
        return;
    }

    const memory_unit = try practice_session.nextMemoryUnit();

    const arg2 = args.next();
    if (arg2) |flag| {
        if (eql(u8, flag, "-r")) {
            if (args.next()) |response_str| {
                const response = try std.fmt.parseFloat(f64, response_str);
                try practice_session.respond(memory_unit, ResponseQuality.from(response));
            }
        }
        if (eql(u8, flag, "-a"))
            try stdout.writer().print("{0s}\n", .{memory_unit.answer});
        if (eql(u8, flag, "-n"))
            try stdout.writer().print("{0d}\n", .{memory_unit.staleness()});
        if (eql(u8, flag, "-f"))
            try stdout.writer().print("{0s}\n", .{memory_unit.question});
    } else {
        if (memory_unit.staleness() <= 0)
            try stdout.writer().print("{0s}\n", .{memory_unit.question});
    }
}

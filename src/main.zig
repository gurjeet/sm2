const std = @import("std");
const heap = std.heap;
const math = std.math;
const mem = std.mem;
const fs = std.fs;
const fmt = std.fmt;
const time = std.time;
const io = std.io;
const process = std.process;

const Test = struct {
    inline fn isWhitespace(byte: u8) bool {
        return byte == '\n' or byte == '\r' or byte == ' ';
    }

    inline fn isQuote(byte: u8) bool {
        return byte == '"';
    }

    inline fn isNotNumber(byte: u8) bool {
        return (byte < '0' or byte > '9') and byte != '.' and byte != 'e';
    }
};

const File = struct {
    fn skipUntil(comptime stopAtFn: fn (u8) callconv(.Inline) bool, file: fs.File) !void {
        var byte: [1]u8 = .{0};
        while (true) {
            _ = try file.read(&byte);
            if (stopAtFn(byte[0])) break;
        }
    }

    fn readUntil(comptime stopAtFn: fn (u8) callconv(.Inline) bool, file: fs.File, buf: []u8) !usize {
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
    fn read(comptime T: type, file: fs.File) !T {
        var buf: [20]u8 = undefined;

        const bytes_read = try File.readUntil(Test.isNotNumber, file, &buf);

        if (T == f64) {
            return try fmt.parseFloat(f64, buf[0..bytes_read]);
        }
        return try fmt.parseInt(T, buf[0..bytes_read], 10);
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
        return @max(@min(max, r), min);
    }
};

const EFactor = struct {
    const Type = f64;
    const start: Type = 2.5;
    const minimum: Type = 1.3;

    fn next(ef: Type, q: ResponseQuality.Type) Type {
        const delta = ResponseQuality.max - q;
        return @max(ef + (0.1 - delta * (0.08 + delta * 0.02)), minimum);
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
        const has_forgotten = q < @round(ResponseQuality.max / 2.0);
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
            else => 6 * math.pow(f64, self.ef, @intToFloat(f64, self.repetition) - 1),
        };
    }

    fn staleness(self: @This()) f64 {
        const delta = @intToFloat(f64, time.timestamp() - self.last_practice) / 60.0 / 60.0 / 24.0;
        return self.nextInterval() - delta;
    }

    fn read(file: fs.File, allocator: mem.Allocator) !@This() {
        const offset = try file.getPos();
        const last_practice = try Number.read(i64, file);
        const ef = try Number.read(f64, file);
        const repetition = try Number.read(u64, file);
        try File.skipUntil(Test.isQuote, file);

        var question = try allocator.alloc(u8, 80);
        _ = try File.readUntil(Test.isQuote, file, question);
        try File.skipUntil(Test.isQuote, file);

        var answer = try allocator.alloc(u8, 80);
        _ = try File.readUntil(Test.isQuote, file, answer);
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

    fn write(self: @This(), file: fs.File, onlyUpdateMeta: bool) !void {
        if (self.offset) |offset| try file.seekTo(offset);
        try fmt.formatInt(time.timestamp(), 10, fmt.Case.upper, .{}, file.writer());
        try file.writer().print(" ", .{});
        try fmt.formatFloatDecimal(self.ef, .{ .precision = 2 }, file.writer());
        try file.writer().print(" ", .{});
        try fmt.formatInt(self.repetition, 10, fmt.Case.upper, .{ .width = 2, .fill = '0' }, file.writer());
        try file.writer().print(" ", .{});

        if (onlyUpdateMeta) return;

        try file.writer().print(" ", .{});
        try file.writer().print("\"{0s}\" \"{1s}\"\n", .{ self.question, self.answer });
    }

};

const PracticeSession = struct {
    file: fs.File,

    fn fromFile(file_path: []const u8) !PracticeSession {
        const file = try fs.cwd().openFile(file_path, .{ .mode = fs.File.OpenMode.read_write });

        return PracticeSession{
            .file = file,
        };
    }

    fn nextMemoryUnit(self: @This(), allocator: mem.Allocator) !MemoryUnit {
        try self.file.seekTo(0);

        var mu_soonest: MemoryUnit = MemoryUnit.new("", "");
        mu_soonest.last_practice = 9223372036854775807;

        while (MemoryUnit.read(self.file, allocator) catch null) |mu_next| {
            if (mu_next.staleness() < mu_soonest.staleness()) mu_soonest = mu_next;
        }

        return mu_soonest;
    }

    fn newMemoryUnit(self: @This(), question: []const u8, answer: []const u8) !void {
        try self.file.seekFromEnd(0);
        try MemoryUnit.new(question, answer).write(self.file, false);
    }

    fn respond(self: @This(), memory_unit: MemoryUnit, r: ResponseQuality.Type) !void {
        try memory_unit.next(r).write(self.file, true);
    }
};

pub fn main() !void {
    const stdout = io.getStdOut();

    var bufferFba: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&bufferFba);
    const allocator = fba.allocator();

    var args = try process.argsWithAllocator(allocator);
    _ = args.next();
    const arg1 = args.next();

    var practice_session: PracticeSession = undefined;

    if (arg1) |file_path| {
        practice_session = try PracticeSession.fromFile(file_path);
    } else {
        try stdout.writer().print("Usage: sm2 <filename> [new|show|grade|until|next]\n", .{});
        return;
    }

    const memory_unit = try practice_session.nextMemoryUnit(allocator);

    const arg2 = args.next();
    if (arg2) |flag| {
        if (mem.eql(u8, flag, "grade")) {
            if (args.next()) |grade_str| {
                const grade = try fmt.parseFloat(f64, grade_str);
                try practice_session.respond(memory_unit, ResponseQuality.from(grade));
            }
        }
        if (mem.eql(u8, flag, "new")) {
            const question = args.next();
            const answer = args.next();
            if (question == null or answer == null) {
              try stdout.writer().print("Missing question or answer: sm2 <filename> new \"<question>\" \"<answer>\"\n", .{});
            } else {
              const q: []const u8 = mem.span(question.?);
              const a: []const u8 = mem.span(answer.?);
              try practice_session.newMemoryUnit(q, a);
            }
        }
        if (mem.eql(u8, flag, "show"))
            try stdout.writer().print("{0s}\n", .{memory_unit.answer});
        if (mem.eql(u8, flag, "until"))
            try stdout.writer().print("{0d}\n", .{memory_unit.staleness()});
        if (mem.eql(u8, flag, "next"))
            try stdout.writer().print("{0s}\n", .{memory_unit.question});
    } else {
        if (memory_unit.staleness() <= 0)
            try stdout.writer().print("{0s}\n", .{memory_unit.question});
    }
}

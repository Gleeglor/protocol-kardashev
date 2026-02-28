const std = @import("std");

// Pointers
test "pointers - single mutable pointer" {
    var x: i32 = 42;
    const ptr: *i32 = &x;
    ptr.* = 100;

    try std.testing.expectEqual(@as(i32, 100), x);
}

test "pointers - const pointer prevents modification" {
    const value: i32 = 777;
    const ptr: *const i32 = &value;

    try std.testing.expectEqual(@as(i32, 777), ptr.*);

    // ptr.* = 999;  // <- this would not compile
}

test "pointers - optional pointer" {
    var num: i32 = 123;
    var opt: ?*i32 = null;

    try std.testing.expect(opt == null);

    opt = &num;

    try std.testing.expect(opt != null);
    if (opt) |p| {
        try std.testing.expectEqual(@as(i32, 123), p.*);
    } else {
        try std.testing.expect(false); // should not reach here
    }
}

test "pointers - slice is fat pointer (ptr + len)" {
    const s: []const u8 = "zig";
    try std.testing.expectEqual(@as(usize, 3), s.len);
}

// String
test "string - compile-time - interpolation" {
    const name = "Alice";
    const greeting = "bla-" ++ name ++ "!"; // works → "bla-Alice!"

    try std.testing.expectEqualStrings("bla-Alice!", greeting);
}

test "string - runtime - formatting" {
    const allocator = std.heap.page_allocator; // or use arena / fixed buffer etc.
    const name = "Alice"; // pretend this came from runtime

    // Like "bla-" + name + "!"
    const greeting = try std.fmt.allocPrint(
        allocator,
        "bla-{s}!",
        .{name},
    );
    defer allocator.free(greeting);

    try std.testing.expectEqualStrings("bla-Alice!", greeting);
}

test "string - runtime - multiple parts" {
    const allocator = std.heap.page_allocator; // or use arena / fixed buffer etc.
    const name = "Alice"; // pretend this came from runtime

    const parts = [_][]const u8{ "bla-", name, "!" };
    const joined = try std.mem.concat(allocator, u8, &parts);
    defer allocator.free(joined);

    try std.testing.expectEqualStrings("bla-Alice!", joined);
}

test "string - runtime - from slice" {
    const allocator = std.heap.page_allocator; // or use arena / fixed buffer etc.
    const name = "Alice"; // pretend this came from runtime

    var list = std.ArrayList(u8).empty;
    defer list.deinit(allocator);

    try list.appendSlice(allocator, "bla-");
    try list.appendSlice(allocator, name);
    try list.append(allocator, '!');

    const result = try list.toOwnedSlice(allocator); // now you own it
    defer allocator.free(result);

    try std.testing.expectEqualStrings("bla-Alice!", result);
}

// Slices
test "slices - string literal is []const u8 slice" {
    const s: []const u8 = "hello";
    try std.testing.expectEqual(@as(usize, 5), s.len);
    try std.testing.expectEqualStrings("hello", s);
}

test "slices - slice from array" {
    var numbers = [_]i32{ 10, 20, 30, 40, 50 };
    const slice = numbers[1..4];

    try std.testing.expectEqual(@as(usize, 3), slice.len);
    try std.testing.expectEqual(@as(i32, 20), slice[0]);
    try std.testing.expectEqual(@as(i32, 30), slice[1]);
    try std.testing.expectEqual(@as(i32, 40), slice[2]);
}

test "slices - mutable slice modification" {
    var buffer: [10]u8 = undefined;
    var slice: []u8 = &buffer;

    @memcpy(slice[0..5], "Zig!!");
    try std.testing.expectEqualStrings("Zig!!", slice[0..5]);
}

// Allocation
test "allocation - basic alloc + free" {
    const allocator = std.heap.page_allocator;

    const mem = try allocator.alloc(u8, 32);
    defer allocator.free(mem);

    try std.testing.expectEqual(@as(usize, 32), mem.len);
}

test "allocation - ArrayList grows and contains correct data" {
    const allocator = std.heap.page_allocator;

    var list = std.ArrayList(u8).empty;
    defer list.deinit(allocator);

    try list.appendSlice(allocator, "Zig ");
    try list.append(allocator, 'i');
    try list.appendSlice(allocator, "s cool");

    try std.testing.expectEqualStrings("Zig is cool", list.items);
    try std.testing.expect(list.items.len > 0);
}

test "allocation - dupe creates independent copy" {
    const allocator = std.heap.page_allocator;

    const original = "test string";
    const copy = try allocator.dupe(u8, original);
    defer allocator.free(copy);

    try std.testing.expectEqualStrings(original, copy);
    try std.testing.expect(@intFromPtr(original.ptr) != @intFromPtr(copy.ptr));
}

// Errors
const CalcError = error{ DivisionByZero, TooSmall, NegativeResult };

fn safeDivide(a: i32, b: i32) CalcError!i32 {
    if (b == 0) return error.DivisionByZero;
    const result = @divTrunc(a, b);
    if (result < 0) return error.NegativeResult;
    if (a < 10) return error.TooSmall;
    return result;
}

test "errors - unions - safeDivide success case" {
    const result = try safeDivide(50, 5);
    try std.testing.expectEqual(@as(i32, 10), result);
}

test "errors - unions - safeDivide catches division by zero" {
    try std.testing.expectError(
        error.DivisionByZero,
        safeDivide(100, 0),
    );
}

test "errors - unions - safeDivide catches too small input" {
    try std.testing.expectError(
        error.TooSmall,
        safeDivide(7, 2),
    );
}

test "errors - unions - safeDivide catches negative result" {
    try std.testing.expectError(
        error.NegativeResult,
        safeDivide(5, -2),
    );
}

fn processData(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const copy = try allocator.alloc(u8, input.len);
    errdefer allocator.free(copy);

    @memcpy(copy, input);

    if (input.len < 8) return error.DataTooShort;

    return copy;
}

test "errors - errdefer - processData success path – returns owned memory" {
    const allocator = std.heap.page_allocator;

    const input = "Hello Zig!";
    const result = try processData(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(input, result);
}

test "errors - errdefer - processData failure path – errdefer frees allocation" {
    const allocator = std.heap.page_allocator;

    // We expect error, and no memory leak should be reported by GPA in debug mode
    try std.testing.expectError(
        error.DataTooShort,
        processData(allocator, "short"),
    );
}

const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello, world! {s} {s} {s}\n", .{ "bla", "blo", "ble" });
}

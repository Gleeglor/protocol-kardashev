const std = @import("std");

pub fn read_file(filename: []const u8) ![]u8 {
    const allocator = std.heap.page_allocator;
    const contents = try std.fs.cwd().readFileAlloc(allocator, filename, 10 * 1024 * 1024);

    return contents;
}

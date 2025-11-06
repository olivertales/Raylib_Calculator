const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const SCREEN_WIDTH = 500;
const SCREEN_HEIGHT = 100;

pub fn main() !void {
    ray.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "");
    defer ray.CloseWindow();

    ray.SetWindowPosition(0, 0);
    ray.SetExitKey(ray.KEY_Q);
    ray.SetTargetFPS(60);
    const text_pos: WindowPosition = .{ .x = 10, .y = 50 };
    const FONT_SIZE: c_int = 20;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var numbers_str = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    defer numbers_str.deinit(allocator);

    var operation_units = try std.ArrayList([]const u8).initCapacity(allocator, 20);
    defer operation_units.deinit(allocator);
    var typed_history: []const u8 = "";
    defer allocator.free(typed_history);
    var number_index: usize = 0;

    while (!ray.WindowShouldClose()) {
        if (ray.IsKeyPressed(ray.KEY_ENTER)) {
            if (number_index > typed_history.len)
                continue;

            try numbers_str.append(allocator, typed_history[number_index..]);
            var arena: std.heap.ArenaAllocator = .init(allocator);
            const arena_alloc = arena.allocator();
            defer arena.deinit();
            var sorted_numop: std.SinglyLinkedList = .{};
            const operations = operation_units.items;
            for (numbers_str.items, 0..) |str_num, idx| {
                const fmt_num = std.fmt.parseFloat(f64, str_num) catch @panic("Something went wrong on the parsing for int");
                const num_op = try arena_alloc.create(NumberOperation);
                num_op.num = fmt_num;
                num_op.node = .{};
                num_op.op = null;

                if (idx == operations.len) {
                    const last_op = operations[idx - 1][0];
                    if (last_op == '-' or last_op == '+') {
                        num_op.op = operations[idx - 1];
                        num_op.node = sorted_numop.first.?.*;
                        sorted_numop.prepend(&num_op.node);
                    } else {
                        var last_node = sorted_numop.first.?.findLast();
                        last_node.next = &num_op.node;
                    }
                    continue;
                }

                num_op.op = operations[idx];

                if (sorted_numop.first == null)
                    sorted_numop.first = &num_op.node
                else if (operations[idx][0] == '+' or operations[idx][0] == '-') {
                    num_op.node = sorted_numop.first.?.*;
                    sorted_numop.prepend(&num_op.node);
                } else {
                    var last_node = sorted_numop.first.?.findLast();
                    last_node.next = &num_op.node;
                }
            }

            const result = Calculate(allocator, &sorted_numop);
            typed_history = std.fmt.allocPrint(allocator, "{s} = {s}", .{ typed_history, result }) catch unreachable;
        } else if (ray.IsKeyPressed(ray.KEY_BACKSPACE)) {
            if (typed_history.len > 1)
                typed_history = typed_history[0 .. typed_history.len - 1]
            else
                typed_history = "";
        }
        const char_key = ray.GetCharPressed();
        var pressed_key: []const u8 = "";

        for (key_values) |kvalues| {
            if (char_key == kvalues.key) {
                pressed_key = kvalues.value;
                break;
            }
        }

        switch (char_key) {
            ray.KEY_Q => {},
            KEY_PLUS, KEY_MODULO, KEY_POWER, KEY_MULTIPLY, ray.KEY_MINUS, ray.KEY_SLASH => {
                if (number_index > typed_history.len)
                    continue;

                const numbers = typed_history[number_index..];
                typed_history = std.fmt.allocPrint(allocator, "{s}{s}", .{ typed_history, pressed_key }) catch unreachable;
                try numbers_str.append(allocator, numbers);
                try operation_units.append(allocator, pressed_key);
                number_index = typed_history.len;
            },
            ray.KEY_NULL => {},
            else => {
                typed_history = std.fmt.allocPrint(allocator, "{s}{s}", .{ typed_history, pressed_key }) catch unreachable;
            },
        }

        ray.BeginDrawing();
        ray.ClearBackground(ray.GRAY);
        const text = try std.fmt.allocPrint(allocator, "{s}{s}", .{ "Current operation: ", typed_history });
        defer allocator.free(text);
        ray.DrawText(text.ptr, text_pos.x, text_pos.y, FONT_SIZE, ray.BLACK);
        ray.EndDrawing();
    }
}

const key_values = [_]KbdKeyValue{
    .{ .key = ray.KEY_ZERO, .value = "0" },
    .{ .key = ray.KEY_ONE, .value = "1" },
    .{ .key = ray.KEY_TWO, .value = "2" },
    .{ .key = ray.KEY_THREE, .value = "3" },
    .{ .key = ray.KEY_FOUR, .value = "4" },
    .{ .key = ray.KEY_FIVE, .value = "5" },
    .{ .key = ray.KEY_SIX, .value = "6" },
    .{ .key = ray.KEY_SEVEN, .value = "7" },
    .{ .key = ray.KEY_EIGHT, .value = "8" },
    .{ .key = ray.KEY_NINE, .value = "9" },
    .{ .key = ray.KEY_SLASH, .value = "/" },
    .{ .key = ray.KEY_MINUS, .value = "-" },
    .{ .key = KEY_PLUS, .value = "+" },
    .{ .key = KEY_MULTIPLY, .value = "*" },
    .{ .key = KEY_POWER, .value = "^" },
    .{ .key = KEY_MODULO, .value = "%" },
    .{ .key = ray.KEY_PERIOD, .value = "." },
    .{ .key = ray.KEY_COMMA, .value = "," },
};

const KEY_PLUS: c_int = 43;
const KEY_MULTIPLY: c_int = 42;
const KEY_POWER: c_int = 94;
const KEY_MODULO: c_int = 37;

const KbdKeyValue = struct { key: c_int, value: []const u8 };

const NumberOperation = struct { num: f64, op: ?[]const u8, node: std.SinglyLinkedList.Node };

const WindowPosition = struct { x: c_int, y: c_int };

pub fn Calculate(allocator: std.mem.Allocator, num_ops: *std.SinglyLinkedList) []u8 {
    var calculated_num: ?f64 = null;
    var curr_node = num_ops.first;

    while (curr_node) |node| {
        if (node.next == null)
            break;

        const num_op: *NumberOperation = @fieldParentPtr("node", node);
        const op = num_op.op;
        const num = num_op.num;
        const next_op: *NumberOperation = @fieldParentPtr("node", node.next.?);

        if (calculated_num == null)
            calculated_num = num;

        if (std.mem.eql(u8, op.?, "*"))
            calculated_num = calculated_num.? * next_op.num
        else if (std.mem.eql(u8, op.?, "^"))
            calculated_num = std.math.pow(f64, calculated_num.?, next_op.num)
        else if (std.mem.eql(u8, op.?, "%"))
            calculated_num = std.math.mod(f64, calculated_num.?, next_op.num) catch unreachable
        else if (std.mem.eql(u8, op.?, "/"))
            calculated_num = calculated_num.? / next_op.num
        else if (std.mem.eql(u8, op.?, "+"))
            calculated_num = calculated_num.? + next_op.num
        else
            calculated_num = calculated_num.? - next_op.num;

        curr_node = node.next;
    }

    return std.fmt.allocPrint(allocator, "{d}", .{calculated_num.?}) catch unreachable;
}

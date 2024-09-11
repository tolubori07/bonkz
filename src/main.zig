const vaxis = @import("vaxis");
const std = @import("std");
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;

pub const panic = vaxis.panic_handler;

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .warn },
        .{ .scope = .vaxis_parser, .level = .warn },
    },
};

const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    paste: []const u8,
    color_report: vaxis.Color.Report,
    color_scheme: vaxis.Color.Scheme,
    winsize: vaxis.Winsize,
};

const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    text_input: TextInput, // Declare text_input here

    pub fn init(allocator: std.mem.Allocator) !App {
        var vx = try vaxis.init(allocator, .{});
        const text_input = TextInput.init(allocator, &vx.unicode); // Initialize text_input
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = vx,
            .mouse = null,
            .text_input = text_input,
        };
    }

    pub fn deinit(self: *App) void {
        self.text_input.deinit(); // Deinitialize text_input
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *App) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        while (!self.should_quit) {
            loop.pollEvent();
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            self.draw();
            var buffered = self.tty.bufferedWriter();
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    pub fn draw(self: *App) void {
        const greeting =
            \\██████╗  ██████╗ ███╗   ██╗██╗  ██╗██╗██╗
            \\██╔══██╗██╔═══██╗████╗  ██║██║ ██╔╝██║██║
            \\██████╔╝██║   ██║██╔██╗ ██║█████╔╝ ██║██║
            \\██╔══██╗██║   ██║██║╚██╗██║██╔═██╗ ╚═╝╚═╝
            \\██████╔╝╚██████╔╝██║ ╚████║██║  ██╗██╗██╗
            \\╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝╚═╝
        ;

        const instruction = "Welcome to bonk!! \nType in the packages you would like to install(seperate by space)";

        const win = self.vx.window();
        win.clear();
        self.vx.setMouseShape(.default);

        const style: vaxis.Style = .{ .fg = .{ .rgb = [_]u8{ 113, 114, 211 } }, .bg = .{ .rgb = [_]u8{ 113, 114, 211 } } };

        // Create a window child for the greeting
        const greeting_child = win.child(.{
            .x_off = win.width / 2 - 20,
            .y_off = 2, // Position greeting at the top
            .width = .{ .limit = greeting.len },
            .height = .{ .limit = 6 }, // Adjust the height based on the size of the greeting
            .border = .{ .style = style },
        });

        const instruction_child = win.child(.{
            .x_off = win.width / 2 - 20,
            .y_off = win.height / 4, // Position greeting at the top
            .width = .{ .limit = greeting.len },
            .height = .{ .limit = 6 }, // Adjust the height based on the size of the greeting
            .border = .{ .style = style },
        });

        _ = try instruction_child.printSegment(.{ .text = instruction, .style = .{} }, .{});

        // Print the greeting in the greeting_child window
        const greeting_style: vaxis.Style = .{};
        _ = try greeting_child.printSegment(.{ .text = greeting, .style = greeting_style }, .{});

        // Create a separate window child for the text input
        const input_child = win.child(.{
            .x_off = win.width / 2 - 25,
            .y_off = win.height / 2, // Position the input in the middle of the window
            .width = .{ .limit = 50 },
            .height = .{ .limit = 3 },
            .border = .{ .where = .all, .style = .{ .fg = .{ .rgb = [_]u8{ 113, 114, 211 } } } },
        });

        // Check for mouse events on the input_child
        // Draw the text input in the input_child window
        self.text_input.draw(input_child);
    }

    pub fn update(self: *App, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                } else {
                    try self.text_input.update(.{ .key_press = key }); // Use self.text_input here
                }
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    try app.run();
}

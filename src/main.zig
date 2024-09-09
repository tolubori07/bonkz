const vaxis = @import("vaxis");
const std = @import("std");
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
    focus_in, // window has gained focus
    focus_out, // window has lost focus
    paste_start, // bracketed paste start
    paste_end, // bracketed paste end
    paste: []const u8, // osc 52 paste, caller must free
    color_report: vaxis.Color.Report, // osc 4, 10, 11, 12 response
    color_scheme: vaxis.Color.Scheme, // light / dark OS theme changes
    winsize: vaxis.Winsize, // the window size has changed. This event is always sent when the loop
    // is started
};

const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    text_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !App {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null,
            .text_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.text_buffer.deinit();
        self.tty.deinit();
    }

    pub fn run(self: *App) !void {
        //initialise event loop
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();

        try loop.start();
        defer loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());

        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);

        //enable mouse events
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        //main event loop
        while (!self.should_quit) {
            //poll event blocks until we have an event i.e look for events until we find one
            loop.pollEvent();

            //tryEvent returns events until the queue is empty
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            //draw application after handling events
            self.draw();
            var buffered = self.tty.bufferedWriter();
            // Render the application to the screen
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    pub fn update(self: *App, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                } else if (key.rune >= ' ' and key.rune <= '~') {
                    // Append printable characters (ASCII printable range: 32 to 126)
                    try self.text_buffer.append(u8(key.rune));
                } else if (key.matches(vaxis.Key.backspace, .{})) {
                    // Handle backspace
                    if (self.text_buffer.len > 0) {
                        _ = self.text_buffer.pop();
                    }
                }
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            else => {},
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
        const win = self.vx.window();
        win.clear();
        self.vx.setMouseShape(.default);

        const child = win.child(.{
            .x_off = greeting.len / 10,
            .y_off = 3,
            .width = .{ .limit = greeting.len },
            .height = .{ .limit = 50 },
        });

        // mouse events are much easier to handle in the draw cycle. Windows have a helper method to
        // determine if the event occurred in the target window. This method returns null if there
        // is no mouse event, or if it occurred outside of the window
        const style: vaxis.Style = if (child.hasMouse(self.mouse)) |_| blk: {
            // We handled the mouse event, so set it to null
            self.mouse = null;
            self.vx.setMouseShape(.pointer);
            break :blk .{ .reverse = true };
        } else .{};

        // Print a text segment to the screen. This is a helper function which iterates over the
        // text field for graphemes. Alternatively, you can implement your own print functions and
        // use the writeCell API.
        _ = try child.printSegment(.{ .text = greeting, .style = style }, .{});
    }
};

/// Keep our main function small. Typically handling arg parsing and initialization only
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize our application
    var app = try App.init(allocator);
    defer app.deinit();

    // Run the application
    try app.run();
}

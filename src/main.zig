const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("libretro.h");
});
const gl = @import("gl_es_2v0.zig");

// Basically a port of the following:
// https://github.com/libretro/libretro-samples/blob/master/tests/test/libretro-test.c

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = &gpa.allocator;

var frame_buf: []u32 = undefined;
var last_aspect: f32 = 0.0;
var last_sample_rate: f32 = 0.0;
var hw_render: c.retro_hw_render_callback = undefined;

const BASE_WIDTH = 320;
const BASE_HEIGHT = 240;
const MAX_WIDTH = 1024;
const MAX_HEIGHT = 1024;

var width: u32 = BASE_WIDTH;
var height: u32 = BASE_HEIGHT;

var prog: gl.GLuint = 0;
var vbo: gl.GLuint = 0;

const vertex_shader = @embedFile("shader.vert");
const fragment_shader = @embedFile("shader.frag");

fn compile_program() void {
    prog = gl.createProgram();
    var vert = gl.createShader(gl.VERTEX_SHADER);
    var frag = gl.createShader(gl.FRAGMENT_SHADER);

    var vert_src = [_][*c]const u8{vertex_shader};
    var frag_src = [_][*c]const u8{fragment_shader};
    gl.shaderSource(vert, 1, &vert_src, &@intCast(c_int, vertex_shader.len));
    gl.shaderSource(frag, 1, &frag_src, &@intCast(c_int, vertex_shader.len));
    gl.compileShader(vert);
    gl.compileShader(frag);

    gl.attachShader(prog, vert);
    gl.attachShader(prog, frag);
    gl.linkProgram(prog);
    gl.deleteShader(vert);
    gl.deleteShader(frag);
}

fn setup_vao() void {
    const vertex_data = &[_]gl.GLfloat{
        -0.5, -0.5,
        0.5,  -0.5,
        -0.5, 0.5,
        0.5,  0.5,
        1.0,  1.0,
        1.0,  1.0,
        1.0,  1.0,
        0.0,  1.0,
        0.0,  1.0,
        1.0,  1.0,
        1.0,  0.0,
        1.0,  1.0,
    };

    gl.useProgram(prog);
    gl.genBuffers(1, &vbo);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, vertex_data.len * @sizeOf(gl.GLfloat), vertex_data, gl.STATIC_DRAW);

    gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    gl.useProgram(0);
}

export fn retro_init() void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    frame_buf = alloc.alloc(u32, MAX_WIDTH * MAX_HEIGHT) catch |e| std.debug.panic("error allocating screen: {}", .{e});
}

export fn retro_deinit() void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    alloc.free(frame_buf);
    _ = gpa.deinit();
}

export fn retro_api_version() c_uint {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return c.RETRO_API_VERSION;
}

export fn retro_set_controller_port_device(port: c_uint, device: c_uint) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    std.log.info("Plugging device {} into port {}.", .{ device, port });
}

export fn retro_get_system_info(info: *c.retro_system_info) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });

    std.mem.set(u8, std.mem.asBytes(info), 0);
    info.library_name = "TestCore";
    info.library_version = "v1";
    info.need_fullpath = false;
    info.valid_extensions = null;
}

var video_cb: c.retro_video_refresh_t = null;
var audio_cb: c.retro_audio_sample_t = null;
var audio_batch_cb: c.retro_audio_sample_batch_t = null;
var environ_cb: c.retro_environment_t = null;
var input_poll_cb: c.retro_input_poll_t = null;
var input_state_cb: c.retro_input_state_t = null;
var log_cb: c.retro_log_printf_t = null;

export fn retro_get_system_av_info(info: *c.retro_system_av_info) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });

    var aspect: f32 = 4.0 / 3.0;
    var retro_var: c.retro_variable = .{ .key = "test_aspect", .value = null };
    if (environ_cb.?(c.RETRO_ENVIRONMENT_GET_VARIABLE, &retro_var) and retro_var.value != null) {
        // string compare to figure out aspect ration
        const value = std.mem.spanZ(retro_var.value);
        if (std.mem.eql(u8, "4:3", value)) {
            aspect = 4.0 / 3.0;
        } else if (std.mem.eql(u8, "16:9", value)) {
            aspect = 16.0 / 9.0;
        }
    }

    var sampling_rate: f32 = 30000;
    retro_var.key = "test_samplerate";
    retro_var.value = null;
    if (environ_cb.?(c.RETRO_ENVIRONMENT_GET_VARIABLE, &retro_var) and retro_var.value != null) {
        sampling_rate = std.fmt.parseFloat(f32, std.mem.spanZ(retro_var.value)) catch |e| std.debug.panic("Unable to parse float: {}", .{e});
    }

    info.timing = .{
        .fps = 60.0,
        .sample_rate = sampling_rate,
    };

    info.geometry = .{
        .base_width = BASE_WIDTH,
        .base_height = BASE_HEIGHT,
        .max_width = MAX_WIDTH,
        .max_height = MAX_HEIGHT,
        .aspect_ratio = aspect,
    };

    last_aspect = aspect;
    last_sample_rate = sampling_rate;
}

var rumble: retro_rumble_interface = undefined;

export fn retro_set_environment(env_cb: c.retro_environment_t) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    const cb = env_cb.?;

    environ_cb = cb;

    var retro_vars = [_]c.retro_variable{
        .{ .key = "test_aspect", .value = "Aspect Ratio; 4:3|16:9" },
        .{ .key = "test_resolution", .value = "Internal resolution; 320x240|360x480|480x272|512x384|512x512|640x240|640x448|640x480|720x576|800x600|960x720|1024x768" },
        .{ .key = "test_samplerate", .value = "Sample Rate; 30000|20000" },
        .{ .key = "test_analog_mouse", .value = "Left Analog as mouse; true|false" },
        .{ .key = "test_analog_mouse_relative", .value = "Analog mouse is relative; false|true" },
        .{ .key = "test_audio_enable", .value = "Enable Audio; true|false" },
        .{ .key = null, .value = null },
    };

    _ = cb(c.RETRO_ENVIRONMENT_SET_VARIABLES, &retro_vars);

    var no_content = true;
    _ = cb(c.RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_content);

    var logging: c.retro_log_callback = undefined;
    if (cb(c.RETRO_ENVIRONMENT_GET_LOG_INTERFACE, &logging)) {
        log_cb = logging.log;
    }

    // Set controller types
    const controllers = [_]c.retro_controller_description{
        .{ .desc = "Dummy Controller #1", .id = @intCast(c_uint, c.RETRO_DEVICE_SUBCLASS(c.RETRO_DEVICE_JOYPAD, 0)) },
        .{ .desc = "Dummy Controller #2", .id = @intCast(c_uint, c.RETRO_DEVICE_SUBCLASS(c.RETRO_DEVICE_JOYPAD, 1)) },
        .{ .desc = "Augmented Joypad", .id = c.RETRO_DEVICE_JOYPAD }, // Test overriding generic description in UI.
    };

    var ports = [_]c.retro_controller_info{
        .{ .types = &controllers, .num_types = 3 },
        .{ .types = null, .num_types = 0 },
    };

    _ = cb(c.RETRO_ENVIRONMENT_SET_CONTROLLER_INFO, &ports);
}

export fn retro_set_audio_sample(cb: c.retro_audio_sample_t) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    audio_cb = cb;
}

export fn retro_set_audio_sample_batch(cb: c.retro_audio_sample_batch_t) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    audio_batch_cb = cb;
}

export fn retro_set_input_poll(cb: c.retro_input_poll_t) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    input_poll_cb = cb;
}

export fn retro_set_input_state(cb: c.retro_input_state_t) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    input_state_cb = cb;
}

export fn retro_set_video_refresh(cb: c.retro_video_refresh_t) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    video_cb = cb;
}

// Actual core code

var x_coord: i32 = 0;
var y_coord: i32 = 0;

export fn retro_reset() void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    x_coord = 0;
    y_coord = 0;
}

export fn retro_run() void {
    var updated = false;
    if (environ_cb.?(c.RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) and updated)
        update_variables();
    update_input();
    // render_checkered();
    render_gl();
}

fn update_variables() void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    std.log.debug("Update variables", .{});
    var retro_var: c.retro_variable = .{
        .key = "test_resolution",
        .value = undefined,
    };

    if (environ_cb.?(c.RETRO_ENVIRONMENT_GET_VARIABLE, &retro_var) and retro_var.value != null) {
        const value = std.mem.spanZ(retro_var.value);
        var tokens = std.mem.tokenize(value, "x");

        const tok1 = tokens.next();
        const tok2 = tokens.next();

        if (tok1) |t1| {
            if (tok2) |t2| {
                width = std.fmt.parseUnsigned(u32, t1, 10) catch width;
                height = std.fmt.parseUnsigned(u32, t2, 10) catch height;
            }
        }

        std.log.debug("Width and Height set to {s}", .{value});
    }
}

fn update_input() void {
    var dir_x: i32 = 0;
    var dir_y: i32 = 0;

    input_poll_cb.?();
    if (input_state_cb.?(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_UP) != 0) {
        dir_y -= 1;
    }
    if (input_state_cb.?(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_DOWN) != 0) {
        dir_y += 1;
    }
    if (input_state_cb.?(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_LEFT) != 0) {
        dir_x -= 1;
    }
    if (input_state_cb.?(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_RIGHT) != 0) {
        dir_x += 1;
    }

    dir_x += @divFloor(input_state_cb.?(0, c.RETRO_DEVICE_ANALOG, c.RETRO_DEVICE_INDEX_ANALOG_LEFT, c.RETRO_DEVICE_ID_ANALOG_X), 5000);
    dir_y += @divFloor(input_state_cb.?(0, c.RETRO_DEVICE_ANALOG, c.RETRO_DEVICE_INDEX_ANALOG_LEFT, c.RETRO_DEVICE_ID_ANALOG_Y), 5000);

    x_coord = (x_coord + dir_x) & 31;
    y_coord = (y_coord + dir_y) & 31;

    if (input_state_cb.?(0, c.RETRO_DEVICE_KEYBOARD, 0, c.RETROK_RETURN) != 0) {
        std.log.info("Return key is pressed!", .{});
    }
}

fn render_checkered() void {
    var buf: [*]u32 = undefined;
    var stride: usize = 0;

    var fb = std.mem.zeroes(c.retro_framebuffer);
    fb.width = width;
    fb.height = height;
    fb.access_flags = c.RETRO_MEMORY_ACCESS_WRITE;

    if (environ_cb.?(c.RETRO_ENVIRONMENT_GET_CURRENT_SOFTWARE_FRAMEBUFFER, &fb) and fb.format == .RETRO_PIXEL_FORMAT_XRGB8888) {
        buf = @ptrCast([*]u32, @alignCast(4, fb.data));
        stride = fb.pitch >> 2;
    } else {
        buf = frame_buf.ptr;
        stride = width;
    }

    const color_r: u32 = 0xff << 16;
    const color_g: u32 = 0xff << 8;

    var y: i32 = 0;
    while (y < height) : (y += 1) {
        const line = buf[@intCast(u32, y) * stride .. @intCast(u32, y + 1) * stride];
        const index_y = ((y - y_coord) >> 4) & 1;
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            const index_x = ((x - x_coord) >> 4) & 1;
            line[@intCast(usize, x)] = if ((index_y ^ index_x) != 0) color_r else color_g;
        }
    }

    video_cb.?(buf, width, height, stride << 2);
}

var frame_count: u32 = 0;

fn render_gl() void {
    const res = hw_render.get_current_framebuffer.?();
    if (res < 0) {
        std.log.info("Could not get framebuffer", .{});
        return;
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, @intCast(c_uint, res));

    gl.clearColor(0.3, 0.4, 0.5, 1.0);
    gl.viewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

    gl.useProgram(prog);
    defer gl.useProgram(0);

    gl.enable(gl.DEPTH_TEST);

    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    // const attr1 = gl.getAttribLocation(prog, "aVertex");
    // if (attr1 < 0) {
    //     std.log.info("Could not get aVertex attribute!", .{});
    //     var err = gl.getError();
    //     while (err != gl.NO_ERROR) {
    //         const errstr = switch (err) {
    //             gl.NO_ERROR => "No error",
    //             gl.INVALID_ENUM => "Invalid enum",
    //             gl.INVALID_VALUE => "Invalid value",
    //             gl.INVALID_OPERATION => "Invalid operation",
    //             gl.OUT_OF_MEMORY => "Out of memory",
    //             // gl.STACK_OVERFLOW => "Stack Overflow",
    //             // gl.STACK_UNDERFLOW => "Stack Underflow",
    //             // gl.TABLE_TOO_LARGE => "Table too large",
    //             gl.INVALID_FRAMEBUFFER_OPERATION => "Invalid framebuffer operation",
    //             else => "Unknown",
    //         };
    //         std.log.info("ERROR: {} {s}", .{ err, errstr });
    //         err = gl.getError();
    //     }
    // }
    const vloc = 0; // @intCast(c_uint, attr1);
    gl.vertexAttribPointer(vloc, 2, gl.FLOAT, gl.FALSE, 0, null);
    gl.enableVertexAttribArray(vloc);
    defer gl.disableVertexAttribArray(vloc);

    // const attr2 = gl.getAttribLocation(prog, "aColor");
    // if (attr2 < 0) {
    //     std.log.info("Could not get aColor attribute, result: {}", .{attr2});
    // }
    const cloc = 1; //@intCast(c_uint, attr2);
    gl.vertexAttribPointer(cloc, 4, gl.FLOAT, gl.FALSE, 0, @intToPtr(*c_void, 8 * @sizeOf(gl.GLfloat)));
    gl.enableVertexAttribArray(cloc);
    gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    defer gl.disableVertexAttribArray(cloc);

    const loc = gl.getUniformLocation(prog, "uMVP");

    const angle = @intToFloat(f32, frame_count) / 100.0;
    var cos_angle = std.math.cos(angle);
    var sin_angle = std.math.sin(angle);

    const mvp = &[_]gl.GLfloat{
        cos_angle, -sin_angle, 0, 0,
        sin_angle, cos_angle,  0, 0,
        0,         0,          1, 0,
        0,         0,          0, 1,
    };
    gl.uniformMatrix4fv(loc, 1, gl.FALSE, mvp);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    cos_angle *= 0.5;
    sin_angle *= 0.5;

    const mvp2 = &[_]gl.GLfloat{
        cos_angle, -sin_angle, 0,   0,
        sin_angle, cos_angle,  0,   0,
        0,         0,          1,   0,
        0.4,       0.5,        0.2, 1,
    };

    gl.uniformMatrix4fv(loc, 1, gl.FALSE, mvp2);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    frame_count += 1;

    const RETRO_HW_FRAME_BUFFER_VALID = @intToPtr(*c_void, @bitCast(usize, @as(isize, -1)));

    video_cb.?(RETRO_HW_FRAME_BUFFER_VALID, width, height, 0);
}

fn get_proc_address(_: u8, proc: [:0]const u8) ?*const c_void {
    const get_proc_addr = hw_render.get_proc_address.?;
    const res = get_proc_addr(proc);
    return res;
}

export fn context_reset() void {
    std.log.info("Context reset!", .{});

    var ctx: u8 = 0;
    gl.load(ctx, get_proc_address) catch |e| std.log.info("Couldn't initialize GL", .{});

    compile_program();
    setup_vao();
}

export fn context_destroy() void {
    std.log.info("Context destroy!", .{});

    gl.deleteBuffers(1, &vbo);
    vbo = 0;
    gl.deleteProgram(prog);
    prog = 0;
}

fn retro_init_hw_context() bool {
    hw_render.context_type = .RETRO_HW_CONTEXT_OPENGL;
    hw_render.context_reset = context_reset;
    hw_render.context_destroy = context_destroy;
    hw_render.depth = true;
    hw_render.stencil = true;
    hw_render.bottom_left_origin = true;

    if (!environ_cb.?(c.RETRO_ENVIRONMENT_SET_HW_RENDER, &hw_render))
        return false;

    return true;
}

export fn retro_load_game(info: ?*const c.retro_game_info) bool {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });

    update_variables();

    var desc = [_]c.retro_input_descriptor{
        .{ .port = 0, .device = c.RETRO_DEVICE_JOYPAD, .index = 0, .id = c.RETRO_DEVICE_ID_JOYPAD_LEFT, .description = "Left" },
        .{ .port = 0, .device = c.RETRO_DEVICE_JOYPAD, .index = 0, .id = c.RETRO_DEVICE_ID_JOYPAD_UP, .description = "Up" },
        .{ .port = 0, .device = c.RETRO_DEVICE_JOYPAD, .index = 0, .id = c.RETRO_DEVICE_ID_JOYPAD_DOWN, .description = "Down" },
        .{ .port = 0, .device = c.RETRO_DEVICE_JOYPAD, .index = 0, .id = c.RETRO_DEVICE_ID_JOYPAD_RIGHT, .description = "Right" },
        std.mem.zeroes(c.retro_input_descriptor),
    };

    _ = environ_cb.?(c.RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS, &desc);

    var fmt = c.retro_pixel_format.RETRO_PIXEL_FORMAT_XRGB8888;
    if (!environ_cb.?(c.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt)) {
        std.log.info("XRGB8888 is not supported", .{});
        return false;
    }

    if (!retro_init_hw_context()) {
        std.log.info("HW Context could not be initialized, exiting...", .{});
        return false;
    }

    return true;
}

export fn retro_unload_game() void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
}

export fn retro_get_region() c_uint {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return c.RETRO_REGION_NTSC;
}

export fn retro_load_game_special(type_int: c_uint, info: *c.retro_game_info, num: isize) bool {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return retro_load_game(null);
}

export fn retro_serialize_size() isize {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return 0;
}

export fn retro_serialize(data: *c_void, size: isize) bool {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return false;
}

export fn retro_unserialize(data: *const c_void, size: isize) bool {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return false;
}

export fn retro_get_memory_data(id: c_uint) ?*c_void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return null;
}

export fn retro_get_memory_size(id: c_uint) isize {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
    return 0;
}

export fn retro_cheat_reset(id: c_uint) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
}

export fn retro_cheat_set(id: c_uint, enabled: bool, code: [*]const u8) void {
    std.log.debug("{s}:{}", .{ @src().fn_name, @src().line });
}

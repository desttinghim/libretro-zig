const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("libretro.h");
});

// Basically a port of the following:
// https://github.com/libretro/libretro-samples/blob/master/tests/test/libretro-test.c

export fn fallback_log(log_level, fmt: [*]u8) void {}

export fn retro_init() void {}

export fn retro_deinit() void {}

export fn retro_api_version() c_uint {
    return c.RETRO_API_VERSION;
}

export fn retro_set_controller_port_device(port: c_uint, device: c_uint) void {
    c.log_cb(c.RETRO_LOG_INFO, "Plugging device {} into port {}.\n", device, port);
}

export fn retro_get_system_info(info: *c.retro_system_info) void {
    info.library_name = "TestCore";
    info.library_version = "v1";
    info.need_fullpath = false;
    info.valid_extensions = null;
}

var video_cb: c.retro_video_refresh_t = undefined;
var audio_cb: c.retro_audio_sample_t = undefined;
var audio_batch_cb: c.retro_audio_sample_batch_t = undefined;
var environ_cb: c.retro_environment_t = undefined;
var input_poll_cb: c.retro_input_poll_t = undefined;
var input_state_cb: c.retro_input_state_t = undefined;

export fn retro_get_system_av_info(info: c.retro_system_av_info) void {
    var aspect: f32 = 4.0 / 3.0;
    var retro_var: c.retro_variable = .{ .key = "test_aspect" };
    if (environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &retro_var) and retro_var.value) {
        // string compare to figure out aspect ration
        // if (retro_var.value == "4:3")
    }

    var sampling_rate: f32 = 30000;
    retro_var.key = "test_samplerate";
    if (environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &retro_var) and retro_var.value) {
        // sampling_rate = str_to_float(retro_var.value)
    }

    info.timing = .{
        .fps = 60.0,
        .sample_rate = sampling_rate,
    };

    info.geometry = .{
        .base_width = 320,
        .base_height = 240,
        .max_width = 320,
        .max_height = 240,
        .aspect_ratio = aspect,
    };

    last_aspect = aspect;
    last_sample_rate = sampling_rate;
}

var rumble: retro_rumble_interface = undefined;

export fn retro_set_environment(cb: c.retro_environment_t) void {
    environ_cb = cb;

    const retro_vars = .{
        .{ "test_aspect", "Aspect Ratio; 4:3|16:9" },
        .{ "test_samplerate", "Sample Rate; 30000|20000" },
        .{ "test_analog_mouse", "Left Analog as mouse; true|false" },
        .{ "test_analog_mouse_relative", "Analog mouse is relative; false|true" },
        .{ "test_audio_enable", "Enable Audio; true|false" },
        .{ null, null },
    };
}

test "basic add functionality" {
    testing.expect(add(3, 7) == 10);
}

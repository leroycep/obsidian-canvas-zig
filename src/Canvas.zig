program: gl.Program,
uniforms: UniformLocations,
current_texture: ?gl.Texture,
vertices: std.ArrayListUnmanaged(Vertex),

blank_texture: gl.Texture,
font: BitmapFont,
font_pages: std.AutoHashMapUnmanaged(u32, FontPage),

vbo: gl.Buffer,
vao: gl.VertexArray,

const Canvas = @This();

pub fn init(allocator: std.mem.Allocator, vertex_buffer_size: usize) !@This() {
    // Text shader
    const program = gl.createProgram();
    errdefer program.delete();

    {
        const vs = gl.createShader(.vertex);
        defer vs.delete();
        vs.source(1, &.{@embedFile("./Canvas.vs.glsl")});
        vs.compile();

        const fs = gl.createShader(.fragment);
        defer fs.delete();
        fs.source(1, &.{@embedFile("./Canvas.fs.glsl")});
        fs.compile();

        program.attach(vs);
        program.attach(fs);
        defer {
            program.detach(vs);
            program.detach(fs);
        }
        program.link();
    }

    var vertices = try std.ArrayListUnmanaged(Vertex).initCapacity(allocator, vertex_buffer_size);
    errdefer vertices.deinit(allocator);

    const blank_texture = gl.createTexture(.@"2d");
    errdefer blank_texture.delete();
    {
        const BLANK_IMAGE = [_][4]u8{
            .{ 0xFF, 0xFF, 0xFF, 0xFF },
        };

        blank_texture.bind(.@"2d");
        gl.pixelStore(.unpack_row_length, 0);
        gl.textureImage2D(
            .@"2d",
            0,
            .rgba,
            1,
            1,
            .rgba,
            .unsigned_byte,
            std.mem.sliceAsBytes(&BLANK_IMAGE).ptr,
        );
        blank_texture.parameter(.min_filter, .nearest);
        blank_texture.parameter(.mag_filter, .nearest);
        blank_texture.parameter(.wrap_s, .clamp_to_edge);
        blank_texture.parameter(.wrap_t, .clamp_to_edge);
    }

    var font = try BitmapFont.parse(allocator, @embedFile("./font/PressStart2P_8.fnt"));
    errdefer font.deinit();

    var font_pages = std.AutoHashMapUnmanaged(u32, FontPage){};
    errdefer font_pages.deinit(allocator);

    var page_name_iter = font.pages.iterator();
    while (page_name_iter.next()) |font_page| {
        const page_id = font_page.key_ptr.*;
        const page_name = font_page.value_ptr.*;

        const image_bytes = if (std.mem.eql(u8, page_name, "PressStart2P_8.png")) @embedFile("./font/PressStart2P_8.png") else return error.FontPageImageNotFound;

        var font_image = try zigimg.Image.fromMemory(allocator, image_bytes);
        defer font_image.deinit();

        const page_texture = gl.createTexture(.@"2d");
        errdefer page_texture.delete();

        page_texture.bind(.@"2d");
        gl.pixelStore(.unpack_row_length, 0);
        gl.textureImage2D(
            .@"2d",
            0,
            .rgba,
            font_image.width,
            font_image.height,
            .rgba,
            .unsigned_byte,
            std.mem.sliceAsBytes(font_image.pixels.rgba32).ptr,
        );
        page_texture.parameter(.min_filter, .nearest);
        page_texture.parameter(.mag_filter, .nearest);
        page_texture.parameter(.wrap_s, .clamp_to_edge);
        page_texture.parameter(.wrap_t, .clamp_to_edge);

        try font_pages.put(allocator, page_id, .{
            .texture = page_texture,
            .size = .{
                @intToFloat(f32, font_image.width),
                @intToFloat(f32, font_image.height),
            },
        });
    }

    const vbo = gl.createBuffer();
    errdefer vbo.delete();
    const vao = gl.createVertexArray();
    errdefer vao.delete();

    return .{
        .program = program,
        .uniforms = .{
            .projection = program.uniformLocation("projection") orelse return error.UniformNotDefined,
            .texture = program.uniformLocation("texture_handle") orelse return error.UniformNotDefined,
        },
        .current_texture = null,
        .vertices = vertices,

        .blank_texture = blank_texture,
        .font = font,
        .font_pages = font_pages,

        .vbo = vbo,
        .vao = vao,
    };
}

pub fn deinit(this: *@This(), allocator: std.mem.Allocator) void {
    this.program.delete();
    this.vertices.deinit(allocator);
    this.font.deinit();

    var page_name_iter = this.font_pages.iterator();
    while (page_name_iter.next()) |entry| {
        entry.value_ptr.*.texture.delete();
    }
    this.font_pages.deinit(allocator);

    this.vbo.delete();
    this.vao.delete();
}

pub const BeginOptions = struct {
    projection: [4][4]f32,
};

pub fn begin(this: *@This(), options: BeginOptions) void {
    // TEXTURE_UNIT0
    this.program.uniform1i(this.uniforms.texture, 0);
    this.program.uniformMatrix4(this.uniforms.projection, false, &.{options.projection});

    this.vertices.shrinkRetainingCapacity(0);

    gl.enable(.blend);
    gl.disable(.depth_test);
    gl.blendFunc(.src_alpha, .one_minus_src_alpha);
    gl.activeTexture(.texture_0);
}

pub const RectOptions = struct {
    pos: [2]f32,
    size: [2]f32,
    color: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF },
    texture: ?gl.Texture = null,
    /// The top left and bottom right coordinates
    uv: [2][2]f32 = .{ .{ 0, 0 }, .{ 0, 0 } },
};

pub fn rect(this: *@This(), options: RectOptions) void {
    if (this.vertices.unusedCapacitySlice().len < 6) {
        this.flush();
    }
    if (!std.meta.eql(options.texture, this.current_texture)) {
        this.flush();
        this.current_texture = options.texture;
    }

    this.vertices.appendSliceAssumeCapacity(&.{
        // triangle 1
        .{
            .pos = options.pos,
            .uv = options.uv[0],
            .color = options.color,
        },
        .{
            .pos = .{
                options.pos[0] + options.size[0],
                options.pos[1],
            },
            .uv = .{
                options.uv[1][0],
                options.uv[0][1],
            },
            .color = options.color,
        },
        .{
            .pos = .{
                options.pos[0],
                options.pos[1] + options.size[1],
            },
            .uv = .{
                options.uv[0][0],
                options.uv[1][1],
            },
            .color = options.color,
        },

        // triangle 2
        .{
            .pos = .{
                options.pos[0] + options.size[0],
                options.pos[1] + options.size[1],
            },
            .uv = options.uv[1],
            .color = options.color,
        },
        .{
            .pos = .{
                options.pos[0],
                options.pos[1] + options.size[1],
            },
            .uv = .{
                options.uv[0][0],
                options.uv[1][1],
            },
            .color = options.color,
        },
        .{
            .pos = .{
                options.pos[0] + options.size[0],
                options.pos[1],
            },
            .uv = .{
                options.uv[1][0],
                options.uv[0][1],
            },
            .color = options.color,
        },
    });
}

pub const TextOptions = struct {
    pos: [2]f32,
    color: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF },
    scale: f32 = 1,
    @"align": Align = .left,
    baseline: Baseline = .top,

    const Align = enum {
        left,
        center,
    };

    const Baseline = enum {
        top,
        middle,
        bottom,
    };
};

pub fn writeText(this: *@This(), text: []const u8, options: TextOptions) void {
    const text_size = this.font.textSize(text, options.scale);

    var x: f32 = switch (options.@"align") {
        .left => options.pos[0],
        .center => options.pos[0] - text_size[0] / 2,
    };
    var y: f32 = switch (options.baseline) {
        .top => options.pos[1],
        .middle => options.pos[1] - text_size[1] / 2,
        .bottom => options.pos[1] - text_size[1],
    };
    var text_writer = this.textWriter(.{
        .pos = .{ x, y },
        .scale = options.scale,
        .color = options.color,
    });
    text_writer.writer().writeAll(text) catch {};
}

pub fn printText(this: *@This(), comptime fmt: []const u8, args: anytype, options: TextOptions) void {
    const text_size = this.font.fmtTextSize(fmt, args, options.scale);

    const x: f32 = switch (options.@"align") {
        .left => options.pos[0],
        .center => options.pos[0] - text_size[0] / 2,
    };
    const y: f32 = switch (options.baseline) {
        .top => options.pos[1],
        .middle => options.pos[1] - text_size[1] / 2,
        .bottom => options.pos[1] - text_size[1],
    };

    var text_writer = this.textWriter(.{
        .pos = .{ x, y },
        .scale = options.scale,
        .color = options.color,
    });
    text_writer.writer().print(fmt, args) catch {};
}

pub fn end(this: *@This()) void {
    this.flush();
}

pub fn textWriter(this: *@This(), options: TextWriter.Options) TextWriter {
    return TextWriter{
        .canvas = this,
        .options = options,
        .direction = 1,
        .current_pos = options.pos,
    };
}

pub const TextWriter = struct {
    canvas: *Canvas,
    options: Options,
    direction: f32,
    current_pos: [2]f32,

    pub const Options = struct {
        pos: [2]f32 = .{ 0, 0 },
        color: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF },
        scale: f32 = 1,
    };

    pub fn addCharacter(this: *@This(), character: u21) void {
        if (character == '\n') {
            this.current_pos[1] += this.canvas.font.lineHeight * this.options.scale;
            this.current_pos[0] = this.options.pos[0];
            return;
        }
        const glyph = this.canvas.font.glyphs.get(character) orelse return;

        const xadvance = (glyph.xadvance * this.options.scale);
        const offset = [2]f32{
            glyph.offset[0] * this.options.scale,
            glyph.offset[1] * this.options.scale,
        };

        const font_page = this.canvas.font_pages.get(glyph.page) orelse return;

        this.canvas.rect(.{
            .pos = .{
                this.current_pos[0] + offset[0],
                this.current_pos[1] + offset[1],
            },
            .size = .{
                glyph.size[0] * this.options.scale,
                glyph.size[1] * this.options.scale,
            },
            .texture = font_page.texture,
            .uv = .{
                .{
                    glyph.pos[0] / font_page.size[0],
                    glyph.pos[1] / font_page.size[1],
                },
                .{
                    (glyph.pos[0] + glyph.size[0]) / font_page.size[0],
                    (glyph.pos[1] + glyph.size[1]) / font_page.size[1],
                },
            },
            .color = this.options.color,
        });

        this.current_pos[0] += this.direction * xadvance;
    }

    pub fn addText(this: *@This(), text: []const u8) void {
        for (text) |char| {
            this.addCharacter(char);
        }
    }

    pub fn writer(this: *@This()) Writer {
        return Writer{
            .context = this,
        };
    }

    pub const Writer = std.io.Writer(*@This(), error{}, write);

    pub fn write(this: *@This(), bytes: []const u8) error{}!usize {
        this.addText(bytes);
        return bytes.len;
    }
};

fn flush(this: *@This()) void {
    gl.bindTexture(this.current_texture orelse this.blank_texture, .@"2d");
    defer gl.bindTexture(.invalid, .@"2d");

    this.vbo.data(Vertex, this.vertices.items, .dynamic_draw);

    this.vao.bind();
    defer gl.bindVertexArray(.invalid);
    this.vao.vertexBuffer(0, this.vbo, 0, @sizeOf(Vertex));

    this.vao.enableVertexAttribute(0);
    this.vao.enableVertexAttribute(1);
    this.vao.enableVertexAttribute(2);
    this.vao.attribFormat(0, 2, .float, false, @offsetOf(Vertex, "pos"));
    this.vao.attribFormat(1, 2, .float, false, @offsetOf(Vertex, "uv"));
    this.vao.attribFormat(2, 4, .unsigned_byte, true, @offsetOf(Vertex, "color"));
    this.vao.attribBinding(0, 0);
    this.vao.attribBinding(1, 0);
    this.vao.attribBinding(2, 0);

    this.program.use();
    gl.drawArrays(.triangles, 0, this.vertices.items.len);

    this.vertices.shrinkRetainingCapacity(0);
    this.current_texture = null;
}

const UniformLocations = struct {
    projection: u32,
    texture: u32,
};

const FontPage = struct {
    texture: gl.Texture,
    size: [2]f32,
};

const Vertex = struct {
    pos: [2]f32,
    uv: [2]f32,
    color: [4]u8,
};

const std = @import("std");
const BitmapFont = @import("./font/bitmap.zig").Font;
const gl = @import("zgl");
const zigimg = @import("zigimg");

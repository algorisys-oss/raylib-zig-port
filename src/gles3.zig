//! gles3 - OpenGL ES 3.0 (WebGL 2) entry points for the rlgl Zig port on Emscripten.
//!
//! The web counterpart of src/gl33.zig, chosen by rlgl.zig's `graphics_api`. It
//! declares the same `glad_gl*` names, so rlgl's call sites (`gl.glad_glClear.?(...)`)
//! are identical on both targets. Here they are not loaded pointers: each one is a
//! comptime-known pointer to the GLES 3 function Emscripten's WebGL library defines
//! (link with -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2), so nothing is loaded at
//! run time and `.?` is free.
//!
//! Desktop-only entry points and enums are deliberately missing (glPolygonMode,
//! glClearDepth, glGetTexImage, GL_LINE_SMOOTH, ...): rlgl.zig reaches them only on
//! GL 3.3, and using one on the web is a compile error instead of a WebGL error.
//! Enum values are the same in GL and GLES; the ES-only ones are at the end.
//!
//! GL type mapping (GLES3/gl3.h, as in gl33.zig):
//!   GLenum/GLuint/GLbitfield = c_uint   GLint/GLsizei = c_int
//!   GLfloat = f32   GLboolean/GLubyte/GLchar = u8
//!   GLintptr = isize   GLsizeiptr = usize   void*/GLvoid = anyopaque

/// The function `name` as linked from Emscripten's GL library, typed as `Proc`.
fn proc(comptime Proc: type, comptime name: []const u8) ?*const Proc {
    return @extern(*const Proc, .{ .name = name });
}

// --- State / clear / viewport ---------------------------------------------------
pub const glad_glClearColor = proc(fn (red: f32, green: f32, blue: f32, alpha: f32) callconv(.c) void, "glClearColor");
pub const glad_glClear = proc(fn (mask: c_uint) callconv(.c) void, "glClear");
pub const glad_glClearDepthf = proc(fn (d: f32) callconv(.c) void, "glClearDepthf");
pub const glad_glViewport = proc(fn (x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void, "glViewport");
pub const glad_glScissor = proc(fn (x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void, "glScissor");
pub const glad_glEnable = proc(fn (cap: c_uint) callconv(.c) void, "glEnable");
pub const glad_glDisable = proc(fn (cap: c_uint) callconv(.c) void, "glDisable");
pub const glad_glDepthFunc = proc(fn (func: c_uint) callconv(.c) void, "glDepthFunc");
pub const glad_glDepthMask = proc(fn (flag: u8) callconv(.c) void, "glDepthMask");
pub const glad_glCullFace = proc(fn (mode: c_uint) callconv(.c) void, "glCullFace");
pub const glad_glFrontFace = proc(fn (mode: c_uint) callconv(.c) void, "glFrontFace");
pub const glad_glColorMask = proc(fn (red: u8, green: u8, blue: u8, alpha: u8) callconv(.c) void, "glColorMask");
pub const glad_glLineWidth = proc(fn (width: f32) callconv(.c) void, "glLineWidth");

// --- Blending -------------------------------------------------------------------
pub const glad_glBlendFunc = proc(fn (sfactor: c_uint, dfactor: c_uint) callconv(.c) void, "glBlendFunc");
pub const glad_glBlendEquation = proc(fn (mode: c_uint) callconv(.c) void, "glBlendEquation");
pub const glad_glBlendFuncSeparate = proc(fn (sfactorRGB: c_uint, dfactorRGB: c_uint, sfactorAlpha: c_uint, dfactorAlpha: c_uint) callconv(.c) void, "glBlendFuncSeparate");
pub const glad_glBlendEquationSeparate = proc(fn (modeRGB: c_uint, modeAlpha: c_uint) callconv(.c) void, "glBlendEquationSeparate");

// --- Queries --------------------------------------------------------------------
pub const glad_glGetFloatv = proc(fn (pname: c_uint, data: [*c]f32) callconv(.c) void, "glGetFloatv");
pub const glad_glGetIntegerv = proc(fn (pname: c_uint, data: [*c]c_int) callconv(.c) void, "glGetIntegerv");
pub const glad_glGetError = proc(fn () callconv(.c) c_uint, "glGetError");
pub const glad_glGetString = proc(fn (name: c_uint) callconv(.c) [*c]const u8, "glGetString");
pub const glad_glGetStringi = proc(fn (name: c_uint, index: c_uint) callconv(.c) [*c]const u8, "glGetStringi");
pub const glad_glPixelStorei = proc(fn (pname: c_uint, param: c_int) callconv(.c) void, "glPixelStorei");

// --- Textures -------------------------------------------------------------------
pub const glad_glActiveTexture = proc(fn (texture: c_uint) callconv(.c) void, "glActiveTexture");
pub const glad_glBindTexture = proc(fn (target: c_uint, texture: c_uint) callconv(.c) void, "glBindTexture");
pub const glad_glGenTextures = proc(fn (n: c_int, textures: [*c]c_uint) callconv(.c) void, "glGenTextures");
pub const glad_glDeleteTextures = proc(fn (n: c_int, textures: [*c]const c_uint) callconv(.c) void, "glDeleteTextures");
pub const glad_glTexParameteri = proc(fn (target: c_uint, pname: c_uint, param: c_int) callconv(.c) void, "glTexParameteri");
pub const glad_glTexParameterf = proc(fn (target: c_uint, pname: c_uint, param: f32) callconv(.c) void, "glTexParameterf");
pub const glad_glTexParameteriv = proc(fn (target: c_uint, pname: c_uint, params: [*c]const c_int) callconv(.c) void, "glTexParameteriv");
pub const glad_glTexImage2D = proc(fn (target: c_uint, level: c_int, internalformat: c_int, width: c_int, height: c_int, border: c_int, format: c_uint, type: c_uint, pixels: ?*const anyopaque) callconv(.c) void, "glTexImage2D");
pub const glad_glCompressedTexImage2D = proc(fn (target: c_uint, level: c_int, internalformat: c_uint, width: c_int, height: c_int, border: c_int, imageSize: c_int, data: ?*const anyopaque) callconv(.c) void, "glCompressedTexImage2D");
pub const glad_glTexSubImage2D = proc(fn (target: c_uint, level: c_int, xoffset: c_int, yoffset: c_int, width: c_int, height: c_int, format: c_uint, type: c_uint, pixels: ?*const anyopaque) callconv(.c) void, "glTexSubImage2D");
pub const glad_glGenerateMipmap = proc(fn (target: c_uint) callconv(.c) void, "glGenerateMipmap");
pub const glad_glReadPixels = proc(fn (x: c_int, y: c_int, width: c_int, height: c_int, format: c_uint, type: c_uint, pixels: ?*anyopaque) callconv(.c) void, "glReadPixels");

// --- Vertex arrays / buffers ----------------------------------------------------
pub const glad_glGenVertexArrays = proc(fn (n: c_int, arrays: [*c]c_uint) callconv(.c) void, "glGenVertexArrays");
pub const glad_glBindVertexArray = proc(fn (array: c_uint) callconv(.c) void, "glBindVertexArray");
pub const glad_glDeleteVertexArrays = proc(fn (n: c_int, arrays: [*c]const c_uint) callconv(.c) void, "glDeleteVertexArrays");
pub const glad_glGenBuffers = proc(fn (n: c_int, buffers: [*c]c_uint) callconv(.c) void, "glGenBuffers");
pub const glad_glBindBuffer = proc(fn (target: c_uint, buffer: c_uint) callconv(.c) void, "glBindBuffer");
pub const glad_glBufferData = proc(fn (target: c_uint, size: isize, data: ?*const anyopaque, usage: c_uint) callconv(.c) void, "glBufferData");
pub const glad_glBufferSubData = proc(fn (target: c_uint, offset: isize, size: isize, data: ?*const anyopaque) callconv(.c) void, "glBufferSubData");
pub const glad_glDeleteBuffers = proc(fn (n: c_int, buffers: [*c]const c_uint) callconv(.c) void, "glDeleteBuffers");
pub const glad_glEnableVertexAttribArray = proc(fn (index: c_uint) callconv(.c) void, "glEnableVertexAttribArray");
pub const glad_glDisableVertexAttribArray = proc(fn (index: c_uint) callconv(.c) void, "glDisableVertexAttribArray");
pub const glad_glVertexAttribPointer = proc(fn (index: c_uint, size: c_int, type: c_uint, normalized: u8, stride: c_int, pointer: ?*const anyopaque) callconv(.c) void, "glVertexAttribPointer");
pub const glad_glVertexAttribDivisor = proc(fn (index: c_uint, divisor: c_uint) callconv(.c) void, "glVertexAttribDivisor");
pub const glad_glDrawArrays = proc(fn (mode: c_uint, first: c_int, count: c_int) callconv(.c) void, "glDrawArrays");
pub const glad_glDrawElements = proc(fn (mode: c_uint, count: c_int, type: c_uint, indices: ?*const anyopaque) callconv(.c) void, "glDrawElements");
pub const glad_glDrawArraysInstanced = proc(fn (mode: c_uint, first: c_int, count: c_int, instancecount: c_int) callconv(.c) void, "glDrawArraysInstanced");
pub const glad_glDrawElementsInstanced = proc(fn (mode: c_uint, count: c_int, type: c_uint, indices: ?*const anyopaque, instancecount: c_int) callconv(.c) void, "glDrawElementsInstanced");

// --- Vertex attrib default values -----------------------------------------------
pub const glad_glVertexAttrib1fv = proc(fn (index: c_uint, v: [*c]const f32) callconv(.c) void, "glVertexAttrib1fv");
pub const glad_glVertexAttrib2fv = proc(fn (index: c_uint, v: [*c]const f32) callconv(.c) void, "glVertexAttrib2fv");
pub const glad_glVertexAttrib3fv = proc(fn (index: c_uint, v: [*c]const f32) callconv(.c) void, "glVertexAttrib3fv");
pub const glad_glVertexAttrib4fv = proc(fn (index: c_uint, v: [*c]const f32) callconv(.c) void, "glVertexAttrib4fv");

// --- Shaders / programs ---------------------------------------------------------
pub const glad_glUseProgram = proc(fn (program: c_uint) callconv(.c) void, "glUseProgram");
pub const glad_glCreateShader = proc(fn (type: c_uint) callconv(.c) c_uint, "glCreateShader");
pub const glad_glShaderSource = proc(fn (shader: c_uint, count: c_int, string: [*c]const [*c]const u8, length: [*c]const c_int) callconv(.c) void, "glShaderSource");
pub const glad_glCompileShader = proc(fn (shader: c_uint) callconv(.c) void, "glCompileShader");
pub const glad_glGetShaderiv = proc(fn (shader: c_uint, pname: c_uint, params: [*c]c_int) callconv(.c) void, "glGetShaderiv");
pub const glad_glGetShaderInfoLog = proc(fn (shader: c_uint, bufSize: c_int, length: [*c]c_int, infoLog: [*c]u8) callconv(.c) void, "glGetShaderInfoLog");
pub const glad_glDeleteShader = proc(fn (shader: c_uint) callconv(.c) void, "glDeleteShader");
pub const glad_glCreateProgram = proc(fn () callconv(.c) c_uint, "glCreateProgram");
pub const glad_glAttachShader = proc(fn (program: c_uint, shader: c_uint) callconv(.c) void, "glAttachShader");
pub const glad_glDetachShader = proc(fn (program: c_uint, shader: c_uint) callconv(.c) void, "glDetachShader");
pub const glad_glBindAttribLocation = proc(fn (program: c_uint, index: c_uint, name: [*c]const u8) callconv(.c) void, "glBindAttribLocation");
pub const glad_glLinkProgram = proc(fn (program: c_uint) callconv(.c) void, "glLinkProgram");
pub const glad_glGetProgramiv = proc(fn (program: c_uint, pname: c_uint, params: [*c]c_int) callconv(.c) void, "glGetProgramiv");
pub const glad_glGetProgramInfoLog = proc(fn (program: c_uint, bufSize: c_int, length: [*c]c_int, infoLog: [*c]u8) callconv(.c) void, "glGetProgramInfoLog");
pub const glad_glDeleteProgram = proc(fn (program: c_uint) callconv(.c) void, "glDeleteProgram");
pub const glad_glGetUniformLocation = proc(fn (program: c_uint, name: [*c]const u8) callconv(.c) c_int, "glGetUniformLocation");
pub const glad_glGetAttribLocation = proc(fn (program: c_uint, name: [*c]const u8) callconv(.c) c_int, "glGetAttribLocation");

// --- Uniforms -------------------------------------------------------------------
pub const glad_glUniform1fv = proc(fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void, "glUniform1fv");
pub const glad_glUniform2fv = proc(fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void, "glUniform2fv");
pub const glad_glUniform3fv = proc(fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void, "glUniform3fv");
pub const glad_glUniform4fv = proc(fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void, "glUniform4fv");
pub const glad_glUniform1iv = proc(fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void, "glUniform1iv");
pub const glad_glUniform2iv = proc(fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void, "glUniform2iv");
pub const glad_glUniform3iv = proc(fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void, "glUniform3iv");
pub const glad_glUniform4iv = proc(fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void, "glUniform4iv");
pub const glad_glUniform1uiv = proc(fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void, "glUniform1uiv");
pub const glad_glUniform2uiv = proc(fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void, "glUniform2uiv");
pub const glad_glUniform3uiv = proc(fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void, "glUniform3uiv");
pub const glad_glUniform4uiv = proc(fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void, "glUniform4uiv");
pub const glad_glUniform1i = proc(fn (location: c_int, v0: c_int) callconv(.c) void, "glUniform1i");
pub const glad_glUniform4f = proc(fn (location: c_int, v0: f32, v1: f32, v2: f32, v3: f32) callconv(.c) void, "glUniform4f");
pub const glad_glUniformMatrix4fv = proc(fn (location: c_int, count: c_int, transpose: u8, value: [*c]const f32) callconv(.c) void, "glUniformMatrix4fv");

// --- Framebuffers / renderbuffers -----------------------------------------------
pub const glad_glGenFramebuffers = proc(fn (n: c_int, framebuffers: [*c]c_uint) callconv(.c) void, "glGenFramebuffers");
pub const glad_glBindFramebuffer = proc(fn (target: c_uint, framebuffer: c_uint) callconv(.c) void, "glBindFramebuffer");
pub const glad_glDeleteFramebuffers = proc(fn (n: c_int, framebuffers: [*c]const c_uint) callconv(.c) void, "glDeleteFramebuffers");
pub const glad_glFramebufferTexture2D = proc(fn (target: c_uint, attachment: c_uint, textarget: c_uint, texture: c_uint, level: c_int) callconv(.c) void, "glFramebufferTexture2D");
pub const glad_glFramebufferRenderbuffer = proc(fn (target: c_uint, attachment: c_uint, renderbuffertarget: c_uint, renderbuffer: c_uint) callconv(.c) void, "glFramebufferRenderbuffer");
pub const glad_glCheckFramebufferStatus = proc(fn (target: c_uint) callconv(.c) c_uint, "glCheckFramebufferStatus");
pub const glad_glGetFramebufferAttachmentParameteriv = proc(fn (target: c_uint, attachment: c_uint, pname: c_uint, params: [*c]c_int) callconv(.c) void, "glGetFramebufferAttachmentParameteriv");
pub const glad_glGenRenderbuffers = proc(fn (n: c_int, renderbuffers: [*c]c_uint) callconv(.c) void, "glGenRenderbuffers");
pub const glad_glBindRenderbuffer = proc(fn (target: c_uint, renderbuffer: c_uint) callconv(.c) void, "glBindRenderbuffer");
pub const glad_glRenderbufferStorage = proc(fn (target: c_uint, internalformat: c_uint, width: c_int, height: c_int) callconv(.c) void, "glRenderbufferStorage");
pub const glad_glDeleteRenderbuffers = proc(fn (n: c_int, renderbuffers: [*c]const c_uint) callconv(.c) void, "glDeleteRenderbuffers");
pub const glad_glDrawBuffers = proc(fn (n: c_int, bufs: [*c]const c_uint) callconv(.c) void, "glDrawBuffers");
pub const glad_glBlitFramebuffer = proc(fn (srcX0: c_int, srcY0: c_int, srcX1: c_int, srcY1: c_int, dstX0: c_int, dstY0: c_int, dstX1: c_int, dstY1: c_int, mask: c_uint, filter: c_uint) callconv(.c) void, "glBlitFramebuffer");

//----------------------------------------------------------------------------------
// GL enum constants (exact values from external/glad.h). A wrong value silently
// mis-renders, so these are copied verbatim.
//----------------------------------------------------------------------------------
pub const GL_FALSE: c_uint = 0;
pub const GL_TRUE: c_uint = 1;
pub const GL_NO_ERROR: c_uint = 0;

pub const GL_DEPTH_BUFFER_BIT: c_uint = 0x00000100;
pub const GL_COLOR_BUFFER_BIT: c_uint = 0x00004000;

pub const GL_LINES: c_uint = 0x0001;
pub const GL_TRIANGLES: c_uint = 0x0004;
pub const GL_TRIANGLE_STRIP: c_uint = 0x0005;

pub const GL_LEQUAL: c_uint = 0x0203;
pub const GL_FRONT: c_uint = 0x0404;
pub const GL_BACK: c_uint = 0x0405;
pub const GL_FRONT_AND_BACK: c_uint = 0x0408;
pub const GL_CCW: c_uint = 0x0901;

pub const GL_BLEND: c_uint = 0x0BE2;
pub const GL_DEPTH_TEST: c_uint = 0x0B71;
pub const GL_CULL_FACE: c_uint = 0x0B44;
pub const GL_SCISSOR_TEST: c_uint = 0x0C11;
pub const GL_LINE_WIDTH: c_uint = 0x0B21;
pub const GL_POINT_SIZE: c_uint = 0x0B11;

pub const GL_SRC_ALPHA: c_uint = 0x0302;
pub const GL_ONE_MINUS_SRC_ALPHA: c_uint = 0x0303;
pub const GL_ONE: c_uint = 1;
pub const GL_DST_COLOR: c_uint = 0x0306;
pub const GL_FUNC_ADD: c_uint = 0x8006;
pub const GL_FUNC_SUBTRACT: c_uint = 0x800A;

pub const GL_FLOAT: c_uint = 0x1406;
pub const GL_UNSIGNED_BYTE: c_uint = 0x1401;
pub const GL_UNSIGNED_INT: c_uint = 0x1405;
pub const GL_UNSIGNED_SHORT: c_uint = 0x1403;
pub const GL_HALF_FLOAT: c_uint = 0x140B;
pub const GL_UNSIGNED_SHORT_5_6_5: c_uint = 0x8363;
pub const GL_UNSIGNED_SHORT_5_5_5_1: c_uint = 0x8034;
pub const GL_UNSIGNED_SHORT_4_4_4_4: c_uint = 0x8033;

pub const GL_VERTEX_SHADER: c_uint = 0x8B31;
pub const GL_FRAGMENT_SHADER: c_uint = 0x8B30;
pub const GL_COMPUTE_SHADER: c_uint = 0x91B9;
pub const GL_COMPILE_STATUS: c_uint = 0x8B81;
pub const GL_LINK_STATUS: c_uint = 0x8B82;
pub const GL_INFO_LOG_LENGTH: c_uint = 0x8B84;

pub const GL_NUM_EXTENSIONS: c_uint = 0x821D;
pub const GL_EXTENSIONS: c_uint = 0x1F03;
pub const GL_VENDOR: c_uint = 0x1F00;
pub const GL_RENDERER: c_uint = 0x1F01;
pub const GL_VERSION: c_uint = 0x1F02;
pub const GL_SHADING_LANGUAGE_VERSION: c_uint = 0x8B8C;

pub const GL_UNPACK_ALIGNMENT: c_uint = 0x0CF5;
pub const GL_PACK_ALIGNMENT: c_uint = 0x0D05;

pub const GL_TEXTURE0: c_uint = 0x84C0;
pub const GL_TEXTURE_2D: c_uint = 0x0DE1;
pub const GL_TEXTURE_CUBE_MAP: c_uint = 0x8513;
pub const GL_TEXTURE_CUBE_MAP_POSITIVE_X: c_uint = 0x8515;

pub const GL_TEXTURE_WRAP_S: c_uint = 0x2802;
pub const GL_TEXTURE_WRAP_T: c_uint = 0x2803;
pub const GL_TEXTURE_WRAP_R: c_uint = 0x8072;
pub const GL_REPEAT: c_uint = 0x2901;
pub const GL_CLAMP_TO_EDGE: c_uint = 0x812F;
pub const GL_TEXTURE_MAG_FILTER: c_uint = 0x2800;
pub const GL_TEXTURE_MIN_FILTER: c_uint = 0x2801;
pub const GL_NEAREST: c_uint = 0x2600;
pub const GL_LINEAR: c_uint = 0x2601;
pub const GL_LINEAR_MIPMAP_LINEAR: c_uint = 0x2703;
pub const GL_TEXTURE_BASE_LEVEL: c_uint = 0x813C;
pub const GL_TEXTURE_MAX_LEVEL: c_uint = 0x813D;
pub const GL_TEXTURE_MAX_ANISOTROPY_EXT: c_uint = 0x84FE;
pub const GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT: c_uint = 0x84FF;

pub const GL_RED: c_uint = 0x1903;
pub const GL_GREEN: c_uint = 0x1904;
pub const GL_RG: c_uint = 0x8227;
pub const GL_RGB: c_uint = 0x1907;
pub const GL_RGBA: c_uint = 0x1908;
pub const GL_R8: c_uint = 0x8229;
pub const GL_RG8: c_uint = 0x822B;
pub const GL_RGB8: c_uint = 0x8051;
pub const GL_RGBA8: c_uint = 0x8058;
pub const GL_RGB565: c_uint = 0x8D62;
pub const GL_RGB5_A1: c_uint = 0x8057;
pub const GL_RGBA4: c_uint = 0x8056;
pub const GL_R32F: c_uint = 0x822E;
pub const GL_RGB32F: c_uint = 0x8815;
pub const GL_RGBA32F: c_uint = 0x8814;
pub const GL_R16F: c_uint = 0x822D;
pub const GL_RGB16F: c_uint = 0x881B;
pub const GL_RGBA16F: c_uint = 0x881A;

// Compressed formats (some come from rlgl.h #ifndef blocks, not glad.h)
pub const GL_COMPRESSED_RGB_S3TC_DXT1_EXT: c_uint = 0x83F0;
pub const GL_COMPRESSED_RGBA_S3TC_DXT1_EXT: c_uint = 0x83F1;
pub const GL_COMPRESSED_RGBA_S3TC_DXT3_EXT: c_uint = 0x83F2;
pub const GL_COMPRESSED_RGBA_S3TC_DXT5_EXT: c_uint = 0x83F3;
pub const GL_ETC1_RGB8_OES: c_uint = 0x8D64;
pub const GL_COMPRESSED_RGB8_ETC2: c_uint = 0x9274;
pub const GL_COMPRESSED_RGBA8_ETC2_EAC: c_uint = 0x9278;
pub const GL_COMPRESSED_RGB_PVRTC_4BPPV1_IMG: c_uint = 0x8C00;
pub const GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG: c_uint = 0x8C02;
pub const GL_COMPRESSED_RGBA_ASTC_4x4_KHR: c_uint = 0x93B0;
pub const GL_COMPRESSED_RGBA_ASTC_8x8_KHR: c_uint = 0x93B7;

pub const GL_ARRAY_BUFFER: c_uint = 0x8892;
pub const GL_ELEMENT_ARRAY_BUFFER: c_uint = 0x8893;
pub const GL_STATIC_DRAW: c_uint = 0x88E4;
pub const GL_DYNAMIC_DRAW: c_uint = 0x88E8;

pub const GL_FRAMEBUFFER: c_uint = 0x8D40;
pub const GL_READ_FRAMEBUFFER: c_uint = 0x8CA8;
pub const GL_DRAW_FRAMEBUFFER: c_uint = 0x8CA9;
pub const GL_DRAW_FRAMEBUFFER_BINDING: c_uint = 0x8CA6;
pub const GL_RENDERBUFFER: c_uint = 0x8D41;
pub const GL_TEXTURE: c_uint = 0x1702;
pub const GL_DEPTH_COMPONENT: c_uint = 0x1902;
pub const GL_DEPTH_ATTACHMENT: c_uint = 0x8D00;
pub const GL_STENCIL_ATTACHMENT: c_uint = 0x8D20;
pub const GL_COLOR_ATTACHMENT0: c_uint = 0x8CE0;
pub const GL_FRAMEBUFFER_COMPLETE: c_uint = 0x8CD5;
pub const GL_FRAMEBUFFER_UNSUPPORTED: c_uint = 0x8CDD;
pub const GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT: c_uint = 0x8CD6;
pub const GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT: c_uint = 0x8CD7;
pub const GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE: c_uint = 0x8CD0;
pub const GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME: c_uint = 0x8CD1;

// --- OpenGL ES only -----------------------------------------------------------------
pub const GL_LUMINANCE: c_uint = 0x1909;
pub const GL_LUMINANCE_ALPHA: c_uint = 0x190A;
pub const GL_DEPTH_COMPONENT16: c_uint = 0x81A5;
pub const GL_DEPTH_COMPONENT24: c_uint = 0x81A6;
pub const GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS: c_uint = 0x8CD9;

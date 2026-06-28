//! gl33 - GLAD OpenGL 3.3 Core function-pointer externs for the rlgl Zig port.
//!
//! rlgl.h calls OpenGL through GLAD macros like `glClear(...)` that the C
//! preprocessor expands to the function pointer `glad_glClear`. Zig cannot use C
//! macros, so we declare those `glad_gl*` pointers directly as `extern var`
//! (resolved at link time from `src/c/glad_impl.c`, which instantiates GLAD) and
//! call them with `.?(...)`. Only the GL 3.3 Core entry points actually used by
//! the rlgl port are declared here.
//!
//! GL type mapping (from external/glad.h):
//!   GLenum/GLuint/GLbitfield = c_uint   GLint/GLsizei = c_int
//!   GLfloat = f32   GLdouble = f64      GLboolean/GLubyte/GLchar = u8
//!   GLintptr = isize   GLsizeiptr = usize   void*/GLvoid = anyopaque

// GLADapiproc is `void (*)(void)`; the loader returns one of these per name.
pub const GladApiProc = ?*const fn () callconv(.c) void;
pub const GladLoadFunc = ?*const fn (name: [*c]const u8) callconv(.c) GladApiProc;

pub extern fn gladLoadGL(load: GladLoadFunc) c_int;

// GLAD extension-presence flags (int, set by gladLoadGL).
pub extern var GLAD_GL_KHR_texture_compression_astc_hdr: c_int;
pub extern var GLAD_GL_KHR_texture_compression_astc_ldr: c_int;
pub extern var GLAD_GL_EXT_texture_compression_s3tc: c_int;
pub extern var GLAD_GL_ARB_ES3_compatibility: c_int;

// --- State / clear / viewport ---------------------------------------------------
pub extern var glad_glClearColor: ?*const fn (red: f32, green: f32, blue: f32, alpha: f32) callconv(.c) void;
pub extern var glad_glClear: ?*const fn (mask: c_uint) callconv(.c) void;
pub extern var glad_glClearDepth: ?*const fn (depth: f64) callconv(.c) void;
pub extern var glad_glViewport: ?*const fn (x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void;
pub extern var glad_glScissor: ?*const fn (x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void;
pub extern var glad_glEnable: ?*const fn (cap: c_uint) callconv(.c) void;
pub extern var glad_glDisable: ?*const fn (cap: c_uint) callconv(.c) void;
pub extern var glad_glDepthFunc: ?*const fn (func: c_uint) callconv(.c) void;
pub extern var glad_glDepthMask: ?*const fn (flag: u8) callconv(.c) void;
pub extern var glad_glCullFace: ?*const fn (mode: c_uint) callconv(.c) void;
pub extern var glad_glFrontFace: ?*const fn (mode: c_uint) callconv(.c) void;
pub extern var glad_glColorMask: ?*const fn (red: u8, green: u8, blue: u8, alpha: u8) callconv(.c) void;
pub extern var glad_glPolygonMode: ?*const fn (face: c_uint, mode: c_uint) callconv(.c) void;
pub extern var glad_glLineWidth: ?*const fn (width: f32) callconv(.c) void;

// --- Blending -------------------------------------------------------------------
pub extern var glad_glBlendFunc: ?*const fn (sfactor: c_uint, dfactor: c_uint) callconv(.c) void;
pub extern var glad_glBlendEquation: ?*const fn (mode: c_uint) callconv(.c) void;
pub extern var glad_glBlendFuncSeparate: ?*const fn (sfactorRGB: c_uint, dfactorRGB: c_uint, sfactorAlpha: c_uint, dfactorAlpha: c_uint) callconv(.c) void;
pub extern var glad_glBlendEquationSeparate: ?*const fn (modeRGB: c_uint, modeAlpha: c_uint) callconv(.c) void;

// --- Queries --------------------------------------------------------------------
pub extern var glad_glGetFloatv: ?*const fn (pname: c_uint, data: [*c]f32) callconv(.c) void;
pub extern var glad_glGetIntegerv: ?*const fn (pname: c_uint, data: [*c]c_int) callconv(.c) void;
pub extern var glad_glGetError: ?*const fn () callconv(.c) c_uint;
pub extern var glad_glGetString: ?*const fn (name: c_uint) callconv(.c) [*c]const u8;
pub extern var glad_glGetStringi: ?*const fn (name: c_uint, index: c_uint) callconv(.c) [*c]const u8;
pub extern var glad_glPixelStorei: ?*const fn (pname: c_uint, param: c_int) callconv(.c) void;

// --- Textures -------------------------------------------------------------------
pub extern var glad_glActiveTexture: ?*const fn (texture: c_uint) callconv(.c) void;
pub extern var glad_glBindTexture: ?*const fn (target: c_uint, texture: c_uint) callconv(.c) void;
pub extern var glad_glGenTextures: ?*const fn (n: c_int, textures: [*c]c_uint) callconv(.c) void;
pub extern var glad_glDeleteTextures: ?*const fn (n: c_int, textures: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glTexParameteri: ?*const fn (target: c_uint, pname: c_uint, param: c_int) callconv(.c) void;
pub extern var glad_glTexParameterf: ?*const fn (target: c_uint, pname: c_uint, param: f32) callconv(.c) void;
pub extern var glad_glTexParameteriv: ?*const fn (target: c_uint, pname: c_uint, params: [*c]const c_int) callconv(.c) void;
pub extern var glad_glTexImage2D: ?*const fn (target: c_uint, level: c_int, internalformat: c_int, width: c_int, height: c_int, border: c_int, format: c_uint, type: c_uint, pixels: ?*const anyopaque) callconv(.c) void;
pub extern var glad_glCompressedTexImage2D: ?*const fn (target: c_uint, level: c_int, internalformat: c_uint, width: c_int, height: c_int, border: c_int, imageSize: c_int, data: ?*const anyopaque) callconv(.c) void;
pub extern var glad_glTexSubImage2D: ?*const fn (target: c_uint, level: c_int, xoffset: c_int, yoffset: c_int, width: c_int, height: c_int, format: c_uint, type: c_uint, pixels: ?*const anyopaque) callconv(.c) void;
pub extern var glad_glGenerateMipmap: ?*const fn (target: c_uint) callconv(.c) void;
pub extern var glad_glGetTexImage: ?*const fn (target: c_uint, level: c_int, format: c_uint, type: c_uint, pixels: ?*anyopaque) callconv(.c) void;
pub extern var glad_glReadPixels: ?*const fn (x: c_int, y: c_int, width: c_int, height: c_int, format: c_uint, type: c_uint, pixels: ?*anyopaque) callconv(.c) void;

// --- Vertex arrays / buffers ----------------------------------------------------
pub extern var glad_glGenVertexArrays: ?*const fn (n: c_int, arrays: [*c]c_uint) callconv(.c) void;
pub extern var glad_glBindVertexArray: ?*const fn (array: c_uint) callconv(.c) void;
pub extern var glad_glDeleteVertexArrays: ?*const fn (n: c_int, arrays: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glGenBuffers: ?*const fn (n: c_int, buffers: [*c]c_uint) callconv(.c) void;
pub extern var glad_glBindBuffer: ?*const fn (target: c_uint, buffer: c_uint) callconv(.c) void;
pub extern var glad_glBufferData: ?*const fn (target: c_uint, size: isize, data: ?*const anyopaque, usage: c_uint) callconv(.c) void;
pub extern var glad_glBufferSubData: ?*const fn (target: c_uint, offset: isize, size: isize, data: ?*const anyopaque) callconv(.c) void;
pub extern var glad_glDeleteBuffers: ?*const fn (n: c_int, buffers: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glEnableVertexAttribArray: ?*const fn (index: c_uint) callconv(.c) void;
pub extern var glad_glDisableVertexAttribArray: ?*const fn (index: c_uint) callconv(.c) void;
pub extern var glad_glVertexAttribPointer: ?*const fn (index: c_uint, size: c_int, type: c_uint, normalized: u8, stride: c_int, pointer: ?*const anyopaque) callconv(.c) void;
pub extern var glad_glVertexAttribDivisor: ?*const fn (index: c_uint, divisor: c_uint) callconv(.c) void;
pub extern var glad_glDrawArrays: ?*const fn (mode: c_uint, first: c_int, count: c_int) callconv(.c) void;
pub extern var glad_glDrawElements: ?*const fn (mode: c_uint, count: c_int, type: c_uint, indices: ?*const anyopaque) callconv(.c) void;
pub extern var glad_glDrawArraysInstanced: ?*const fn (mode: c_uint, first: c_int, count: c_int, instancecount: c_int) callconv(.c) void;
pub extern var glad_glDrawElementsInstanced: ?*const fn (mode: c_uint, count: c_int, type: c_uint, indices: ?*const anyopaque, instancecount: c_int) callconv(.c) void;

// --- Vertex attrib default values -----------------------------------------------
pub extern var glad_glVertexAttrib1fv: ?*const fn (index: c_uint, v: [*c]const f32) callconv(.c) void;
pub extern var glad_glVertexAttrib2fv: ?*const fn (index: c_uint, v: [*c]const f32) callconv(.c) void;
pub extern var glad_glVertexAttrib3fv: ?*const fn (index: c_uint, v: [*c]const f32) callconv(.c) void;
pub extern var glad_glVertexAttrib4fv: ?*const fn (index: c_uint, v: [*c]const f32) callconv(.c) void;

// --- Shaders / programs ---------------------------------------------------------
pub extern var glad_glUseProgram: ?*const fn (program: c_uint) callconv(.c) void;
pub extern var glad_glCreateShader: ?*const fn (type: c_uint) callconv(.c) c_uint;
pub extern var glad_glShaderSource: ?*const fn (shader: c_uint, count: c_int, string: [*c]const [*c]const u8, length: [*c]const c_int) callconv(.c) void;
pub extern var glad_glCompileShader: ?*const fn (shader: c_uint) callconv(.c) void;
pub extern var glad_glGetShaderiv: ?*const fn (shader: c_uint, pname: c_uint, params: [*c]c_int) callconv(.c) void;
pub extern var glad_glGetShaderInfoLog: ?*const fn (shader: c_uint, bufSize: c_int, length: [*c]c_int, infoLog: [*c]u8) callconv(.c) void;
pub extern var glad_glDeleteShader: ?*const fn (shader: c_uint) callconv(.c) void;
pub extern var glad_glCreateProgram: ?*const fn () callconv(.c) c_uint;
pub extern var glad_glAttachShader: ?*const fn (program: c_uint, shader: c_uint) callconv(.c) void;
pub extern var glad_glDetachShader: ?*const fn (program: c_uint, shader: c_uint) callconv(.c) void;
pub extern var glad_glBindAttribLocation: ?*const fn (program: c_uint, index: c_uint, name: [*c]const u8) callconv(.c) void;
pub extern var glad_glLinkProgram: ?*const fn (program: c_uint) callconv(.c) void;
pub extern var glad_glGetProgramiv: ?*const fn (program: c_uint, pname: c_uint, params: [*c]c_int) callconv(.c) void;
pub extern var glad_glGetProgramInfoLog: ?*const fn (program: c_uint, bufSize: c_int, length: [*c]c_int, infoLog: [*c]u8) callconv(.c) void;
pub extern var glad_glDeleteProgram: ?*const fn (program: c_uint) callconv(.c) void;
pub extern var glad_glGetUniformLocation: ?*const fn (program: c_uint, name: [*c]const u8) callconv(.c) c_int;
pub extern var glad_glGetAttribLocation: ?*const fn (program: c_uint, name: [*c]const u8) callconv(.c) c_int;

// --- Uniforms -------------------------------------------------------------------
pub extern var glad_glUniform1fv: ?*const fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void;
pub extern var glad_glUniform2fv: ?*const fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void;
pub extern var glad_glUniform3fv: ?*const fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void;
pub extern var glad_glUniform4fv: ?*const fn (location: c_int, count: c_int, value: [*c]const f32) callconv(.c) void;
pub extern var glad_glUniform1iv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void;
pub extern var glad_glUniform2iv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void;
pub extern var glad_glUniform3iv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void;
pub extern var glad_glUniform4iv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_int) callconv(.c) void;
pub extern var glad_glUniform1uiv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glUniform2uiv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glUniform3uiv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glUniform4uiv: ?*const fn (location: c_int, count: c_int, value: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glUniform1i: ?*const fn (location: c_int, v0: c_int) callconv(.c) void;
pub extern var glad_glUniform4f: ?*const fn (location: c_int, v0: f32, v1: f32, v2: f32, v3: f32) callconv(.c) void;
pub extern var glad_glUniformMatrix4fv: ?*const fn (location: c_int, count: c_int, transpose: u8, value: [*c]const f32) callconv(.c) void;

// --- Framebuffers / renderbuffers -----------------------------------------------
pub extern var glad_glGenFramebuffers: ?*const fn (n: c_int, framebuffers: [*c]c_uint) callconv(.c) void;
pub extern var glad_glBindFramebuffer: ?*const fn (target: c_uint, framebuffer: c_uint) callconv(.c) void;
pub extern var glad_glDeleteFramebuffers: ?*const fn (n: c_int, framebuffers: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glFramebufferTexture2D: ?*const fn (target: c_uint, attachment: c_uint, textarget: c_uint, texture: c_uint, level: c_int) callconv(.c) void;
pub extern var glad_glFramebufferRenderbuffer: ?*const fn (target: c_uint, attachment: c_uint, renderbuffertarget: c_uint, renderbuffer: c_uint) callconv(.c) void;
pub extern var glad_glCheckFramebufferStatus: ?*const fn (target: c_uint) callconv(.c) c_uint;
pub extern var glad_glGetFramebufferAttachmentParameteriv: ?*const fn (target: c_uint, attachment: c_uint, pname: c_uint, params: [*c]c_int) callconv(.c) void;
pub extern var glad_glGenRenderbuffers: ?*const fn (n: c_int, renderbuffers: [*c]c_uint) callconv(.c) void;
pub extern var glad_glBindRenderbuffer: ?*const fn (target: c_uint, renderbuffer: c_uint) callconv(.c) void;
pub extern var glad_glRenderbufferStorage: ?*const fn (target: c_uint, internalformat: c_uint, width: c_int, height: c_int) callconv(.c) void;
pub extern var glad_glDeleteRenderbuffers: ?*const fn (n: c_int, renderbuffers: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glDrawBuffers: ?*const fn (n: c_int, bufs: [*c]const c_uint) callconv(.c) void;
pub extern var glad_glBlitFramebuffer: ?*const fn (srcX0: c_int, srcY0: c_int, srcX1: c_int, srcY1: c_int, dstX0: c_int, dstY0: c_int, dstX1: c_int, dstY1: c_int, mask: c_uint, filter: c_uint) callconv(.c) void;

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

pub const GL_POINT: c_uint = 0x1B00;
pub const GL_LINE: c_uint = 0x1B01;
pub const GL_FILL: c_uint = 0x1B02;

pub const GL_BLEND: c_uint = 0x0BE2;
pub const GL_DEPTH_TEST: c_uint = 0x0B71;
pub const GL_CULL_FACE: c_uint = 0x0B44;
pub const GL_SCISSOR_TEST: c_uint = 0x0C11;
pub const GL_LINE_SMOOTH: c_uint = 0x0B20;
pub const GL_LINE_WIDTH: c_uint = 0x0B21;
pub const GL_POINT_SIZE: c_uint = 0x0B11;
pub const GL_PROGRAM_POINT_SIZE: c_uint = 0x8642;
pub const GL_TEXTURE_CUBE_MAP_SEAMLESS: c_uint = 0x884F;

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
pub const GL_TEXTURE_SWIZZLE_RGBA: c_uint = 0x8E46;
pub const GL_TEXTURE_LOD_BIAS: c_uint = 0x8501;
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

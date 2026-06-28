// rlgl_impl_defs.h — RL_DEFAULT_SHADER_* name constants that rlgl.h defines only
// inside its RLGL_IMPLEMENTATION block. When rlgl is ported to Zig that block is
// disabled (RAYLIB_ZIG_NO_RLGL_IMPL), but rcore.c/rmodels.c still reference these
// constants for shader-location setup — so we provide them here, force-included
// (-include) into the C compiles. Values copied verbatim from rlgl.h (#ifndef-
// guarded there, so no conflict). See vendor/README.md.
#ifndef RAYLIB_ZIG_RLGL_IMPL_DEFS_H
#define RAYLIB_ZIG_RLGL_IMPL_DEFS_H

#define RL_DEFAULT_SHADER_ATTRIB_NAME_POSITION          "vertexPosition"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD          "vertexTexCoord"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_NORMAL            "vertexNormal"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_COLOR             "vertexColor"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_TANGENT           "vertexTangent"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_TEXCOORD2         "vertexTexCoord2"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_BONEINDICES       "vertexBoneIndices"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_BONEWEIGHTS       "vertexBoneWeights"
#define RL_DEFAULT_SHADER_ATTRIB_NAME_INSTANCETRANSFORM "instanceTransform"

#define RL_DEFAULT_SHADER_UNIFORM_NAME_MVP          "mvp"
#define RL_DEFAULT_SHADER_UNIFORM_NAME_VIEW         "matView"
#define RL_DEFAULT_SHADER_UNIFORM_NAME_PROJECTION   "matProjection"
#define RL_DEFAULT_SHADER_UNIFORM_NAME_MODEL        "matModel"
#define RL_DEFAULT_SHADER_UNIFORM_NAME_NORMAL       "matNormal"
#define RL_DEFAULT_SHADER_UNIFORM_NAME_COLOR        "colDiffuse"
#define RL_DEFAULT_SHADER_UNIFORM_NAME_BONEMATRICES "boneMatrices"

#define RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE0   "texture0"
#define RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE1   "texture1"
#define RL_DEFAULT_SHADER_SAMPLER2D_NAME_TEXTURE2   "texture2"

#endif

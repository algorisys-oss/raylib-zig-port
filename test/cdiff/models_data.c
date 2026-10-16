// models_data.c — C-vs-Zig differential for rmodels' CPU-side data paths.
//
// The examples gate draws a handful of models; it never compares the loaded
// data itself, and never reaches several loaders (VOX, M3D, IQM animations,
// .gltf with data-URI and external buffers/images), the exporters, the
// GenMesh* parameter space, or the collision functions' edge cases. This
// program loads every model under the resource directories given on the
// command line, prints checksums of every array a Model/Mesh/Material/
// ModelAnimation carries, poses each model through its animations, exports
// meshes to OBJ and C-header text and prints those bytes, and sweeps the
// generators and collision functions. Every TraceLog line goes through a log
// callback so log text is compared too. A hidden window provides the GL
// context the loaders upload into. Run via tools/cdiff.sh.
#define _XOPEN_SOURCE 700
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "raylib.h"

static void logCallback(int level, const char *text, va_list args)
{
    char line[4096];
    vsnprintf(line, sizeof(line), text, args);

    // raylib's M3D animation log passes an unsigned int to "%f": the printed
    // duration is whatever xmm0 held (undefined behaviour), so drop it
    char *duration = strstr(line, "| Duration: ");
    if ((duration != NULL) && (strstr(line, ".m3d]") != NULL)) strcpy(duration, "| Duration: (undefined)");

    printf("  log %d: %s\n", level, line);
}

static unsigned int hashBytes(const void *data, size_t size)
{
    const unsigned char *p = data;
    unsigned int h = 2166136261u;
    for (size_t i = 0; (p != NULL) && (i < size); i++) h = (h ^ p[i])*16777619u;
    return h;
}

static void printArray(const char *what, const void *data, size_t size)
{
    if (data == NULL) printf("   %s: NULL\n", what);
    else printf("   %s: %08x\n", what, hashBytes(data, size));
}

static void printMesh(const char *what, Mesh mesh)
{
    size_t vc = (mesh.vertexCount > 0)? (size_t)mesh.vertexCount : 0;
    size_t tc = (mesh.triangleCount > 0)? (size_t)mesh.triangleCount : 0;
    printf("  %s: vertexCount=%d triangleCount=%d boneCount=%d vao=%s\n", what, mesh.vertexCount,
        mesh.triangleCount, mesh.boneCount, (mesh.vaoId > 0)? "yes" : "no");
    printArray("vertices", mesh.vertices, vc*3*sizeof(float));
    printArray("texcoords", mesh.texcoords, vc*2*sizeof(float));
    printArray("texcoords2", mesh.texcoords2, vc*2*sizeof(float));
    printArray("normals", mesh.normals, vc*3*sizeof(float));
    printArray("tangents", mesh.tangents, vc*4*sizeof(float));
    printArray("colors", mesh.colors, vc*4);
    printArray("indices", mesh.indices, tc*3*sizeof(unsigned short));
    printArray("boneIndices", mesh.boneIndices, vc*4);
    printArray("boneWeights", mesh.boneWeights, vc*4*sizeof(float));
    printArray("animVertices", mesh.animVertices, vc*3*sizeof(float));
    printArray("animNormals", mesh.animNormals, vc*3*sizeof(float));
    if (mesh.vboId != NULL)
    {
        printf("   vbo:");
        for (int i = 0; i < 9; i++) printf(" %u", mesh.vboId[i]);
        printf("\n");
    }
    BoundingBox box = GetMeshBoundingBox(mesh);
    printf("   box: %a %a %a / %a %a %a\n", box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z);
}

static void printMaterial(int index, Material material)
{
    printf("  material %d: shader=%u locs=%s valid=%d params=%a,%a,%a,%a\n", index, material.shader.id,
        (material.shader.locs != NULL)? "set" : "NULL", IsMaterialValid(material),
        material.params[0], material.params[1], material.params[2], material.params[3]);
    for (int m = 0; (material.maps != NULL) && (m < 12); m++)
    {
        MaterialMap map = material.maps[m];
        printf("   map %d: tex=%u %dx%d mips=%d fmt=%d color=%d,%d,%d,%d value=%a\n", m, map.texture.id,
            map.texture.width, map.texture.height, map.texture.mipmaps, map.texture.format,
            map.color.r, map.color.g, map.color.b, map.color.a, map.value);
    }
}

static void printPose(const char *what, Model model)
{
    unsigned int bc = model.skeleton.boneCount;
    printArray(what, model.currentPose, bc*sizeof(Transform));
    printArray("boneMatrices", model.boneMatrices, bc*sizeof(Matrix));
    for (int i = 0; i < model.meshCount; i++)
    {
        size_t vc = model.meshes[i].vertexCount;
        printf("   mesh %d", i);
        printArray("animVertices", model.meshes[i].animVertices, vc*3*sizeof(float));
        printf("   mesh %d", i);
        printArray("animNormals", model.meshes[i].animNormals, vc*3*sizeof(float));
    }
}

static void printModel(Model model)
{
    printf("  valid=%d meshCount=%d materialCount=%d\n", IsModelValid(model), model.meshCount, model.materialCount);
    printArray("transform", &model.transform, sizeof(Matrix));
    printArray("meshMaterial", model.meshMaterial, (model.meshCount > 0)? model.meshCount*sizeof(int) : 0);
    for (int i = 0; i < model.meshCount; i++)
    {
        char what[32];
        snprintf(what, sizeof(what), "mesh %d", i);
        printMesh(what, model.meshes[i]);
    }
    for (int i = 0; i < model.materialCount; i++) printMaterial(i, model.materials[i]);

    printf("  skeleton boneCount=%u\n", model.skeleton.boneCount);
    for (unsigned int i = 0; (model.skeleton.bones != NULL) && (i < model.skeleton.boneCount); i++)
    {
        printf("   bone %u: [%s] parent=%d raw=%08x\n", i, model.skeleton.bones[i].name,
            model.skeleton.bones[i].parent, hashBytes(&model.skeleton.bones[i], sizeof(BoneInfo)));
    }
    printArray("bindPose", model.skeleton.bindPose, model.skeleton.boneCount*sizeof(Transform));
    printPose("currentPose", model);

    BoundingBox box = GetModelBoundingBox(model);
    printf("  model box: %a %a %a / %a %a %a\n", box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z);
}

static void printCollision(const char *what, RayCollision c)
{
    printf("  %s: hit=%d d=%a p=%a,%a,%a n=%a,%a,%a\n", what, c.hit, c.distance,
        c.point.x, c.point.y, c.point.z, c.normal.x, c.normal.y, c.normal.z);
}

static void rayMeshSweep(Model model)
{
    Ray rays[] = {
        { { 0, 10, 0 }, { 0, -1, 0 } },
        { { 0, 1, 10 }, { 0, 0, -1 } },
        { { 10, 1, 0.1f }, { -1, 0, 0 } },
        { { 0.3f, 0.5f, -10 }, { 0, 0.05f, 1 } },
    };
    for (int i = 0; i < model.meshCount; i++)
    {
        for (int r = 0; r < 4; r++)
        {
            char what[32];
            snprintf(what, sizeof(what), "rayMesh %d/%d", i, r);
            printCollision(what, GetRayCollisionMesh(rays[r], model.meshes[i], model.transform));
        }
    }
}

static void printFile(const char *path, bool full)
{
    int size = 0;
    unsigned char *data = LoadFileData(path, &size);
    printf("  file %s: size=%d hash=%08x\n", strrchr(path, '/') + 1, size, hashBytes(data, size));
    if (full && (data != NULL)) fwrite(data, 1, size, stdout);
    UnloadFileData(data);
}

static void exportMesh(const char *dir, const char *name, Mesh mesh, bool full)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.obj", dir, name);
    printf("  ExportMesh(%s.obj)=%d\n", name, ExportMesh(mesh, path));
    printFile(path, full);
    snprintf(path, sizeof(path), "%s/%s.h", dir, name);
    printf("  ExportMeshAsCode(%s.h)=%d\n", name, ExportMeshAsCode(mesh, path));
    printFile(path, full);
}

static void animate(const char *path, Model model)
{
    int animCount = 0;
    ModelAnimation *anims = LoadModelAnimations(path, &animCount);
    printf("  animations: count=%d %s\n", animCount, (anims != NULL)? "data" : "NULL");
    for (int a = 0; (anims != NULL) && (a < animCount); a++)
    {
        size_t poses = (size_t)anims[a].keyframeCount*anims[a].boneCount*sizeof(Transform);
        unsigned int h = 2166136261u;
        for (int k = 0; k < anims[a].keyframeCount; k++) h ^= hashBytes(anims[a].keyframePoses[k], anims[a].boneCount*sizeof(Transform)) + k;
        printf("  anim %d: [%s] boneCount=%u keyframeCount=%d poses=%zu hash=%08x valid=%d\n", a, anims[a].name,
            anims[a].boneCount, anims[a].keyframeCount, poses, h, IsModelAnimationValid(model, anims[a]));
    }

    if ((anims != NULL) && (animCount > 0) && IsModelAnimationValid(model, anims[0]))
    {
        float frames[] = { 0.0f, 1.0f, 2.5f, (float)anims[0].keyframeCount - 0.25f, (float)anims[0].keyframeCount + 3.0f, 0.999f };
        for (int f = 0; f < 6; f++)
        {
            UpdateModelAnimation(model, anims[0], frames[f]);
            printf("  UpdateModelAnimation frame=%a\n", frames[f]);
            printPose("currentPose", model);
        }

        ModelAnimation other = (animCount > 1)? anims[1] : anims[0];
        float blends[] = { 0.0f, 0.3f, 1.0f };
        for (int b = 0; b < 3; b++)
        {
            UpdateModelAnimationEx(model, anims[0], 3.7f, other, 1.2f, blends[b]);
            printf("  UpdateModelAnimationEx blend=%a\n", blends[b]);
            printPose("currentPose", model);
        }
    }

    UnloadModelAnimations(anims, animCount);
}

static void loadOne(const char *dir, const char *path)
{
    printf("== %s\n", strrchr(path, '/')? strrchr(path, '/') + 1 : path);
    Model model = LoadModel(path);
    printModel(model);
    animate(path, model);
    rayMeshSweep(model);
    if ((model.meshCount > 0) && (model.meshes[0].texcoords != NULL) && (model.meshes[0].normals != NULL))
    {
        exportMesh(dir, "loaded", model.meshes[0], false);
    }
    UnloadModel(model);
}

static void loadDir(const char *tmp, const char *dir)
{
    FilePathList files = LoadDirectoryFilesEx(dir, ".obj;.iqm;.glb;.gltf;.vox;.m3d", true);
    // Sort for a stable order: directory listing order is not guaranteed
    for (unsigned int i = 0; i < files.count; i++)
        for (unsigned int j = i + 1; j < files.count; j++)
            if (strcmp(files.paths[i], files.paths[j]) > 0) { char *t = files.paths[i]; files.paths[i] = files.paths[j]; files.paths[j] = t; }
    for (unsigned int i = 0; i < files.count; i++) loadOne(tmp, files.paths[i]);
    UnloadDirectoryFiles(files);
}

static void generators(const char *tmp, const char *resources)
{
    struct { const char *name; Mesh mesh; } gens[] = {
        { "poly3", GenMeshPoly(3, 1.0f) },
        { "poly7", GenMeshPoly(7, 2.5f) },
        { "plane", GenMeshPlane(2.0f, 3.0f, 1, 1) },
        { "plane45", GenMeshPlane(5.0f, 1.5f, 4, 5) },
        { "cube", GenMeshCube(1.0f, 2.0f, 3.0f) },
        { "sphere", GenMeshSphere(1.5f, 8, 12) },
        { "sphere0", GenMeshSphere(0.5f, 3, 3) },
        { "hemi", GenMeshHemiSphere(2.0f, 6, 10) },
        { "hemi0", GenMeshHemiSphere(0.0f, 4, 4) },
        { "cyl", GenMeshCylinder(1.0f, 2.0f, 9) },
        { "cone", GenMeshCone(1.5f, 2.5f, 7) },
        { "torus", GenMeshTorus(0.5f, 1.0f, 12, 8) },
        { "torusbig", GenMeshTorus(2.0f, 3.0f, 5, 3) },
        { "knot", GenMeshKnot(1.0f, 2.0f, 16, 64) },
        { "knotbig", GenMeshKnot(4.0f, 1.0f, 6, 6) },
    };
    int count = (int)(sizeof(gens)/sizeof(gens[0]));

    for (int i = 0; i < count; i++)
    {
        printf("== gen %s\n", gens[i].name);
        printMesh("mesh", gens[i].mesh);
        GenMeshTangents(&gens[i].mesh);
        printArray("tangents after GenMeshTangents", gens[i].mesh.tangents, gens[i].mesh.vertexCount*4*sizeof(float));
        exportMesh(tmp, gens[i].name, gens[i].mesh, (i == 0) || (i == 4));
        Model model = LoadModelFromMesh(gens[i].mesh);
        printModel(model);
        rayMeshSweep(model);
        UnloadModel(model);
    }

    char path[512];
    snprintf(path, sizeof(path), "%s/heightmap.png", resources);
    Image heightmap = LoadImage(path);
    snprintf(path, sizeof(path), "%s/cubicmap.png", resources);
    Image cubicmap = LoadImage(path);

    Vector3 sizes[] = { { 16, 8, 16 }, { 1, 1, 1 }, { 3.5f, 0.25f, 7 } };
    for (int s = 0; s < 3; s++)
    {
        printf("== gen heightmap %d\n", s);
        Mesh mesh = GenMeshHeightmap(heightmap, sizes[s]);
        printMesh("mesh", mesh);
        if (s == 1) exportMesh(tmp, "heightmap", mesh, false);
        UnloadMesh(mesh);

        printf("== gen cubicmap %d\n", s);
        mesh = GenMeshCubicmap(cubicmap, sizes[s]);
        printMesh("mesh", mesh);
        if (s == 1) exportMesh(tmp, "cubicmap", mesh, false);
        UnloadMesh(mesh);
    }

    // Cubicmap from a hand-made image with every neighbour combination
    Image small = GenImageColor(5, 4, BLACK);
    ImageDrawPixel(&small, 1, 1, WHITE);
    ImageDrawPixel(&small, 2, 1, WHITE);
    ImageDrawPixel(&small, 0, 0, WHITE);
    ImageDrawPixel(&small, 4, 3, WHITE);
    ImageDrawPixel(&small, 3, 2, WHITE);
    printf("== gen cubicmap small\n");
    Mesh mesh = GenMeshCubicmap(small, (Vector3){ 1.0f, 1.5f, 0.5f });
    printMesh("mesh", mesh);
    UnloadMesh(mesh);

    // Heightmap from a grayscale image
    Image gray = GenImageGradientRadial(9, 7, 0.2f, WHITE, BLACK);
    ImageFormat(&gray, PIXELFORMAT_UNCOMPRESSED_GRAYSCALE);
    printf("== gen heightmap gray\n");
    mesh = GenMeshHeightmap(gray, (Vector3){ 4.0f, 2.0f, 3.0f });
    printMesh("mesh", mesh);
    UnloadMesh(mesh);

    UnloadImage(gray);
    UnloadImage(small);
    UnloadImage(heightmap);
    UnloadImage(cubicmap);
}

static void collisions(void)
{
    printf("== collisions\n");
    Vector3 c[] = { { 0, 0, 0 }, { 1.5f, 0, 0 }, { 3, 3, 3 }, { 0.5f, -0.5f, 0.25f } };
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            printf("  spheres %d %d: %d\n", i, j, CheckCollisionSpheres(c[i], 1.0f, c[j], 0.6f + j*0.2f));

    BoundingBox boxes[] = {
        { { -1, -1, -1 }, { 1, 1, 1 } },
        { { 0.5f, 0.5f, 0.5f }, { 2, 2, 2 } },
        { { 1, -1, -1 }, { 3, 1, 1 } },
        { { 5, 5, 5 }, { 6, 6, 6 } },
    };
    for (int i = 0; i < 4; i++)
    {
        for (int j = 0; j < 4; j++) printf("  boxes %d %d: %d\n", i, j, CheckCollisionBoxes(boxes[i], boxes[j]));
        for (int j = 0; j < 4; j++) printf("  boxSphere %d %d: %d\n", i, j, CheckCollisionBoxSphere(boxes[i], c[j], 0.75f));
    }

    Ray rays[] = {
        { { 0, 0, -5 }, { 0, 0, 1 } },
        { { 0, 0, 0 }, { 0, 1, 0 } },
        { { 3, 0.2f, -5 }, { 0, 0, 1 } },
        { { -4, 3, 2 }, { 1, -0.5f, -0.3f } },
        { { 1, 1, 1 }, { 0, 0, 0 } },
    };
    for (int r = 0; r < 5; r++)
    {
        char what[64];
        for (int i = 0; i < 4; i++)
        {
            snprintf(what, sizeof(what), "raySphere %d %d", r, i);
            printCollision(what, GetRayCollisionSphere(rays[r], c[i], 1.0f));
            snprintf(what, sizeof(what), "rayBox %d %d", r, i);
            printCollision(what, GetRayCollisionBox(rays[r], boxes[i]));
        }
        snprintf(what, sizeof(what), "rayTriangle %d", r);
        printCollision(what, GetRayCollisionTriangle(rays[r], (Vector3){ -1, -1, 0 }, (Vector3){ 1, -1, 0 }, (Vector3){ 0, 1, 0 }));
        snprintf(what, sizeof(what), "rayTriangleBack %d", r);
        printCollision(what, GetRayCollisionTriangle(rays[r], (Vector3){ 0, 1, 0 }, (Vector3){ 1, -1, 0 }, (Vector3){ -1, -1, 0 }));
        snprintf(what, sizeof(what), "rayQuad %d", r);
        printCollision(what, GetRayCollisionQuad(rays[r], (Vector3){ -1, -1, 0 }, (Vector3){ 1, -1, 0 }, (Vector3){ 1, 1, 0 }, (Vector3){ -1, 1, 0 }));
    }
}

static void materials(const char *tmp, const char *objDir)
{
    printf("== materials\n");
    char path[512];
    snprintf(path, sizeof(path), "%s/character.mtl", objDir);
    int count = -1;
    Material *mats = LoadMaterials(path, &count);
    printf("  LoadMaterials(character.mtl): count=%d %s\n", count, (mats != NULL)? "data" : "NULL");
    for (int i = 0; (mats != NULL) && (i < count); i++) { printMaterial(i, mats[i]); UnloadMaterial(mats[i]); }
    RL_FREE(mats);

    count = -1;
    snprintf(path, sizeof(path), "%s/missing.mtl", tmp);
    mats = LoadMaterials(path, &count);
    printf("  LoadMaterials(missing.mtl): count=%d %s\n", count, (mats != NULL)? "data" : "NULL");
    RL_FREE(mats);

    count = -1;
    snprintf(path, sizeof(path), "%s/cube.obj", objDir);
    mats = LoadMaterials(path, &count);
    printf("  LoadMaterials(cube.obj): count=%d %s\n", count, (mats != NULL)? "data" : "NULL");
    RL_FREE(mats);

    Material def = LoadMaterialDefault();
    printMaterial(-1, def);
    Texture2D tex = { 0 };
    tex.id = 77; tex.width = 3; tex.height = 4;
    SetMaterialTexture(&def, MATERIAL_MAP_NORMAL, tex);
    printMaterial(-2, def);
    RL_FREE(def.maps);

    Model model = LoadModelFromMesh(GenMeshCube(1, 1, 1));
    SetModelMeshMaterial(&model, 0, 0);
    SetModelMeshMaterial(&model, 1, 0);
    SetModelMeshMaterial(&model, 0, 3);
    printf("  meshMaterial[0]=%d\n", model.meshMaterial[0]);
    UnloadModel(model);
}

static void writeText(const char *path, const char *text)
{
    FILE *f = fopen(path, "wb");
    fputs(text, f);
    fclose(f);
}

// glTF files that exercise the URI paths the bundled .glb files never reach
static void gltfVariants(const char *tmp, const char *resources)
{
    // One triangle: 3 positions (36 bytes), 3 texcoords (24 bytes), 3 u16 indices (6 + 2 pad)
    static const float positions[9] = { 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    static const float uvs[6] = { 0, 0, 1, 0, 0, 1 };
    static const unsigned short idx[4] = { 0, 1, 2, 0 };
    unsigned char bin[68];
    memcpy(bin, positions, 36);
    memcpy(bin + 36, uvs, 24);
    memcpy(bin + 60, idx, 8);

    char path[512];
    snprintf(path, sizeof(path), "%s/tri.bin", tmp);
    SaveFileData(path, bin, sizeof(bin));

    int b64Size = 0;
    char *b64 = EncodeDataBase64(bin, sizeof(bin), &b64Size);

    // Copy a png next to the gltf for the external image URI, and embed one as a data URI
    int pngSize = 0;
    snprintf(path, sizeof(path), "%s/billboard.png", resources);
    unsigned char *png = LoadFileData(path, &pngSize);
    snprintf(path, sizeof(path), "%s/tex.png", tmp);
    SaveFileData(path, png, pngSize);
    int pngB64Size = 0;
    char *pngB64 = EncodeDataBase64(png, pngSize, &pngB64Size);
    UnloadFileData(png);

    const char *fmt =
        "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}],"
        "\"nodes\":[{\"mesh\":0,\"translation\":[1,2,3],\"scale\":[2,2,2]}],"
        "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0,\"TEXCOORD_0\":1},\"indices\":2,\"material\":0}]}],"
        "\"materials\":[{\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.5,0.25,1,1],\"baseColorTexture\":{\"index\":0},"
        "\"metallicFactor\":0.3,\"roughnessFactor\":0.6},\"emissiveFactor\":[0.1,0.2,0.3]}],"
        "\"textures\":[{\"source\":0}],\"images\":[{\"uri\":\"%s\"}],"
        "\"buffers\":[{\"byteLength\":68,\"uri\":\"%s\"}],"
        "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":60},{\"buffer\":0,\"byteOffset\":60,\"byteLength\":6}],"
        "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,\"type\":\"VEC3\",\"min\":[0,0,0],\"max\":[1,1,0]},"
        "{\"bufferView\":0,\"byteOffset\":36,\"componentType\":5126,\"count\":3,\"type\":\"VEC2\"},"
        "{\"bufferView\":1,\"componentType\":5123,\"count\":3,\"type\":\"SCALAR\"}]}";

    char *dataUri = malloc(b64Size + 64);
    snprintf(dataUri, b64Size + 64, "data:application/octet-stream;base64,%s", b64);
    char *imageUri = malloc(pngB64Size + 64);
    snprintf(imageUri, pngB64Size + 64, "data:image/png;base64,%s", pngB64);

    const char *variants[][3] = {
        { "external.gltf", "tex.png", "tri.bin" },
        { "embedded.gltf", imageUri, dataUri },
        { "missingimage.gltf", "nothere.png", "tri.bin" },
        { "badimageuri.gltf", "data:image/png;base64", dataUri },
    };
    for (int v = 0; v < 4; v++)
    {
        size_t size = strlen(fmt) + strlen(variants[v][1]) + strlen(variants[v][2]) + 1;
        char *json = malloc(size);
        snprintf(json, size, fmt, variants[v][1], variants[v][2]);
        snprintf(path, sizeof(path), "%s/%s", tmp, variants[v][0]);
        writeText(path, json);
        free(json);
        loadOne(tmp, path);
    }

    free(dataUri);
    free(imageUri);
    MemFree(b64);
    MemFree(pngB64);
}

static void brokenFiles(const char *tmp)
{
    const char *names[] = { "missing.obj", "missing.iqm", "missing.glb", "missing.vox", "missing.m3d", "missing.xyz",
                            "garbage.iqm", "garbage.glb", "garbage.gltf", "garbage.vox", "garbage.m3d", "short.iqm" };
    char path[512];
    for (int i = 6; i < 11; i++)
    {
        snprintf(path, sizeof(path), "%s/%s", tmp, names[i]);
        writeText(path, "this is not a model file, just some bytes to parse 0123456789abcdef");
    }

    // A complete IQM header (magic + 27 unsigned ints) with an unsupported version
    unsigned char header[16 + 27*4] = "INTERQUAKEMODEL";
    header[16] = 3;
    snprintf(path, sizeof(path), "%s/%s", tmp, names[11]);
    SaveFileData(path, header, sizeof(header));
    for (int i = 0; i < 12; i++)
    {
        snprintf(path, sizeof(path), "%s/%s", tmp, names[i]);
        loadOne(tmp, path);
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) { printf("usage: models_data <examples dir>\n"); return 1; }
    const char *examples = argv[1];

    // Work inside a fresh temp directory through relative paths, so the C and
    // Zig runs print the same file names
    char tmpDir[] = "/tmp/models_data_XXXXXX";
    if ((mkdtemp(tmpDir) == NULL) || (chdir(tmpDir) != 0)) return 1;
    const char *tmp = ".";

    SetTraceLogLevel(LOG_WARNING);
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(64, 64, "models_data");
    SetTraceLogCallback(logCallback);
    SetTraceLogLevel(LOG_DEBUG);

    char resources[512], dir[512];
    snprintf(resources, sizeof(resources), "%s/models/resources", examples);

    collisions();
    generators(tmp, resources);
    snprintf(dir, sizeof(dir), "%s/models", resources);
    loadDir(tmp, dir);
    snprintf(dir, sizeof(dir), "%s/shaders/resources/models", examples);
    loadDir(tmp, dir);
    snprintf(dir, sizeof(dir), "%s/models/obj", resources);
    materials(tmp, dir);
    gltfVariants(tmp, resources);
    brokenFiles(tmp);

    SetTraceLogLevel(LOG_WARNING);
    CloseWindow();

    char cmd[600];
    snprintf(cmd, sizeof(cmd), "rm -rf %s", tmpDir);
    return system(cmd);
}

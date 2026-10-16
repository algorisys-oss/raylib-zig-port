# Embedded data for embedded_files_loading.zig

`image_data.raw` and `audio_data.raw` are exactly the bytes of the C arrays in
raylib's `examples/others/resources/image_data.h` and `audio_data.h`
(ExportImageAsCode / ExportWaveAsCode output), which the C example compiles in.
The Zig translation `@embedFile`s them instead. Reproduce / verify with:

    H=/home/rajesh/opensource/graphics/raylib-6.2/examples/others/resources
    python3 tools/c_array_to_raw.py $H/image_data.h image_data.raw
    python3 tools/c_array_to_raw.py $H/audio_data.h audio_data.raw

(Verified byte-identical 2026-10-16.) Data © raylib, zlib/libpng license.

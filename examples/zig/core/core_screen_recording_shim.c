// core_screen_recording_shim.c — instantiates msf_gif (third-party GIF
// encoder, vendor/msf_gif, linked as C) for the core_screen_recording example.
#define MSF_GIF_IMPL
#include "../../../vendor/msf_gif/msf_gif.h"

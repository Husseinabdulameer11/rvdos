#include <SDL2/SDL.h>
#include <stdint.h>
#include <stdbool.h>

#define H_VISIBLE 640
#define V_VISIBLE 480

static SDL_Window* win = NULL;
static SDL_Renderer* ren = NULL;
static SDL_Texture* tex = NULL;
static uint32_t framebuf[H_VISIBLE * V_VISIBLE];
static int px = 0, py = 0;
static bool quit_requested = false;

// Single-slot pending keypress -- matches keyboard.vhd's own "one key at
// a time, no buffering" design exactly, so there's no mismatch between
// what this side can hold and what the hardware side can hold.
static int pending_key = -1;

static void handle_key_event(SDL_Event *e) {
    if (e->type == SDL_TEXTINPUT) {
        // Handles regular printable characters, already translated for
        // the current keyboard layout/shift state by SDL itself.
        pending_key = (unsigned char)e->text.text[0];
    } else if (e->type == SDL_KEYDOWN) {
        // Control keys that don't generate SDL_TEXTINPUT events.
        switch (e->key.keysym.sym) {
            case SDLK_RETURN:    pending_key = '\n'; break;
            case SDLK_BACKSPACE: pending_key = 8;    break;
            default: break; // anything else (arrow keys, F-keys, etc.) is ignored
        }
    }
}

void sdl_init(void) {
    SDL_Init(SDL_INIT_VIDEO);
    win = SDL_CreateWindow("RISC-V CPU - live VGA output", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_VISIBLE, V_VISIBLE, 0);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB888,
        SDL_TEXTUREACCESS_STREAMING, H_VISIBLE, V_VISIBLE);
    SDL_StartTextInput(); // needed for SDL_TEXTINPUT events to actually fire
}

void sdl_push_pixel(int32_t r, int32_t g, int32_t b) {
    if (px < H_VISIBLE && py < V_VISIBLE) {
        framebuf[py * H_VISIBLE + px] = (r << 16) | (g << 8) | b;
    }
    px++;
}

// Writes one LOGICAL pixel (320x200 space) into all 4 of the physical
// screen positions it actually occupies (2x pixel-doubled, plus the
// 40-line letterbox offset -- see video_scanout.vhd). Scalar integer
// arguments only, no arrays -- unlike the earlier line-batching attempt,
// this is the same proven-reliable VHPIDIRECT calling pattern already
// used successfully by every other function in this file. Cuts push
// calls from one per PHYSICAL pixel (256,000/frame) to one per LOGICAL
// pixel (64,000/frame) -- a real 4x reduction, not just a redistribution
// of the same work.
void sdl_push_pixel_logical(int32_t log_x, int32_t log_y, int32_t r, int32_t g, int32_t b) {
    int32_t phys_x = log_x * 2;
    int32_t phys_y = 40 + log_y * 2; // 40 = V_MARGIN, the letterbox offset
    if (phys_x + 1 >= H_VISIBLE || phys_y + 1 >= V_VISIBLE) return;
    uint32_t color = ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
    framebuf[phys_y * H_VISIBLE + phys_x]         = color;
    framebuf[phys_y * H_VISIBLE + phys_x + 1]     = color;
    framebuf[(phys_y + 1) * H_VISIBLE + phys_x]   = color;
    framebuf[(phys_y + 1) * H_VISIBLE + phys_x + 1] = color;
}

// Called once per scanline (480 times per frame) -- much more often than
// once per frame, which is what actually keeps Windows' message loop
// serviced and the window out of "(Not Responding)". Simulating a full
// frame (420,000 clock cycles, one VHPIDIRECT call per pixel) takes
// noticeable wall-clock time, so once-per-frame polling alone left long
// gaps where the OS saw no response from the window at all.
void sdl_new_line(void) {
    px = 0;
    py++;

    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) quit_requested = true;
        handle_key_event(&e);
    }
}

int32_t sdl_new_frame(void) {
    SDL_UpdateTexture(tex, NULL, framebuf, H_VISIBLE * sizeof(uint32_t));
    SDL_RenderClear(ren);
    SDL_RenderCopy(ren, tex, NULL, NULL);
    SDL_RenderPresent(ren);
    px = 0; py = 0;

    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) quit_requested = true;
        handle_key_event(&e);
    }

    return quit_requested ? 1 : 0;
}

// Returns the pending key's ASCII code and consumes it (clears pending_key
// so the same key isn't delivered twice), or -1 if nothing is waiting.
// Called once per scanline from tb_live.vhd's pump process, not once per
// clock cycle -- calling any VHPIDIRECT function 420,000 times a frame
// (once per pixel clock) turned out to add enough overhead to visibly
// slow the whole simulation down; once per line (480 times/frame) is
// still far more than fast enough for anything at human typing speed.
int32_t sdl_poll_key(void) {
    int32_t k = pending_key;
    pending_key = -1;
    return k;
}

void sdl_quit(void) {
    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
}
/* Author: Peter Sovietov */

#ifndef ZVON_SFX_H
#define ZVON_SFX_H

#include "zvon.h"

typedef void (*sfx_change_func)(void *state, int param, double val);
typedef double (*sfx_mono_func)(void *state, double l);
typedef void (*sfx_stereo_func)(void *state, double *l, double *r);
typedef void (*sfx_init_func)(void *state);
typedef void (*sfx_free_func)(void *state);

struct sfx_box {
    struct sfx_proto *proto;
    void *state;
};

struct sfx_proto {
    char *name;
    sfx_change_func change;
    sfx_mono_func mono;
    sfx_stereo_func stereo;
    sfx_init_func init;
    sfx_free_func free;
    size_t state_size;
};

#define MAX_SFX_BOXES 8

struct chan_state {
    int is_on;
    double vol;
    double pan;
    struct sfx_box stack[MAX_SFX_BOXES];
    int stack_size;
};

void chan_set(struct chan_state *c, int is_on, double vol, double pan);
void chan_drop(struct chan_state *c);
struct sfx_box *chan_push(struct chan_state *c, struct sfx_proto *proto);

void mix_init(struct chan_state *channels, int num_channels);
void mix_process(struct chan_state *channels, int num_channels, double vol, float *samples, int num_samples);

enum {
    ZV_NOTE_ON,
    ZV_NOTE_OFF,
    ZV_VOLUME,
    ZV_TIME,
    ZV_FEEDBACK,
    ZV_GAIN,
    ZV_WAVE_TYPE,
    ZV_WAVE_WIDTH,
    ZV_WAVE_OFFSET,
    ZV_ATTACK_TIME,
    ZV_DECAY_TIME,
    ZV_SUSTAIN_LEVEL,
    ZV_RELEASE_TIME,
    ZV_GLIDE_ON,
    ZV_GLIDE_OFF,
    ZV_FREQ_SCALER,
    ZV_LFO_SELECT,
    ZV_LFO_WAVE_TYPE,
    ZV_LFO_WAVE_SIGN,
    ZV_LFO_FREQ,
    ZV_LFO_LEVEL,
    ZV_LFO_IS_ONESHOT,
    ZV_LFO_TO_FREQ,
    ZV_LFO_TO_WIDTH,
    ZV_LFO_TO_OFFSET,
    ZV_END
};

enum {
    ZV_SIN = LFO_SIN,
    ZV_SAW = LFO_SAW,
    ZV_SQUARE = LFO_SQUARE,
    ZV_TRIANGLE = LFO_TRIANGLE,
    ZV_PWM,
    ZV_FM,
    ZV_NOISE
};

extern struct sfx_proto sfx_synth;
extern struct sfx_proto sfx_delay;
extern struct sfx_proto sfx_dist;

#endif

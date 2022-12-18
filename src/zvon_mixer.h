/* Author: Peter Sovietov */

#ifndef ZVON_MIXER_H
#define ZVON_MIXER_H

#include "zvon.h"

typedef void (*sfx_change_func)(void *state, int param, int elem, double val);
typedef double (*sfx_mono_func)(void *state, double l);
typedef void (*sfx_stereo_func)(void *state, double *l, double *r);
typedef void (*sfx_init_func)(void *state);
typedef void (*sfx_free_func)(void *state);

struct sfx_proto {
    char *name;
    sfx_change_func change;
    sfx_mono_func mono;
    sfx_stereo_func stereo;
    sfx_init_func init;
    sfx_free_func free;
    int state_size;
};

struct sfx_box {
    struct sfx_proto *proto;
    double vol;
    void *state;
};

void sfx_box_set_vol(struct sfx_box *box, double vol);

#define SFX_MAX_BOXES 8

struct chan_state {
    int is_on;
    double vol;
    double pan_left;
    double pan_right;
    struct sfx_box stack[SFX_MAX_BOXES];
    int stack_size;
};

void chan_set_on(struct chan_state *c, int is_on);
void chan_set_vol(struct chan_state *c, double vol);
void chan_set_pan(struct chan_state *c, double pan);
void chan_drop(struct chan_state *c);
struct sfx_box *chan_push(struct chan_state *c, struct sfx_proto *proto);

void mix_init(struct chan_state *chans, int num_chans);
void mix_process(struct chan_state *chans, int num_chans, double vol, float *samps, int num_samps);

#define SFX_BOX_VOLUME 0

void sfx_box_change(struct sfx_box *box, int param, int elem, double val);
void chan_change(struct chan_state *c, int param, int elem, double val);

#endif

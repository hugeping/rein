/* Author: Peter Sovietov */

#ifndef ZVON_H
#define ZVON_H

#include "zvon_platform.h"

int sec(double t);
double midi_freq(int m);
double limit(double x, double low, double high);
double lerp(double a, double b, double x);
double hertz(double t, double freq);
double dsf(double phase, double mod, double width);
double dsf2(double phase, double mod, double width);
double saw(double phase, double width);
double square(double phase, double width);
double pwm(double phase, double offset, double width);
unsigned int lfsr(unsigned int state, int bits, int *taps, int taps_size);

struct phasor_state {
    double phase;
};

void phasor_init(struct phasor_state *s);
void phasor_reset(struct phasor_state *s);
double phasor_next(struct phasor_state *s, double freq);

struct env_state {
    int *deltas;
    double *levels;
    size_t env_size;
    int is_end;
    int is_loop;
    int is_full_reset;
    size_t sustain_pos;
    double level_0;
    double level;
    int t;
    double level_at_pos;
    int t_at_pos;
    size_t pos;
};

typedef double (*env_func)(double a, double b, double x);

void env_init(struct env_state *s, int env_size, int *deltas, double *levels, double level_0);
void env_set(struct env_state *s, int pos, int delta, double level);
void env_reset(struct env_state *s);
double env_next_head(struct env_state *s, env_func func);
double env_next(struct env_state *s);
double seq_next(struct env_state *s);

struct delay_state {
    double *buf;
    size_t buf_size;
    double level;
    double fb;
    size_t pos;
};

void delay_init(struct delay_state *s, double *buf, size_t buf_size, double level, double fb);
double delay_next(struct delay_state *s, double x);

struct filter_state {
    double y;
};

void filter_init(struct filter_state *s);
double filter_lp_next(struct filter_state *s, double x, double width);
double filter_hp_next(struct filter_state *s, double x, double width);

struct glide_state {
    double source;
    double rate;
};

void glide_init(struct glide_state *s, double source, double rate);
double glide_next(struct glide_state *s, double target);

#define MAX_TAPS 32

struct noise_state {
    int bits;
    int taps[MAX_TAPS];
    int taps_size;
    unsigned int state;
    double phase;
};

void noise_init(struct noise_state *s, int bits, int *taps, int taps_size);
double noise_next(struct noise_state *s, double freq);

typedef void (*sfx_change_func)(void *state, int param, double val1, double val2);
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
void chan_free(struct chan_state *c);
void *chan_push(struct chan_state *c, struct sfx_proto *proto);

void mix_init(struct chan_state *channels, int num_channels);
void mix_process(struct chan_state *channels, int num_channels, double vol, float *samples, int num_samples);

#endif

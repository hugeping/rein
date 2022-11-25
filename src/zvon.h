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
double softclip(double x, double drive);

struct phasor_state {
    double phase;
};

void phasor_init(struct phasor_state *s);
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

struct adsr_state {
    int deltas[3];
    double levels[3];
    struct env_state env;
    int sustain_mode;
};

void adsr_init(struct adsr_state *s, int is_sustain_on);
void adsr_set_attack(struct adsr_state *s, double t);
void adsr_set_decay(struct adsr_state *s, double t);
void adsr_set_sustain(struct adsr_state *s, double levels);
void adsr_set_release(struct adsr_state *s, double t);
void adsr_note_on(struct adsr_state *s);
void adsr_note_off(struct adsr_state *s);
double adsr_next(struct adsr_state *s);

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

struct lfo_state {
    double phase;
    double freq;
    int func;
    int sign;
    double level;
    double offset;
    int is_oneshot;
};

void lfo_init(struct lfo_state *s, int func, int sign, double freq, double level, double offset, int is_oneshot);
double lfo_func(double x, int func);
double lfo_next(struct lfo_state *s);

typedef void (*sfx_change_func)(void *state, int param, float val, float *data);
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

#endif

/* Author: Peter Sovietov */

#ifndef ZVON_H
#define ZVON_H

#define MIN(a, b) (((a) < (b)) ? (a) : (b))
#define MAX(a, b) (((a) > (b)) ? (a) : (b))

#define PI 3.14159265358979323846

#ifndef SR
#define SR 44100
#endif

int sec(double t);
double limit(double x, double low, double high);
double lerp(double x, double y, double a);
double dsf(double phase, double mod, double width);
double dsf2(double phase, double mod, double width);
double pwm(double phase, double offset, double width);
double softclip(double x, double gain);

struct phasor_state {
    double phase;
};

void phasor_init(struct phasor_state *s);
double phasor_next(struct phasor_state *s, double freq);

struct adsr_state {
    int state;
    double level;
    double attack;
    double decay;
    double sustain;
    double release;
    double attack_step;
    double decay_step;
    double release_step;
};

void adsr_init(struct adsr_state *s);
void adsr_set_attack(struct adsr_state *s, double attack);
void adsr_set_decay(struct adsr_state *s, double decay);
void adsr_set_sustain(struct adsr_state *s, double sustain);
void adsr_set_release(struct adsr_state *s, double release);
void adsr_note_on(struct adsr_state *s, int is_reset_level_on);
void adsr_note_off(struct adsr_state *s);
double adsr_next(struct adsr_state *s, int is_sustain_on);

struct delay_state {
    double *buf;
    int buf_size;
    int pos;
    int size;
    double level;
    double fb;
};

void delay_init(struct delay_state *s, double *buf, int buf_size);
void delay_set_time(struct delay_state *s, double time);
void delay_set_level(struct delay_state *s, double level);
void delay_set_fb(struct delay_state *s, double fb);
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

void glide_init(struct glide_state *s);
void glide_set_source(struct glide_state *s, double source);
void glide_set_rate(struct glide_state *s, double rate);
double glide_next(struct glide_state *s, double target);

struct noise_state {
    double phase;
    unsigned int state;
    double old_y;
    double y;
    double width;
};

void noise_init(struct noise_state *s);
void noise_set_width(struct noise_state *s, double width);
double noise_lin_next(struct noise_state *s, double freq);
double noise_next(struct noise_state *s, double freq);

enum {
    LFO_ZERO,
    LFO_SIN,
    LFO_SAW,
    LFO_SQUARE,
    LFO_TRIANGLE,
    LFO_SEQ,
    LFO_LIN_SEQ
};

#define LFO_MAX_SEQ_STEPS 128

struct lfo_state {
    double phase;
    double freq;
    int func;
    int is_reset_on;
    double seq[LFO_MAX_SEQ_STEPS];
    int edit_pos;
    int seq_size;
    double prev;
    int pos;
    double low;
    double high;
    int is_loop;
};

void lfo_init(struct lfo_state *s);
void lfo_reset(struct lfo_state *s);
void lfo_set_reset(struct lfo_state *s, int is_reset_on);
void lfo_set_type(struct lfo_state *s, int func);
void lfo_set_freq(struct lfo_state *s, double freq);
void lfo_set_low(struct lfo_state *s, double low);
void lfo_set_high(struct lfo_state *s, double high);
void lfo_set_loop(struct lfo_state *s, int is_loop);
void lfo_set_seq_pos(struct lfo_state *s, int pos);
void lfo_set_seq_val(struct lfo_state *s, double val);
void lfo_set_seq_size(struct lfo_state *s, int size);
double lfo_next(struct lfo_state *s);

#endif

/* Author: Peter Sovietov */

#include <math.h>
#include "zvon_sfx.h"

struct test_square_state {
    double freq;
    double vol;
    struct phasor_state ph1;
    struct phasor_state ph2;
    struct env_state env;
    int env_deltas[2];
    double env_levels[2];
};

void test_square_init(struct test_square_state *s) {
    phasor_init(&s->ph1);
    phasor_init(&s->ph2);
    env_init(&s->env, 2, s->env_deltas, s->env_levels, 0);
    env_set(&s->env, 0, sec(0.01), 1);
    env_set(&s->env, 1, sec(0.5), 0);
}

void test_square_change(struct test_square_state *s, int param, float val, float* user) {
    (void) user;
    if (param == ZV_NOTE_ON) {
        s->freq = val;
        env_reset(&s->env);
    } else if (param == ZV_VOLUME) {
        s->vol = val;
    }
}

double test_square_mono(struct test_square_state *s, double l) {
    (void) l;
    double a = square(phasor_next(&s->ph1, s->freq) + 2 * sin(phasor_next(&s->ph2, 4)), 0.5);
    return s->vol * a * env_next(&s->env);
}

struct sfx_proto test_square_box = {
    .name = "test_square",
    .init = (sfx_init_func) test_square_init,
    .change = (sfx_change_func) test_square_change,
    .mono = (sfx_mono_func) test_square_mono,
    .state_size = sizeof(struct test_square_state)
};

struct test_saw_state {
    double freq;
    double vol;
    struct phasor_state ph1;
    struct phasor_state ph2;
    struct phasor_state ph3;
    struct env_state env;
    int env_deltas[2];
    double env_levels[2];
};

void test_saw_init(struct test_saw_state *s) {
    phasor_init(&s->ph1);
    phasor_init(&s->ph2);
    phasor_init(&s->ph3);
    env_init(&s->env, 2, s->env_deltas, s->env_levels, 0);
    env_set(&s->env, 0, sec(0.01), 1);
    env_set(&s->env, 1, sec(0.1), 0.5);
}

void test_saw_change(struct test_saw_state *s, int param, float val, float *user) {
    (void) user;
    if (param == ZV_NOTE_ON) {
        s->freq = val;
        env_reset(&s->env);
    } else if (param == ZV_VOLUME) {
        s->vol = val;
    }
}

double test_saw_mono(struct test_saw_state *s, double l) {
    (void) l;
    double mod = 0.2 + fabs(1 + sin(phasor_next(&s->ph2, 1))) * 0.3;
    double a = saw(phasor_next(&s->ph1, s->freq) + 2 * sin(phasor_next(&s->ph3, 4)), mod);
    return s->vol * a * env_next(&s->env);
}

struct sfx_proto test_saw_box = {
    .name = "test_saw",
    .init = (sfx_init_func) test_saw_init,
    .change = (sfx_change_func) test_saw_change,
    .mono = (sfx_mono_func) test_saw_mono,
    .state_size = sizeof(struct test_saw_state)
};

struct delay_box_state {
    struct delay_state d;
    double delay_buf[SR];
};

void delay_box_init(struct delay_box_state *s) {
    delay_init(&s->d, s->delay_buf, sec(0.5), 0.5, 0.5);
}

void delay_box_change(struct delay_box_state *s, int param, float val, float *user) {
    (void) user;
    if (param == ZV_VOLUME) {
        s->d.level = val;
    } else if (param == ZV_TIME) {
        s->d.buf_size = limit(sec(val), 1, SR);
        s->d.pos = 0;
    } else if (param == ZV_FEEDBACK) {
        s->d.fb = val;
    }
}

double delay_box_mono(struct delay_box_state *s, double l) {
    return delay_next(&s->d, l);
}

struct sfx_proto delay_box = {
    .name = "delay",
    .init = (sfx_init_func) delay_box_init,
    .change = (sfx_change_func) delay_box_change,
    .mono = (sfx_mono_func) delay_box_mono,
    .state_size = sizeof(struct delay_box_state)
};

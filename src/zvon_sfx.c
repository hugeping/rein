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

struct sfx_delay_state {
    struct delay_state d;
    double delay_buf[SR];
};

void sfx_delay_init(struct sfx_delay_state *s) {
    delay_init(&s->d, s->delay_buf, sec(0.5), 0.5, 0.5);
}

void sfx_delay_change(struct sfx_delay_state *s, int param, float val, float *user) {
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

double sfx_delay_mono(struct sfx_delay_state *s, double l) {
    return delay_next(&s->d, l);
}

struct sfx_proto sfx_delay = {
    .name = "delay",
    .init = (sfx_init_func) sfx_delay_init,
    .change = (sfx_change_func) sfx_delay_change,
    .mono = (sfx_mono_func) sfx_delay_mono,
    .state_size = sizeof(struct sfx_delay_state)
};

struct sfx_dist_state {
    double drive;
    double vol;
};

void sfx_dist_init(struct sfx_dist_state *s) {
    s->drive = 1;
    s->vol = 1;
}

void sfx_dist_change(struct sfx_dist_state *s, int param, float val, float *user) {
    (void) user;
    if (param == ZV_VOLUME) {
        s->vol = val;
    } else if (param == ZV_DRIVE) {
        s->drive = val;
    }
}

double sfx_dist_mono(struct sfx_dist_state *s, double l) {
    return s->vol * dist(l, s->drive);
}

struct sfx_proto sfx_dist = {
    .name = "distortion",
    .init = (sfx_init_func) sfx_dist_init,
    .change = (sfx_change_func) sfx_dist_change,
    .mono = (sfx_mono_func) sfx_dist_mono,
    .state_size = sizeof(struct sfx_dist_state)
};

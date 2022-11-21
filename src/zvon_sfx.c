/* Author: Peter Sovietov */

#include <math.h>
#include <stddef.h>
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
    s->freq = 0;
    s->vol = 0;
    phasor_init(&s->ph1);
    phasor_init(&s->ph2);
    env_init(&s->env, 2, s->env_deltas, s->env_levels, 0);
    env_set(&s->env, 0, sec(0.01), 1);
    env_set(&s->env, 1, sec(0.5), 0);
}

void test_square_change(struct test_square_state *s, int param, double val1, double val2) {
    if (param == ZV_NOTE_ON) {
        s->freq = val1;
        s->vol = val2;
        env_reset(&s->env);
    }
}

double test_square_mono(struct test_square_state *s, double l) {
    (void) l;
    double a = square(phasor_next(&s->ph1, s->freq) + 2 * sin(phasor_next(&s->ph2, 4)), 0.5);
    return s->vol * a * env_next(&s->env);
}

struct sfx_proto test_square_proto = {
    .name = "test_square",
    .init = (sfx_init_func) test_square_init,
    .change = (sfx_change_func) test_square_change,
    .mono = (sfx_mono_func) test_square_mono,
    .state_size = sizeof(struct test_square_state)
};

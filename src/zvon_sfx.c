/* Author: Peter Sovietov */

#include <math.h>
#include "zvon_sfx.h"

struct sfx_synth_state {
    struct phasor_state phase;
    struct adsr_state adsr;
    double freq;
    int wave_type;
};

static void sfx_synth_init(struct sfx_synth_state *s) {
    phasor_init(&s->phase);
    adsr_init(&s->adsr, 0);
    s->freq = 0;
    s->wave_type = 0;
}

static void sfx_synth_change(struct sfx_synth_state *s, int param, float val, float *data) {
    (void) data;
    if (param == ZV_NOTE_ON) {
        s->freq = val;
        adsr_note_on(&s->adsr);
    } else if (param == ZV_NOTE_OFF) {
        adsr_note_off(&s->adsr);
    } else if (param == ZV_WAVE_TYPE) {
        s->wave_type = limit(val, 0, 1);
    } else if (param == ZV_ATTACK_TIME) {
        adsr_set_attack(&s->adsr, val);
    } else if (param == ZV_DECAY_TIME) {
        adsr_set_decay(&s->adsr, val);
    } else if (param == ZV_SUSTAIN_LEVEL) {
        adsr_set_sustain(&s->adsr, val);
    } else if (param == ZV_RELEASE_TIME) {
        adsr_set_release(&s->adsr, val);
    }
}

static double sfx_synth_mono(struct sfx_synth_state *s, double l) {
    (void) l;
    double x = 0;
    double p = phasor_next(&s->phase, s->freq);
    if (s->wave_type == 0) {
        x = sin(p);
    } else if (s->wave_type == 1) {
        x = square(p, 0.5);
    } else if (s->wave_type == 2) {
        x = saw(p, 0.7);
    }
    return x * adsr_next(&s->adsr);
}

struct sfx_proto sfx_synth = {
    .name = "synth",
    .init = (sfx_init_func) sfx_synth_init,
    .change = (sfx_change_func) sfx_synth_change,
    .mono = (sfx_mono_func) sfx_synth_mono,
    .state_size = sizeof(struct sfx_synth_state)
};

#define DELAY_SIZE SR

struct sfx_delay_state {
    struct delay_state d;
    double delay_buf[DELAY_SIZE];
};

static void sfx_delay_init(struct sfx_delay_state *s) {
    delay_init(&s->d, s->delay_buf, sec(0.5), 0.5, 0.5);
}

static void sfx_delay_change(struct sfx_delay_state *s, int param, float val, float *user) {
    (void) user;
    if (param == ZV_VOLUME) {
        s->d.level = val;
    } else if (param == ZV_TIME) {
        s->d.buf_size = limit(sec(val), 1, DELAY_SIZE);
        s->d.pos = 0;
    } else if (param == ZV_FEEDBACK) {
        s->d.fb = val;
    }
}

static double sfx_delay_mono(struct sfx_delay_state *s, double l) {
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
    double gain;
    double vol;
};

static void sfx_dist_init(struct sfx_dist_state *s) {
    s->gain = 1;
    s->vol = 1;
}

static void sfx_dist_change(struct sfx_dist_state *s, int param, float val, float *user) {
    (void) user;
    if (param == ZV_VOLUME) {
        s->vol = val;
    } else if (param == ZV_GAIN) {
        s->gain = val;
    }
}

static double sfx_dist_mono(struct sfx_dist_state *s, double l) {
    return s->vol * softclip(l, 10 * s->gain);
}

struct sfx_proto sfx_dist = {
    .name = "dist",
    .init = (sfx_init_func) sfx_dist_init,
    .change = (sfx_change_func) sfx_dist_change,
    .mono = (sfx_mono_func) sfx_dist_mono,
    .state_size = sizeof(struct sfx_dist_state)
};

/* Author: Peter Sovietov */

#include <math.h>
#include "zvon_sfx.h"

struct sfx_synth_state {
    struct phasor_state phase;
    struct adsr_state adsr;
    struct glide_state glide;
    struct lfo_state freq_lfo;
    struct lfo_state width_lfo;
    int is_glide_on;
    int wave_type;
    double wave_width;
    double freq;
    double vol;
};

static void sfx_synth_init(struct sfx_synth_state *s) {
    phasor_init(&s->phase);
    adsr_init(&s->adsr, 0);
    glide_init(&s->glide, 440, 100);
    lfo_init(&s->freq_lfo, 0, 1, 0, 1, 0);
    lfo_init(&s->width_lfo, 0, 1, 0, 1, 0);
    s->wave_type = 0;
    s->freq = 0;
    s->wave_width = 0.5;
    s->is_glide_on = 0;
}

static void sfx_synth_change(struct sfx_synth_state *s, int param, float val, float *data) {
    (void) data;
    switch (param) {
    case ZV_VOLUME:
        s->vol = val;
        break;
    case ZV_NOTE_ON:
        s->freq = val;
        adsr_note_on(&s->adsr);
        s->freq_lfo.phase = 0;
        s->width_lfo.phase = 0;
        break;
    case ZV_NOTE_OFF:
        adsr_note_off(&s->adsr);
        break;
    case ZV_WAVE_TYPE:
        s->wave_type = val;
        break;
    case ZV_WAVE_WIDTH:
        s->wave_width = val;
        break;
    case ZV_ATTACK_TIME:
        adsr_set_attack(&s->adsr, val);
        break;
    case ZV_DECAY_TIME:
        adsr_set_decay(&s->adsr, val);
        break;
    case ZV_SUSTAIN_LEVEL:
        adsr_set_sustain(&s->adsr, val);
        break;
    case ZV_RELEASE_TIME:
        adsr_set_release(&s->adsr, val);
        break;
    case ZV_GLIDE_ON:
        glide_init(&s->glide, s->freq, val);
        s->is_glide_on = 1;
        break;
    case ZV_GLIDE_OFF:
        s->is_glide_on = 0;
        break;
    case ZV_FREQ_LFO_WAVE_TYPE:
        s->freq_lfo.func = val;
        break;
    case ZV_FREQ_LFO_WAVE_SIGN:
        s->freq_lfo.sign = val;
        break;
    case ZV_FREQ_LFO_FREQ:
        s->freq_lfo.freq = val;
        break;
    case ZV_FREQ_LFO_LEVEL:
        s->freq_lfo.level = val;
        break;
    case ZV_FREQ_LFO_IS_ONESHOT:
        s->freq_lfo.is_oneshot = val;
        break;
    case ZV_WIDTH_LFO_WAVE_TYPE:
        s->width_lfo.func = val;
        break;
    case ZV_WIDTH_LFO_WAVE_SIGN:
        s->width_lfo.sign = val;
        break;
    case ZV_WIDTH_LFO_FREQ:
        s->width_lfo.freq = val;
        break;
    case ZV_WIDTH_LFO_LEVEL:
        s->width_lfo.level = val;
        break;
    case ZV_WIDTH_LFO_IS_ONESHOT:
        s->width_lfo.is_oneshot = val;
        break;
    }
}

static double sfx_synth_mono(struct sfx_synth_state *s, double l) {
    (void) l;
    double x = 0;
    double freq = s->is_glide_on ? glide_next(&s->glide, s->freq) : s->freq;
    freq = limit(freq + lfo_next(&s->freq_lfo), 0, 15000);
    double width = limit(s->wave_width + lfo_next(&s->width_lfo), 0, 0.9);
    double phase = phasor_next(&s->phase, freq);
    if (s->wave_type == 0) {
        x = sin(phase);
    } else if (s->wave_type == 1) {
        x = square(phase, width);
    } else if (s->wave_type == 2) {
        x = saw(phase, width);
    }
    return x * adsr_next(&s->adsr) * s->vol;
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

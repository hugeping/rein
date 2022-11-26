/* Author: Peter Sovietov */

#include <math.h>
#include <stdlib.h>
#include "zvon_sfx.h"

void mix_init(struct chan_state *channels, int num_channels) {
    for (int i = 0; i < num_channels; i++) {
        struct chan_state *c = &channels[i];
        chan_set(c, 0, 0, 0);
        c->stack_size = 0;
    }
}

void chan_set(struct chan_state *c, int is_on, double vol, double pan) {
    c->is_on = is_on;
    c->vol = vol;
    c->pan = pan;
}

void chan_drop(struct chan_state *c) {
    for (int i = 0; i < c->stack_size; i++) {
        if (c->stack[i].proto->free) {
            c->stack[i].proto->free(c->stack[i].state);
        }
        free(c->stack[i].state);
    }
    c->stack_size = 0;
}

struct sfx_box *chan_push(struct chan_state *c, struct sfx_proto *proto) {
    if (c->stack_size < MAX_SFX_BOXES) {
        struct sfx_box *box = &c->stack[c->stack_size];
        box->proto = proto;
        box->state = calloc(1, proto->state_size);
        if (box->state || !box->proto->state_size) {
            proto->init(box->state);
            c->stack_size++;
            return box;
        }
    }
    return NULL;
}

static void chan_process(struct sfx_box *stack, int stack_size, double *l, double *r) {
    for (int i = 0; i < stack_size; i++) {
        if (stack[i].proto->stereo) {
            stack[i].proto->stereo(stack[i].state, l, r);
        } else {
            *l = stack[i].proto->mono(stack[i].state, *l);
            *r = *l;
        }
    }
}

void mix_process(struct chan_state *channels, int num_channels, double vol, float *samples, int num_samples) {
    for (; num_samples; num_samples--, samples += 2) {
        double left = 0, right = 0;
        for (int i = 0; i < num_channels; i++) {
            struct chan_state *c = &channels[i];
            double l = 0, r = 0;
            if (c->is_on) {
                chan_process(c->stack, c->stack_size, &l, &r);
                double pan = (c->pan + 1) * 0.5;
                left += c->vol * l * (1 - pan);
                right += c->vol * r * pan;
            }
        }
        samples[0] = vol * left;
        samples[1] = vol * right;
    }
}

#define SYNTH_LFOS 4

struct sfx_synth_state {
    struct phasor_state phase;
    struct adsr_state adsr;
    struct glide_state glide;
    struct noise_state noise;
    struct lfo_state lfo[SYNTH_LFOS];
    int lfo_target[SYNTH_LFOS];
    int lfo_current;
    int is_glide_on;
    int wave_type;
    double wave_width;
    double wave_offset;
    double freq;
    double freq_scaler;
    double vol;
};

enum {
    LFO_TARGET_NONE,
    LFO_TARGET_FREQ,
    LFO_TARGET_WIDTH,
    LFO_TARGET_OFFSET
};

static void sfx_synth_init(struct sfx_synth_state *s) {
    phasor_init(&s->phase);
    adsr_init(&s->adsr, 0);
    glide_init(&s->glide, 440, 100);
    noise_init(&s->noise, 16, (int[]) {0, 3, 10}, 3);
    for (int i = 0; i < SYNTH_LFOS; i++) {
        lfo_init(&s->lfo[i], ZV_SIN, 1, 0, 1, 0);
    }
    s->freq_scaler = 1;
    s->wave_type = ZV_SIN;
    s->wave_width = 0.5;
    s->wave_offset = 0.5;
}

static void sfx_synth_change(struct sfx_synth_state *s, int param, double val) {
    switch (param) {
    case ZV_VOLUME:
        s->vol = val;
        break;
    case ZV_NOTE_ON:
        s->freq = val;
        adsr_note_on(&s->adsr);
        for (int i = 0; i < SYNTH_LFOS; i++) {
            s->lfo[i].phase = 0;
        }
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
    case ZV_WAVE_OFFSET:
        s->wave_offset = val;
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
    case ZV_FREQ_SCALER:
        s->freq_scaler = val;
        break;
    case ZV_LFO_TO_FREQ:
        s->lfo_target[(int) limit(val, 0, SYNTH_LFOS - 1)] = LFO_TARGET_FREQ;
        break;
    case ZV_LFO_TO_WIDTH:
       s->lfo_target[(int) limit(val, 0, SYNTH_LFOS - 1)] = LFO_TARGET_WIDTH;
        break;
    case ZV_LFO_TO_OFFSET:
       s->lfo_target[(int) limit(val, 0, SYNTH_LFOS - 1)] = LFO_TARGET_OFFSET;
        break;
    case ZV_LFO_SELECT:
        s->lfo_current = limit(val, 0, SYNTH_LFOS - 1);
        break;
    case ZV_LFO_WAVE_TYPE:
        s->lfo[s->lfo_current].func = val;
        break;
    case ZV_LFO_WAVE_SIGN:
        s->lfo[s->lfo_current].sign = val;
        break;
    case ZV_LFO_FREQ:
        s->lfo[s->lfo_current].freq = val;
        break;
    case ZV_LFO_LEVEL:
        s->lfo[s->lfo_current].level = val;
        break;
    case ZV_LFO_IS_ONESHOT:
        s->lfo[s->lfo_current].is_oneshot = val;
        break;
    }
}

static double sfx_synth_mono(struct sfx_synth_state *s, double l) {
    (void) l;
    double freq = s->freq * s->freq_scaler;
    if (s->is_glide_on) {
        freq = glide_next(&s->glide, freq);
    }
    double width = s->wave_width;
    double offset = s->wave_offset;
    for(int i = 0; i < SYNTH_LFOS; i++) {
        if (s->lfo_target[i] == LFO_TARGET_FREQ) {
            freq += lfo_next(&s->lfo[i]);
        } else if (s->lfo_target[i] == LFO_TARGET_WIDTH) {
            width += lfo_next(&s->lfo[i]);
        } else if (s->lfo_target[i] == LFO_TARGET_OFFSET) {
            offset += lfo_next(&s->lfo[i]);
        }
    }
    double phase = phasor_next(&s->phase, limit(freq, 0, 15000));
    width = limit(width, 0, 0.9);
    double x = 0;
    if (s->wave_type == ZV_SIN) {
        x = sin(phase);
    } else if (s->wave_type == ZV_SAW) {
        x = saw(phase, width);
    } else if (s->wave_type == ZV_SQUARE) {
        x = square(phase, width);
    } else if (s->wave_type == ZV_PWM) {
        x = pwm(phase, offset, width);
    } else if (s->wave_type == ZV_FM) {
        x = dsf(phase, offset, width);
    } else if (s->wave_type == ZV_NOISE) {
        x = noise_next(&s->noise, freq);
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

static void sfx_delay_change(struct sfx_delay_state *s, int param, double val) {
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

static void sfx_dist_change(struct sfx_dist_state *s, int param, double val) {
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

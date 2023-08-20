/* Author: Peter Sovietov */

#include <math.h>
#include "zvon_sfx.h"

struct osc_state {
    int type;
    double params[OSC_PARAMS];
    struct phasor_state phasor1;
    struct noise_state noise1;
};

static void osc_init(struct osc_state *s) {
    s->type = OSC_SIN;
    s->params[OSC_FREQ] = 0;
    s->params[OSC_FMUL] = 1;
    s->params[OSC_AMP] = 1;
    s->params[OSC_WIDTH] = 0.5;
    s->params[OSC_OFFSET] = 1;
    phasor_init(&s->phasor1);
    noise_init(&s->noise1);
}

struct sfx_synth_state {
    struct osc_state osc;
    struct lfo_state lfos[SYNTH_LFOS];
    int lfo_targets[SYNTH_LFOS];
    double fmul[OSC_PARAMS];
    struct adsr_state adsr;
    int is_sustain_on;
    struct glide_state glide;
    int is_glide_on;
    int is_fm_on;
};

static void sfx_synth_init(struct sfx_synth_state *s) {
    osc_init(&s->osc);
    for (int i = 0; i < SYNTH_LFOS; i++) {
        lfo_init(&s->lfos[i]);
    }
    adsr_init(&s->adsr);
    s->is_sustain_on = 0;
    glide_init(&s->glide);
    s->is_glide_on = 0;
    s->is_fm_on = 0;
}

static void lfo_note_on(struct sfx_synth_state *s) {
    for (int i = 0; i < SYNTH_LFOS; i++) {
        lfo_reset(&s->lfos[i]);
    }
}

static void sfx_synth_change(struct sfx_synth_state *s, int param, int elem, double val) {
    switch (param) {
    case ZV_TYPE:
        s->osc.type = val;
        break;
    case ZV_SET_FM:
        s->is_fm_on = val;
        break;
    case ZV_FREQ:
        s->osc.params[OSC_FREQ] = val;
        break;
    case ZV_FMUL:
        elem = limit(elem, 0, OSC_PARAMS - 1);
        if (elem == OSC_FREQ) {
            s->osc.params[OSC_FMUL] = val;
        } else {
            s->fmul[elem] = val;
        }
        break;
    case ZV_AMP:
        s->osc.params[OSC_AMP] = val;
        break;
    case ZV_WIDTH:
        s->osc.params[OSC_WIDTH] = val;
        break;
    case ZV_OFFSET:
        s->osc.params[OSC_OFFSET] = val;
        break;
    case ZV_NOTE_ON:
        s->osc.params[OSC_FREQ] = val;
        adsr_note_on(&s->adsr, 0);
        lfo_note_on(s);
        break;
    case ZV_NOTE_OFF:
        adsr_note_off(&s->adsr);
        break;
    case ZV_SET_GLIDE:
        s->is_glide_on = val;
        break;
    case ZV_GLIDE_RATE:
        glide_set_rate(&s->glide, val);
        break;
    case ZV_ATTACK:
        adsr_set_attack(&s->adsr, val);
        break;
    case ZV_DECAY:
        adsr_set_decay(&s->adsr, val);
        break;
    case ZV_SUSTAIN:
        adsr_set_sustain(&s->adsr, val);
        break;
    case ZV_RELEASE:
        adsr_set_release(&s->adsr, val);
        break;
    case ZV_SET_SUSTAIN:
        s->is_sustain_on = val;
        break;
    case ZV_LFO_TYPE:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_type(&s->lfos[elem], val);
        break;
    case ZV_LFO_FREQ:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_freq(&s->lfos[elem], val);
        break;
    case ZV_LFO_LOW:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_low(&s->lfos[elem], val);
        break;
    case ZV_LFO_HIGH:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_high(&s->lfos[elem], val);
        break;
    case ZV_LFO_SET_LOOP:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_loop(&s->lfos[elem], val);
        break;
    case ZV_LFO_SET_RESET:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_reset(&s->lfos[elem], val);
        break;
    case ZV_LFO_SEQ_POS:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_seq_pos(&s->lfos[elem], val);
        break;
    case ZV_LFO_SEQ_VAL:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_seq_val(&s->lfos[elem], val);
        break;
    case ZV_LFO_SEQ_SIZE:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_seq_size(&s->lfos[elem], val);
        break;
    case ZV_LFO_ASSIGN:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        s->lfo_targets[elem] = limit(val, 0, OSC_PARAMS - 1);
        break;
    }
}

static double osc_noise(struct osc_state *s, int is_lin_on, double width, double freq) {
    noise_set_width(&s->noise1, width);
    if (is_lin_on) {
        return noise_lin_next(&s->noise1, freq);
    }
    return noise_next(&s->noise1, freq);
}

static double osc_next(struct osc_state *s, double freq, double width, double offset) {
    double w = limit(width, 0, 0.9);
    switch (s->type) {
    case OSC_SIN:
        return sin(phasor_next(&s->phasor1, freq));
    case OSC_SAW:
        return dsf(phasor_next(&s->phasor1, freq), 1, w);
    case OSC_SQUARE:
        return dsf(phasor_next(&s->phasor1, freq), 2, w);
    case OSC_DSF:
        return dsf(phasor_next(&s->phasor1, freq), offset, w);
    case OSC_DSF2:
        return dsf2(phasor_next(&s->phasor1, freq), offset, w);
    case OSC_PWM:
        return pwm(phasor_next(&s->phasor1, freq), offset, w);
    case OSC_NOISE:
        return osc_noise(s, 0, width, freq);
    case OSC_BAND_NOISE:
        return sin(phasor_next(&s->phasor1, freq + osc_noise(s, 0, width, offset)));
    case OSC_LIN_NOISE:
        return osc_noise(s, 1, width, freq);
    case OSC_LIN_BAND_NOISE:
        return sin(phasor_next(&s->phasor1, freq + osc_noise(s, 1, width, offset)));
    }
    return 0;
}

static double sfx_synth_mono(struct sfx_synth_state *s, double l) {
    double params[OSC_PARAMS];
    for(int i = 0; i < OSC_PARAMS; i++) {
        params[i] = s->osc.params[i];
    }
    double f = params[OSC_FREQ];
    if (s->is_glide_on) {
        f = glide_next(&s->glide, f);
    }
    params[OSC_FREQ] = s->is_fm_on ? l : 0;
    for(int i = 0; i < SYNTH_LFOS; i++) {
        params[s->lfo_targets[i]] += lfo_next(&s->lfos[i]);
    }
    s->fmul[OSC_FREQ] = params[OSC_FMUL];
    for(int i = 0; i < OSC_PARAMS; i++) {
        params[i] += f * s->fmul[i];
    }
    double y = params[OSC_AMP] * osc_next(&s->osc,
        params[OSC_FREQ], params[OSC_WIDTH], params[OSC_OFFSET]);
    y *= adsr_next(&s->adsr, s->is_sustain_on);
    return s->is_fm_on ? y : y + l;
}

struct sfx_proto sfx_synth = {
    .name = "synth",
    .init = (sfx_init_func) sfx_synth_init,
    .change = (sfx_change_func) sfx_synth_change,
    .mono = (sfx_mono_func) sfx_synth_mono,
    .state_size = sizeof(struct sfx_synth_state)
};

#define DELAY_BUF_SIZE 65536

struct sfx_delay_state {
    struct delay_state delay1;
    double buf[DELAY_BUF_SIZE];
};

static void sfx_delay_init(struct sfx_delay_state *s) {
    delay_init(&s->delay1, s->buf, DELAY_BUF_SIZE);
}

static void sfx_delay_change(struct sfx_delay_state *s, int param, int elem, double val) {
    (void) elem;
    switch (param) {
    case ZV_DELAY_TIME:
        delay_set_time(&s->delay1, val);
        break;
    case ZV_DELAY_LEVEL:
        delay_set_level(&s->delay1, val);
        break;
    case ZV_DELAY_FB:
        delay_set_fb(&s->delay1, val);
        break;
    }
}

static double sfx_delay_mono(struct sfx_delay_state *s, double l) {
    return delay_next(&s->delay1, l);
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
};

static void sfx_dist_init(struct sfx_dist_state *s) {
    s->gain = 1;
}

static void sfx_dist_change(struct sfx_dist_state *s, int param, int elem, double val) {
    (void) elem;
    switch (param) {
    case ZV_DIST_GAIN:
        s->gain = val;
        break;
    }
}

static double sfx_dist_mono(struct sfx_dist_state *s, double l) {
    return softclip(l, 10 * s->gain);
}

struct sfx_proto sfx_dist = {
    .name = "dist",
    .init = (sfx_init_func) sfx_dist_init,
    .change = (sfx_change_func) sfx_dist_change,
    .mono = (sfx_mono_func) sfx_dist_mono,
    .state_size = sizeof(struct sfx_dist_state)
};

struct sfx_filter_state {
    struct filter_state filter1;
    int mode;
    double width;
};

static void sfx_filter_init(struct sfx_filter_state *s) {
    filter_init(&s->filter1);
    s->mode = FILTER_LP;
    s->width = 0.5;
}

static void sfx_filter_change(struct sfx_filter_state *s, int param, int elem, double val) {
    (void) elem;
    switch (param) {
    case ZV_FILTER_MODE:
        s->mode = val;
        break;
    case ZV_FILTER_WIDTH:
        s->width = val;
        break;
    }
}

static double sfx_filter_mono(struct sfx_filter_state *s, double l) {
    if (s->mode == FILTER_LP) {
        return filter_lp_next(&s->filter1, l, s->width);
    } else if (s->mode == FILTER_HP) {
        return filter_hp_next(&s->filter1, l, s->width);
    }
    return 0;
}

struct sfx_proto sfx_filter = {
    .name = "filter",
    .init = (sfx_init_func) sfx_filter_init,
    .change = (sfx_change_func) sfx_filter_change,
    .mono = (sfx_mono_func) sfx_filter_mono,
    .state_size = sizeof(struct sfx_filter_state)
};

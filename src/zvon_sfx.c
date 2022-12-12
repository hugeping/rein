/* Author: Peter Sovietov */

#include <math.h>
#include "zvon_sfx.h"

void sfx_box_change(struct sfx_box *box, int param, int elem, double val) {
    switch (param) {
    case ZV_VOLUME:
        sfx_box_set_vol(box, val);
        break;
    default:
        if (box->state) {
            box->proto->change(box->state, param, elem, val);
        }
    }
}

struct osc_state {
    int mode;
    struct phasor_state phasor1;
    struct phasor_state phasor2;
    struct noise_state noise1;
};

static void osc_init(struct osc_state *s) {
    s->mode = OSC_SIN;
    phasor_init(&s->phasor1);
    phasor_init(&s->phasor2);
    noise_init(&s->noise1);
}

struct sfx_synth_state {
    struct osc_state osc;
    struct lfo_state lfo[SYNTH_LFOS];
    int lfo_target[SYNTH_LFOS];
    double lfo_param[LFO_TARGETS];
    int lfo_remap[LFO_TARGETS];
    double amp;
    double freq;
    double width;
    double offset;
    double freq_mul;
    struct adsr_state adsr;
    int is_sustain_on;
    struct glide_state glide;
    int is_glide_on;
};

static void lfo_reset_remap(struct sfx_synth_state *s) {
    for (int i = 0; i < LFO_TARGETS; i++) {
        s->lfo_remap[i] = i;
    }
}

static void sfx_synth_init(struct sfx_synth_state *s) {
    osc_init(&s->osc);
    for (int i = 0; i < SYNTH_LFOS; i++) {
        lfo_init(&s->lfo[i]);
    }
    lfo_reset_remap(s);
    s->amp = 1;
    s->freq = 0;
    s->freq_mul = 1;
    s->width = 0.5;
    s->offset = 0.5;
    adsr_init(&s->adsr);
    s->is_sustain_on = 0;
    glide_init(&s->glide);
    s->is_glide_on = 0;
}

static void lfo_note_on(struct sfx_synth_state *s) {
    for (int i = 0; i < SYNTH_LFOS; i++) {
        if (s->lfo[i].func == LFO_SEQ || !s->lfo[i].is_loop) {
            lfo_reset(&s->lfo[i]);
        }
    }
}

static void sfx_synth_change(struct sfx_synth_state *s, int param, int elem, double val) {
    (void) elem;
    switch (param) {
    case ZV_NOTE_ON:
        s->freq = val;
        adsr_note_on(&s->adsr, 0);
        lfo_note_on(s);
        break;
    case ZV_NOTE_OFF:
        adsr_note_off(&s->adsr);
        break;
    case ZV_SET_GLIDE_ON:
        glide_set_source(&s->glide, s->freq);
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
    case ZV_SET_SUSTAIN_ON:
        s->is_sustain_on = val;
        break;
    case ZV_FREQ_MUL:
        s->freq_mul = val;
        break;
    case ZV_MODE:
        s->osc.mode = val;
        break;
    case ZV_AMP:
        s->amp = val;
        break;
    case ZV_WIDTH:
        s->width = val;
        break;
    case ZV_OFFSET:
        s->offset = val;
        break;
    case ZV_REMAP_FREQ:
        lfo_reset_remap(s);
        int idx = limit(val, 0, LFO_TARGETS - 1);
        int old = s->lfo_remap[idx];
        s->lfo_remap[idx] = LFO_TARGET_FREQ;
        s->lfo_remap[LFO_TARGET_FREQ] = old;
        break;
    case ZV_LFO_FUNC:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_func(&s->lfo[elem], val);
        break;
    case ZV_LFO_FREQ:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_freq(&s->lfo[elem], val);
        break;
    case ZV_LFO_LOW:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_low(&s->lfo[elem], val);
        break;
    case ZV_LFO_HIGH:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_high(&s->lfo[elem], val);
        break;
    case ZV_LFO_LOOP:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        lfo_set_loop(&s->lfo[elem], val);
        break;
    case ZV_LFO_SEQ_POS:
        lfo_set_seq_pos(&s->lfo[elem], val);
        break;
    case ZV_LFO_SEQ_VAL:
        lfo_set_seq_val(&s->lfo[elem], val);
        break;
    case ZV_LFO_SEQ_SIZE:
        lfo_set_seq_size(&s->lfo[elem], val);
        break;
    case ZV_LFO_ASSIGN:
        elem = limit(elem, 0, SYNTH_LFOS - 1);
        s->lfo_target[elem] = limit(val, 0, LFO_TARGETS - 1);
        break;
    }
}

static double osc_next(struct osc_state *s, double *lfo_param) {
    double amp = lfo_param[LFO_TARGET_AMP];
    double freq = lfo_param[LFO_TARGET_FREQ];
    double width = lfo_param[LFO_TARGET_WIDTH];
    double offset = lfo_param[LFO_TARGET_OFFSET];
    double w = limit(width, 0, 0.9);
    switch (s->mode) {
    case OSC_SIN:
        return amp * sin(phasor_next(&s->phasor1, freq));
    case OSC_SAW:
        return amp * saw(phasor_next(&s->phasor1, freq), w);
    case OSC_SQUARE:
        return amp * square(phasor_next(&s->phasor1, freq), w);
    case OSC_DSF:
        return amp * dsf(phasor_next(&s->phasor1, freq), offset, w);
    case OSC_DSF2:
        return amp * dsf2(phasor_next(&s->phasor1, freq), offset, w);
    case OSC_PWM:
        return amp * pwm(phasor_next(&s->phasor1, freq), offset, w);
    case OSC_NOISE8:
        noise_set_width(&s->noise1, 2);
        return amp * noise_next(&s->noise1, freq);
    case OSC_NOISE:
        noise_set_width(&s->noise1, amp);
        return sin(phasor_next(&s->phasor1, freq + noise_lin_next(&s->noise1, width)));
    case OSC_SIN_NOISE:
        noise_set_width(&s->noise1, amp);
        double y1 = sin(phasor_next(&s->phasor1, freq));
        double y2 = sin(phasor_next(&s->phasor2, offset + noise_lin_next(&s->noise1, width)));
        return y1 + y2;
    }
    return 0;
}

static double sfx_synth_mono(struct sfx_synth_state *s, double l) {
    (void) l;
    s->lfo_param[s->lfo_remap[LFO_TARGET_AMP]] = s->amp;
    s->lfo_param[s->lfo_remap[LFO_TARGET_FREQ]] = 0;
    s->lfo_param[s->lfo_remap[LFO_TARGET_FREQ_MUL]] = s->freq_mul;
    s->lfo_param[s->lfo_remap[LFO_TARGET_WIDTH]] = s->width;
    s->lfo_param[s->lfo_remap[LFO_TARGET_OFFSET]] = s->offset;
    for(int i = 0; i < SYNTH_LFOS; i++) {
        s->lfo_param[s->lfo_remap[s->lfo_target[i]]] += lfo_next(&s->lfo[i]);
    }
    double freq = s->is_glide_on ? glide_next(&s->glide, s->freq) : s->freq;
    freq *= s->lfo_param[s->lfo_remap[LFO_TARGET_FREQ_MUL]];
    s->lfo_param[s->lfo_remap[LFO_TARGET_FREQ]] += freq;
    double y = osc_next(&s->osc, s->lfo_param);
    return y * adsr_next(&s->adsr, s->is_sustain_on);
}

struct sfx_proto sfx_synth = {
    .name = "synth",
    .init = (sfx_init_func) sfx_synth_init,
    .change = (sfx_change_func) sfx_synth_change,
    .mono = (sfx_mono_func) sfx_synth_mono,
    .state_size = sizeof(struct sfx_synth_state)
};

#define SFX_DELAY_BUF_SIZE 65536

struct sfx_delay_state {
    struct delay_state delay1;
    double buf[SFX_DELAY_BUF_SIZE];
};

static void sfx_delay_init(struct sfx_delay_state *s) {
    delay_init(&s->delay1, s->buf, SFX_DELAY_BUF_SIZE);
}

static void sfx_delay_change(struct sfx_delay_state *s, int param, int elem, double val) {
    (void) elem;
    switch (param) {
    case ZV_TIME:
        delay_set_time(&s->delay1, val);
        break;
    case ZV_LEVEL:
        delay_set_level(&s->delay1, val);
        break;
    case ZV_FEEDBACK:
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
    case ZV_GAIN:
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
    s->mode = ZV_LOWPASS;
    s->width = 0.5;
}

static void sfx_filter_change(struct sfx_filter_state *s, int param, int elem, double val) {
    (void) elem;
    switch (param) {
    case ZV_MODE:
        s->mode = val;
        break;
    case ZV_WIDTH:
        s->width = val;
        break;
    }
}

static double sfx_filter_mono(struct sfx_filter_state *s, double l) {
    if (s->mode == ZV_LOWPASS) {
        return filter_lp_next(&s->filter1, l, s->width);
    } else if (s->mode == ZV_HIGHPASS) {
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

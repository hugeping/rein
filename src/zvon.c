/* Author: Peter Sovietov */

#include <math.h>
#include "zvon.h"

int sec(double t) {
    return t * SR;
}

double midi_freq(int m) {
    return 440 * pow(2, (m - 69) * (1 / 12.));
}

double limit(double x, double low, double high) {
    return MIN(MAX(x, low), high);
}

double lerp(double x, double y, double a) {
    return x + a * (y - x);
}

double dsf(double phase, double mod, double width) {
    double mphase = mod * phase;
    double n = sin(phase) - width * sin(phase - mphase);
    return n / (1 + width * (width - 2 * cos(mphase)));
}

double dsf2(double phase, double mod, double width) {
    double mphase = mod * phase;
    double n = sin(phase) * (1 - width * width);
    return n / (1 + width * (width - 2 * cos(mphase)));
}

double saw(double phase, double width) {
    return dsf(phase, 1, width);
}

double square(double phase, double width) {
    return dsf(phase, 2, width);
}

double pwm(double phase, double offset, double width) {
    return saw(phase, width) - saw(phase + offset, width);
}

static unsigned int xorshift(unsigned int x) {
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

double softclip(double x, double gain) {
    return tanh(x * gain);
}

void phasor_init(struct phasor_state *s) {
    s->phase = 0;
}

double phasor_next(struct phasor_state *s, double freq) {
    double p = s->phase;
    s->phase = fmod(s->phase + (2 * PI / SR) * freq, SR * PI);
    return p;
}

enum {
    ADSR_ATTACK,
    ADSR_DECAY,
    ADSR_SUSTAIN,
    ADSR_RELEASE,
    ADSR_END
};

void adsr_init(struct adsr_state *s) {
    s->state = ADSR_END;
    s->level = 0;
    adsr_set_attack(s, 0.01);
    adsr_set_decay(s, 0.1);
    s->sustain = 0.5;
    adsr_set_release(s, 0.3);
}

void adsr_set_attack(struct adsr_state *s, double attack) {
    s->attack = attack;
    int dt = sec(attack);
    s->attack_step = 1. / (dt ? dt : 1);
}

void adsr_set_decay(struct adsr_state *s, double decay) {
    s->decay = decay;
    int dt = sec(decay);
    s->decay_step = (1 - s->sustain) / (dt ? dt : 1);
}

void adsr_set_sustain(struct adsr_state *s, double sustain) {
    s->sustain = sustain;
    adsr_set_decay(s, s->decay);
    adsr_set_release(s, s->release);
}

void adsr_set_release(struct adsr_state *s, double release) {
    s->release = release;
    int dt = sec(release);
    s->release_step = s->sustain / (dt ? dt : 1);
}

void adsr_note_on(struct adsr_state *s, int is_reset_level_on) {
    s->state = ADSR_ATTACK;
    if (is_reset_level_on) {
        s->level = 0;
    }
}

void adsr_note_off(struct adsr_state *s) {
    s->state = ADSR_RELEASE;
}

double adsr_next(struct adsr_state *s, int is_sustain_on) {
    switch (s->state) {
    case ADSR_ATTACK:
        s->level += s->attack_step;
        if (s->level >= 1) {
            s->level = 1;
            s->state = ADSR_DECAY;
        }
        break;
    case ADSR_DECAY:
        s->level -= s->decay_step;
        if (s->level <= s->sustain) {
            s->level = s->sustain;
            s->state = is_sustain_on ? ADSR_SUSTAIN : ADSR_RELEASE;
        }
        break;
    case ADSR_RELEASE:
        s->level -= s->release_step;
        if (s->level <= 0) {
            s->level = 0;
            s->state = ADSR_END;
        }
        break;
    }
    return s->level;
}

void delay_init(struct delay_state *s, double *buf, int buf_size) {
    s->buf = buf;
    for (int i = 0; i < buf_size; i++) {
        s->buf[i] = 0;
    }
    s->buf_size = buf_size;
    s->pos = 0;
    s->size = buf_size;
    delay_set_level(s, 0.5);
    delay_set_fb(s, 0.5);
}

void delay_set_time(struct delay_state *s, double time) {
    s->size = limit(sec(time), 1, s->buf_size);
}

void delay_set_level(struct delay_state *s, double level) {
    s->level = level;
}
void delay_set_fb(struct delay_state *s, double fb) {
    s->fb = fb;
}

double delay_next(struct delay_state *s, double x) {
    double y = x + s->buf[s->pos] * s->level;
    s->buf[s->pos] = x + s->buf[s->pos] * s->fb;
    s->pos = (s->pos + 1) % s->size;
    return y;
}

void filter_init(struct filter_state *s) {
    s->y = 0;
}

double filter_lp_next(struct filter_state *s, double x, double width) {
    s->y += width * (x - s->y);
    return s->y;
}

double filter_hp_next(struct filter_state *s, double x, double width) {
    return x - filter_lp_next(s, x, 1 - width);
}

void glide_init(struct glide_state *s) {
    glide_set_source(s, 440);
    glide_set_rate(s, 100);
}

void glide_set_source(struct glide_state *s, double source) {
    s->source = source;
}

void glide_set_rate(struct glide_state *s, double rate) {
    s->rate = rate * (1. / SR);
}

double glide_next(struct glide_state *s, double target) {
    double step = s->rate * fabs(s->source - target) + 1e-6;
    if (s->source < target) {
        s->source = MIN(s->source + step, target);
    } else {
        s->source = MAX(s->source - step, target);
    }
    return s->source;
}

void noise_init(struct noise_state *s) {
    s->phase = 0;
    s->state = 1;
    s->old_y = 0;
    s->y = 0;
    noise_set_width(s, 2);
}

void noise_set_width(struct noise_state *s, unsigned int width) {
    width++;
    s->width = width < 2 ? 2 : width;
}

double noise_lin_next(struct noise_state *s, double freq) {
    s->phase += freq * (1. / SR);
    if (s->phase >= 1) {
        s->phase -= 1;
        s->state = xorshift(s->state);
        s->old_y = s->y;
        s->y = s->state % s->width;
    }
    return lerp(s->old_y, s->y, s->phase) - s->width / 2;
}

double noise_next(struct noise_state *s, double freq) {
    s->phase += freq * (1. / SR);
    if (s->phase >= 1) {
        s->phase -= 1;
        s->state = xorshift(s->state);
        s->y = s->state % s->width;
    }
    return (double) s->y - s->width / 2;
}

void lfo_init(struct lfo_state *s) {
    s->freq = 0;
    lfo_reset(s);
    for (int i = 0; i < LFO_MAX_SEQ_STEPS; i++) {
        s->seq[i] = 0;
    }
    s->edit_pos = 0;
    lfo_set_seq_size(s, 0);
    lfo_is_lin_seq(s, 0);
    lfo_set_func(s, LFO_ZERO);
    lfo_set_freq(s, 0);
    lfo_set_low(s, 0);
    lfo_set_high(s, 0);
    lfo_set_loop(s, 1);
}

void lfo_reset(struct lfo_state *s) {
    s->phase = 0;
    s->prev = 0;
    s->pos = 0;
}

void lfo_set_func(struct lfo_state *s, int func) {
    s->func = func;
}

void lfo_set_freq(struct lfo_state *s, double freq) {
    s->freq = freq;
}

void lfo_set_low(struct lfo_state *s, double low) {
    s->low = low;
 }

void lfo_set_high(struct lfo_state *s, double high) {
    s->high = high;
 }

void lfo_set_loop(struct lfo_state *s, int is_loop) {
    s->is_loop = is_loop;
}

void lfo_set_seq_pos(struct lfo_state *s, int pos) {
    s->edit_pos = limit(pos, 0, LFO_MAX_SEQ_STEPS - 1);
}

void lfo_set_seq_val(struct lfo_state *s, double val) {
    s->seq[s->edit_pos] = val;
}

void lfo_set_seq_size(struct lfo_state *s, int size) {
    s->seq_size = limit(size, 0, LFO_MAX_SEQ_STEPS);
}

void lfo_is_lin_seq(struct lfo_state *s, int is_lin_seq) {
    s->is_lin_seq = is_lin_seq;
}

static double lfo_func(struct lfo_state *s) {
    double x = s->phase;
    switch (s->func) {
    case LFO_SIN:
        return (sin(x * 2 * PI) + 1) * 0.5;
    case LFO_SAW:
        return x;
    case LFO_SQUARE:
        return floor(x * 2);
    case LFO_TRIANGLE:
        return 2 * (x - floor(2 * x) * (2 * x - 1));
    case LFO_SEQ:
        if (s->is_lin_seq) {
            return lerp(s->prev, s->seq[s->pos], x);
        }
        return s->seq[s->pos];
    default:
        return 0;
    }
}

static void lfo_seq_next(struct lfo_state *s) {
    s->phase = 0;
    s->prev = s->seq[s->pos];
    s->pos++;
    if (s->pos >= s->seq_size) {
        s->pos = s->is_loop ? 0 : s->seq_size - 1;
    }
}

double lfo_next(struct lfo_state *s) {
    double y = s->low + (s->high - s->low) * lfo_func(s);
    s->phase += s->freq * (1. / SR);
    if (s->phase >= 1) {
        if (s->func == LFO_SEQ) {
            lfo_seq_next(s);
        } else {
            s->phase = s->is_loop ? s->phase - 1 : 1;
        }
    }
    return y;
}

/* Author: Peter Sovietov */

#ifndef ZVON_SFX_H
#define ZVON_SFX_H

#include "zvon_mixer.h"

void sfx_box_change(struct sfx_box *box, int param, int elem, double val);

enum {
    ZV_VOLUME,
    ZV_NOTE_ON,
    ZV_NOTE_OFF,
    ZV_FREQ,
    ZV_SET_GLIDE,
    ZV_GLIDE_RATE,
    ZV_FREQ_MUL,
    ZV_ATTACK,
    ZV_DECAY,
    ZV_SUSTAIN,
    ZV_RELEASE,
    ZV_SET_SUSTAIN,
    ZV_AMP,
    ZV_WIDTH,
    ZV_OFFSET,
    ZV_LFO_FUNC,
    ZV_LFO_FREQ,
    ZV_LFO_LOW,
    ZV_LFO_HIGH,
    ZV_LFO_SET_LOOP,
    ZV_LFO_SET_RESET,
    ZV_LFO_SEQ_POS,
    ZV_LFO_SEQ_VAL,
    ZV_LFO_SEQ_SIZE,
    ZV_LFO_SET_LIN_SEQ,
    ZV_LFO_ASSIGN,
    ZV_TIME,
    ZV_LEVEL,
    ZV_FEEDBACK,
    ZV_GAIN,
    ZV_MODE,
    ZV_HIGHPASS,
    ZV_LOWPASS,
    ZV_END
};

enum {
    OSC_SIN,
    OSC_SAW,
    OSC_SQUARE,
    OSC_DSF,
    OSC_DSF2,
    OSC_PWM,
    OSC_NOISE,
    OSC_LNOISE,
    OSC_RNOISE,
    OSC_RLNOISE,
    OSC_SIN_RLNOISE
};

#define SYNTH_LFOS 4

enum {
    LFO_TARGET_AMP,
    LFO_TARGET_FREQ,
    LFO_TARGET_FREQ_MUL,
    LFO_TARGET_WIDTH,
    LFO_TARGET_OFFSET,
    LFO_TARGETS
};

extern struct sfx_proto sfx_synth;
extern struct sfx_proto sfx_delay;
extern struct sfx_proto sfx_dist;
extern struct sfx_proto sfx_filter;

#endif

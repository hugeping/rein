/* Author: Peter Sovietov */

#ifndef ZVON_SFX_H
#define ZVON_SFX_H

#include "zvon_mixer.h"

enum {
    ZV_VOLUME = SFX_BOX_VOLUME,
    ZV_TYPE,
    ZV_SET_FM,
    ZV_FREQ,
    ZV_FMUL,
    ZV_AMP,
    ZV_WIDTH,
    ZV_OFFSET,
    ZV_NOTE_ON,
    ZV_NOTE_OFF,
    ZV_SET_GLIDE,
    ZV_GLIDE_RATE,
    ZV_ATTACK,
    ZV_DECAY,
    ZV_SUSTAIN,
    ZV_RELEASE,
    ZV_SET_SUSTAIN,
    ZV_LFO_TYPE,
    ZV_LFO_FREQ,
    ZV_LFO_LOW,
    ZV_LFO_HIGH,
    ZV_LFO_SET_LOOP,
    ZV_LFO_SET_RESET,
    ZV_LFO_SEQ_POS,
    ZV_LFO_SEQ_VAL,
    ZV_LFO_SEQ_SIZE,
    ZV_LFO_ASSIGN,
    ZV_DELAY_TIME,
    ZV_DELAY_LEVEL,
    ZV_DELAY_FB,
    ZV_DIST_GAIN,
    ZV_FILTER_MODE,
    ZV_FILTER_WIDTH,
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
    OSC_BAND_NOISE,
    OSC_LIN_NOISE,
    OSC_LIN_BAND_NOISE
};

enum {
    OSC_FREQ,
    OSC_FMUL,
    OSC_AMP,
    OSC_WIDTH,
    OSC_OFFSET,
    OSC_PARAMS
};

enum {
    FILTER_HP,
    FILTER_LP
};

#define SYNTH_LFOS 4

extern struct sfx_proto sfx_synth;
extern struct sfx_proto sfx_delay;
extern struct sfx_proto sfx_dist;
extern struct sfx_proto sfx_filter;

#endif

/* Author: Peter Sovietov */

#ifndef ZVON_SFX_H
#define ZVON_SFX_H

#include "zvon.h"

enum {
    ZV_NOTE_ON,
    ZV_NOTE_OFF,
    ZV_VOLUME,
    ZV_TIME,
    ZV_FEEDBACK,
    ZV_GAIN,
    ZV_WAVE_TYPE,
    ZV_WAVE_WIDTH,
    ZV_ATTACK_TIME,
    ZV_DECAY_TIME,
    ZV_SUSTAIN_LEVEL,
    ZV_RELEASE_TIME,
    ZV_GLIDE_ON,
    ZV_GLIDE_OFF,
    ZV_FREQ_LFO_WAVE_TYPE,
    ZV_FREQ_LFO_WAVE_SIGN,
    ZV_FREQ_LFO_FREQ,
    ZV_FREQ_LFO_LEVEL,
    ZV_FREQ_LFO_IS_ONESHOT,
    ZV_WIDTH_LFO_WAVE_TYPE,
    ZV_WIDTH_LFO_WAVE_SIGN,
    ZV_WIDTH_LFO_FREQ,
    ZV_WIDTH_LFO_LEVEL,
    ZV_WIDTH_LFO_IS_ONESHOT,
    ZV_END
};

extern struct sfx_proto sfx_synth;
extern struct sfx_proto sfx_delay;
extern struct sfx_proto sfx_dist;

#endif

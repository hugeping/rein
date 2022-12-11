#include "external.h"
#include "platform.h"

#include "zvon.h"
#include "zvon_sfx.h"

#define CHANNELS_MAX 32

static double
empty_mono(void *s, double x)
{
	return 0.0;
}

static void
empty_change(void *s, int param, float val)
{
}

static void
empty_init(void *s)
{
}

static struct sfx_proto empty_box = {
	.name = "empty",
	.init = (sfx_init_func) empty_init,
	.change = (sfx_change_func) empty_change,
	.mono = (sfx_mono_func) empty_mono,
	.state_size = 0,
};

static struct sfx_proto *boxes[] = { &empty_box, &sfx_delay, &sfx_dist, &sfx_synth, &sfx_filter, NULL };

static struct chan_state channels[CHANNELS_MAX];

static int
synth_change(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	int nr = luaL_checkinteger(L, 2);
	const int param = luaL_checkinteger(L, 3);
	int elem = 0;
	double val;
	struct sfx_box *box;

	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");

	if (lua_isnumber(L, 5)) {
		elem = luaL_checkinteger(L, 4);
		val = luaL_checknumber(L, 5);
	} else
		val = luaL_checknumber(L, 4);
	if (nr < 0)
		nr = channels[chan].stack_size + nr;
	if (nr < 0 || nr >= channels[chan].stack_size)
		return luaL_error(L, "Wrong stack position");
	box = &channels[chan].stack[nr];
	sfx_box_change(box, param, elem, val);
	return 0;
}

static int
synth_push(lua_State *L)
{
	int i = 0;
	struct chan_state *chan_state;
	const int chan = luaL_checkinteger(L, 1);
	const char *box = luaL_checkstring(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_state = &channels[chan];
	if (chan_state->stack_size >= SFX_MAX_BOXES)
		return luaL_error(L, "Maximum boxes reached");
	while (boxes[i] && strcmp(boxes[i]->name, box)) i++;
	if (!boxes[i])
		return luaL_error(L, "Unknown box name: %s", box);
	chan_push(&channels[chan], boxes[i]);
	lua_pushinteger(L, chan_state->stack_size - 1);
	return 1;
}

static int
synth_drop(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_drop(&channels[chan]);
	return 0;
}

static int
synth_set_on(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_set_on(&channels[chan], lua_toboolean(L, 2));
	return 0;
}

static int
synth_set_vol(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const double val = luaL_checknumber(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_set_vol(&channels[chan], val);
	return 0;
}

static int
synth_set_pan(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const double pan = luaL_checknumber(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_set_pan(&channels[chan], pan);
	return 0;
}

static int
synth_mix(lua_State *L)
{
	int samples = luaL_checkinteger(L, 1);
	const double vol = luaL_optnumber(L, 2, 1.0f);
	unsigned int free = AudioWrite(NULL, 0);
	#define SAMPLES_NR 128
	float floats[SAMPLES_NR*2];
	signed short buf[SAMPLES_NR*2];
	int nr, written, i;
	if (samples > free / 4) /* stereo * sizeof(short) */
		samples = free / 4;
	written = samples;
	while (samples > 0) {
		nr = (samples > SAMPLES_NR)?SAMPLES_NR:samples;
		mix_process(channels, CHANNELS_MAX, vol, floats, nr);
		for (i = 0; i < nr*2; i ++)
			buf[i] = (signed short)(floats[i] * 32768.0);
		AudioWrite(buf, nr * 4);
		samples -= nr;
	}
	#undef SAMPLES_NR
	lua_pushinteger(L, written);
	return 1;
}

static int
synth_stop(lua_State *L)
{
	int i;
	const int chan = luaL_optinteger(L, 1, -1);
	if (chan == -1) {
		for (i = 0; i < CHANNELS_MAX; i ++) {
			chan_drop(&channels[i]);
			chan_set_on(&channels[i], 0);
		}
		return 0;
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_drop(&channels[chan]);
	chan_set_on(&channels[chan], 0);
	chan_set_pan(&channels[chan], 0);
	chan_set_vol(&channels[chan], 0);
	return 0;
}

static const luaL_Reg
synth_lib[] = {
	{ "push", synth_push },
	{ "drop", synth_drop },
	{ "on", synth_set_on },
	{ "vol", synth_set_vol },
	{ "pan", synth_set_pan },
	{ "change", synth_change },
	{ "mix", synth_mix },
	{ "stop", synth_stop },
	{ NULL, NULL }
};

static struct {
	const char *name;
	int val;
} constants[] = {
	{ "VOLUME", ZV_VOLUME },
	/* synth */
	{ "NOTE_ON", ZV_NOTE_ON },
	{ "NOTE_OFF", ZV_NOTE_OFF },
	{ "GLIDE_ON", ZV_GLIDE_ON },
	{ "GLIDE_OFF", ZV_GLIDE_OFF },
	{ "ATTACK", ZV_ATTACK },
	{ "DECAY", ZV_DECAY },
	{ "SUSTAIN", ZV_SUSTAIN },
	{ "RELEASE", ZV_RELEASE },
	{ "SUSTAIN_ON", ZV_SUSTAIN_ON },
	{ "FREQ_MUL", ZV_FREQ_MUL },
	{ "MODE", ZV_MODE }, /* +filter */
	{ "AMP", ZV_AMP },
	{ "WIDTH", ZV_WIDTH }, /* +fliter */
	{ "OFFSET", ZV_OFFSET },
	{ "REMAP", ZV_REMAP },
	{ "LFO_FUNC", ZV_LFO_FUNC },
	{ "LFO_FREQ", ZV_LFO_FREQ },
	{ "LFO_LOW", ZV_LFO_LOW },
	{ "LFO_HIGH", ZV_LFO_HIGH },
	{ "LFO_LOOP", ZV_LFO_LOOP },
	{ "LFO_ASSIGN", ZV_LFO_ASSIGN },
	/* delay */
	{ "TIME", ZV_TIME },
	{ "LEVEL", ZV_LEVEL },
	{ "FEEDBACK", ZV_FEEDBACK },
	/* dist */
	{ "GAIN", ZV_GAIN },
	/* filter */
	{ "LOWPASS", ZV_LOWPASS },
	{ "HIGHPASS", ZV_HIGHPASS },
	/* values */
	{ "OSC_SIN", OSC_SIN },
	{ "OSC_SAW", OSC_SAW },
	{ "OSC_SQUARE", OSC_SQUARE },
	{ "OSC_DSF", OSC_DSF },
	{ "OSC_DSF2", OSC_DSF2 },
	{ "OSC_PWM", OSC_PWM },
	{ "OSC_SIN_NOISE", OSC_SIN_NOISE },
	{ "OSC_NOISE8", OSC_NOISE8 },
	{ "LFO_NONE", LFO_NONE },
	{ "LFO_SIN", LFO_SIN },
	{ "LFO_SAW", LFO_SAW },
	{ "LFO_SQUARE", LFO_SQUARE },
	{ "LFO_TRIANGLE", LFO_TRIANGLE },
	{ "LFO_PARAM_AMP", LFO_PARAM_AMP },
	{ "LFO_PARAM_FREQ", LFO_PARAM_FREQ },
	{ "LFO_PARAM_WIDTH", LFO_PARAM_WIDTH },
	{ "LFO_PARAM_OFFSET", LFO_PARAM_OFFSET },
	{ NULL }
};

int
luaopen_synth(lua_State *L)
{
	int i;
	mix_init(channels, CHANNELS_MAX);
	luaL_newlib(L, synth_lib);
	for (i = 0; constants[i].name; i++) {
		lua_pushstring(L, constants[i].name);
		lua_pushinteger(L, constants[i].val);
		lua_rawset(L, -3);
	}
	return 1;
}

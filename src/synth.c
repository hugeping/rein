#include "external.h"
#include "platform.h"
#include "zvon_sfx.h"

#define CHANNELS_MAX 32

enum {
	ZV_BYPASS = ZV_END + 1,
};

static int mutex;

static double
empty_mono(void *s, double x)
{
	return 0.0;
}

static void
empty_change(void *s, int param, double val)
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

static double
bypass_mono(void *s, double x)
{
	return x;
}

static struct sfx_proto bypass_box = {
	.name = "bypass",
	.init = (sfx_init_func) empty_init,
	.change = (sfx_change_func) empty_change,
	.mono = (sfx_mono_func) bypass_mono,
	.state_size = 0,
};

static struct sfx_proto *boxes[] = { &empty_box, &bypass_box, &sfx_delay, &sfx_dist, &sfx_synth, &sfx_filter, NULL };

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
	MutexLock(mutex);
	if (nr < 0)
		nr = channels[chan].stack_size + nr;
	if (nr < 0 || nr >= channels[chan].stack_size) {
		MutexUnlock(mutex);
		return luaL_error(L, "Wrong stack position");
	}
	box = &channels[chan].stack[nr];
	sfx_box_change(box, param, elem, val);
	MutexUnlock(mutex);
	return 0;
}

#if 0
static int
synth_peek(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	int nr = luaL_checkinteger(L, 2);
	struct sfx_box *box;

	if (chan < 0 || chan >= CHANNELS_MAX)
		return 0;

	MutexLock(mutex);
	if (nr < 0)
		nr = channels[chan].stack_size + nr;
	if (nr < 0 || nr >= channels[chan].stack_size) {
		MutexUnlock(mutex);
		return 0;
	}
	box = &channels[chan].stack[nr];
	lua_pushstring(L, box->proto->name);
	MutexUnlock(mutex);
	return 1;
}
#endif
static int
synth_push(lua_State *L)
{
	int i = 0;
	struct chan_state *chan_state;
	const int chan = luaL_checkinteger(L, 1);
	const char *box = luaL_checkstring(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	chan_state = &channels[chan];
	if (chan_state->stack_size >= SFX_MAX_BOXES) {
		MutexUnlock(mutex);
		return luaL_error(L, "Maximum boxes reached");
	}
	while (boxes[i] && strcmp(boxes[i]->name, box)) i++;
	if (!boxes[i]) {
		MutexUnlock(mutex);
		return luaL_error(L, "Unknown box name: %s", box);
	}
	chan_push(&channels[chan], boxes[i]);
	MutexUnlock(mutex);
	lua_pushinteger(L, chan_state->stack_size - 1);
	return 1;
}

static int
synth_drop(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	chan_drop(&channels[chan]);
	MutexUnlock(mutex);
	return 0;
}

static int
synth_set_on(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	chan_set_on(&channels[chan], lua_toboolean(L, 2));
	MutexUnlock(mutex);
	return 0;
}

static int
synth_set_vol(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const double val = luaL_checknumber(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	chan_set_vol(&channels[chan], val);
	MutexUnlock(mutex);
	return 0;
}

static int
synth_mul_vol(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const double val = luaL_checknumber(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	channels[chan].vol *= val;
	MutexUnlock(mutex);
	return 0;
}

static int
synth_set_pan(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const double pan = luaL_checknumber(L, 2);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	chan_set_pan(&channels[chan], pan);
	MutexUnlock(mutex);
	return 0;
}

static int
synth_mix(lua_State *L)
{
	int samples = luaL_checkinteger(L, 1);
	const double vol = luaL_optnumber(L, 2, 1.0f);
	unsigned int free;
	#define SAMPLES_NR 128
	float floats[SAMPLES_NR*2];
	signed short buf[SAMPLES_NR*2];
	int nr, written, i;
	MutexLock(mutex);
	free = AudioWrite(NULL, 0);
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
	MutexUnlock(mutex);
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
		MutexLock(mutex);
		for (i = 0; i < CHANNELS_MAX; i ++) {
			chan_drop(&channels[i]);
			chan_set_on(&channels[i], 0);
		}
		MutexUnlock(mutex);
		return 0;
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	MutexLock(mutex);
	chan_drop(&channels[chan]);
	chan_set_on(&channels[chan], 0);
	chan_set_pan(&channels[chan], 0);
	chan_set_vol(&channels[chan], 0);
	MutexUnlock(mutex);
	return 0;
}

static const luaL_Reg
synth_lib[] = {
	{ "push", synth_push },
	{ "drop", synth_drop },
	{ "on", synth_set_on },
	{ "vol", synth_set_vol },
	{ "mul_vol", synth_mul_vol },
	{ "pan", synth_set_pan },
	{ "change", synth_change },
//	{ "peek", synth_peek },
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
	{ "TYPE", ZV_TYPE },
	{ "FREQ", ZV_FREQ },
	{ "FMUL", ZV_FMUL },
	{ "AMP", ZV_AMP },
	{ "WIDTH", ZV_WIDTH },
	{ "OFFSET", ZV_OFFSET },
	{ "SET_LIN", ZV_SET_LIN },
	{ "FREQ2", ZV_FREQ2 },
	{ "NOTE_ON", ZV_NOTE_ON },
	{ "NOTE_OFF", ZV_NOTE_OFF },
	{ "SET_GLIDE", ZV_SET_GLIDE },
	{ "GLIDE_RATE", ZV_GLIDE_RATE },
	{ "ATTACK", ZV_ATTACK },
	{ "DECAY", ZV_DECAY },
	{ "SUSTAIN", ZV_SUSTAIN },
	{ "RELEASE", ZV_RELEASE },
	{ "SET_SUSTAIN", ZV_SET_SUSTAIN },
	{ "REMAP", ZV_REMAP },
	{ "LFO_TYPE", ZV_LFO_TYPE },
	{ "LFO_FREQ", ZV_LFO_FREQ },
	{ "LFO_LOW", ZV_LFO_LOW },
	{ "LFO_HIGH", ZV_LFO_HIGH },
	{ "LFO_SET_LOOP", ZV_LFO_SET_LOOP },
	{ "LFO_SEQ_POS", ZV_LFO_SEQ_POS },
	{ "LFO_SEQ_VAL", ZV_LFO_SEQ_VAL },
	{ "LFO_SEQ_SIZE", ZV_LFO_SEQ_SIZE },
	{ "LFO_ASSIGN", ZV_LFO_ASSIGN },
	{ "LFO_SET_RESET", ZV_LFO_SET_RESET },
	{ "LFO_SET_LIN_SEQ", ZV_LFO_SET_LIN_SEQ },
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
	{ "OSC_NOISE", OSC_NOISE },
	{ "OSC_BAND_NOISE", OSC_BAND_NOISE },
	{ "OSC_SIN_BAND_NOISE", OSC_SIN_BAND_NOISE },
	{ "LFO_ZERO", LFO_ZERO },
	{ "LFO_SIN", LFO_SIN },
	{ "LFO_SAW", LFO_SAW },
	{ "LFO_SQUARE", LFO_SQUARE },
	{ "LFO_TRIANGLE", LFO_TRIANGLE },
	{ "LFO_SEQ", LFO_SEQ },

	{ NULL }
};

int
synth_init()
{
	mutex = Mutex();
	mix_init(channels, CHANNELS_MAX);
	return 0;
}

void
synth_done()
{
	MutexDestroy(mutex);
}

int
luaopen_synth(lua_State *L)
{
	int i;
	luaL_newlib(L, synth_lib);
	for (i = 0; constants[i].name; i++) {
		lua_pushstring(L, constants[i].name);
		lua_pushinteger(L, constants[i].val);
		lua_rawset(L, -3);
	}
	return 1;
}

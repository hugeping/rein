#include "external.h"
#include "platform.h"

#include "zvon.h"
#include "zvon_sfx.h"

enum {
    ZV_SAMPLES_LOAD = ZV_END + 1,
    ZV_SAMPLES_RESET,
};

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

static struct sfx_proto *boxes[] = { &empty_box, &sfx_delay, &sfx_dist, &sfx_synth, NULL };

static struct chan_state channels[CHANNELS_MAX];

static int
synth_change(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	int nr = luaL_checkinteger(L, 2);
	const int param = luaL_checkinteger(L, 3);
	const double val = luaL_checknumber(L, 4);
	struct sfx_box *box;
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	if (nr < 0)
		nr = channels[chan].stack_size + nr;
	if (nr < 0 || nr >= channels[chan].stack_size)
		return luaL_error(L, "Wrong stack position");
	box = &channels[chan].stack[nr];
	box->proto->change(box->state, param, val);
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
	if (chan_state->stack_size >= MAX_SFX_BOXES)
		return luaL_error(L, "Maximum boxes reached");
	while (boxes[i] && strcmp(boxes[i]->name, box)) i++;
	if (!boxes[i])
		return luaL_error(L, "Unknown box name: %s", box);
	chan_push(&channels[chan], boxes[i]);
	lua_pushinteger(L, chan_state->stack_size - 1);
	return 1;
}

static int
synth_free(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_drop(&channels[chan]);
	return 0;
}

static int
synth_set(lua_State *L)
{
	struct chan_state *chan_state;
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_state = &channels[chan];
	if (lua_isboolean(L, 2))
		chan_state->is_on = lua_toboolean(L, 2);
	chan_state->vol = luaL_optnumber(L, 3, chan_state->vol);
	chan_state->pan = luaL_optnumber(L, 4, chan_state->pan);
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
			chan_set(&channels[i], 0, 0, 0);
		}
		return 0;
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_drop(&channels[chan]);
	chan_set(&channels[chan], 0, 0, 0);
	return 0;
}

static const luaL_Reg
synth_lib[] = {
	{ "push", synth_push },
	{ "free", synth_free },
	{ "set", synth_set },
	{ "change", synth_change },
	{ "mix", synth_mix },
	{ "stop", synth_stop },
	{ NULL, NULL }
};

static struct {
	const char *name;
	int val;
} constants[] = {
	{ "NOTE_ON", ZV_NOTE_ON },
	{ "NOTE_OFF", ZV_NOTE_OFF },
	{ "VOLUME", ZV_VOLUME },
	{ "TIME", ZV_TIME },
	{ "FEEDBACK", ZV_FEEDBACK },
	{ "GAIN", ZV_GAIN },
	{ "WAVE_TYPE", ZV_WAVE_TYPE },
	{ "WAVE_WIDTH", ZV_WAVE_WIDTH },
	{ "WAVE_OFFSET", ZV_WAVE_OFFSET },
	{ "ATTACK_TIME", ZV_ATTACK_TIME },
	{ "DECAY_TIME", ZV_DECAY_TIME },
	{ "SUSTAIN_LEVEL", ZV_SUSTAIN_LEVEL },
	{ "RELEASE_TIME", ZV_RELEASE_TIME },
	{ "GLIDE_ON", ZV_GLIDE_ON },
	{ "GLIDE_OFF", ZV_GLIDE_OFF },
	{ "LFO_SELECT", ZV_LFO_SELECT },
	{ "LFO_WAVE_TYPE", ZV_LFO_WAVE_TYPE },
	{ "LFO_WAVE_SIGN", ZV_LFO_WAVE_SIGN },
	{ "LFO_FREQ", ZV_LFO_FREQ },
	{ "LFO_LEVEL", ZV_LFO_LEVEL },
	{ "LFO_IS_ONESHOT", ZV_LFO_IS_ONESHOT },
	{ "LFO_TO_FREQ", ZV_LFO_TO_FREQ },
	{ "LFO_TO_WIDTH", ZV_LFO_TO_WIDTH },
	{ "LFO_TO_OFFSET", ZV_LFO_TO_OFFSET },
	{ "SIN", ZV_SIN },
	{ "SQUARE", ZV_SQUARE },
	{ "SAW", ZV_SAW },
	{ "TRIANGLE", ZV_TRIANGLE },
	{ "PWM", ZV_PWM },
	{ "FM", ZV_FM },
	{ NULL, },
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

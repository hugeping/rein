#include "external.h"
#include "platform.h"

#include "zvon.h"
#include "zvon_platform.h"

#define CHANNELS_MAX 32

extern struct box_def test_box;

static struct {
	const char *name;
	struct box_def *def;
} boxes[] = {
	{ "test", &test_box },
	{ NULL, NULL },
};

static struct chan_state channels[CHANNELS_MAX];

static int
synth_change(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const int nr = luaL_checkinteger(L, 2);
	const int param = luaL_checkinteger(L, 3);
	const double val = luaL_checknumber(L, 4);
	const int elem = luaL_optinteger(L, 5, 0);
	struct box_state *box;
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	if (nr >= channels[chan].stack_size)
		return luaL_error(L, "Wrong stack position");
	box = &channels[chan].stack[nr];
	box->change(box->state, param, elem, val);
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
	if (chan_state->stack_size >= MAX_BOXES)
		return luaL_error(L, "Maximum boxes reached");
	while (boxes[i].name && strcmp(boxes[i].name, box)) i++;
	if (!boxes[i].name)
		return luaL_error(L, "Unknown box name");
	chan_push(&channels[chan], boxes[i].def);
	return 0;
}

static int
synth_free(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_free(&channels[chan]);
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
	double floats[SAMPLES_NR*2];
	signed short buf[SAMPLES_NR*2];
	int nr, written, i;
	if (samples > free / 4) /* stereo * sizeof(short) */
		samples = free / 4;
	written = samples;
	while (samples > 0) {
		nr = (samples > SAMPLES_NR)?SAMPLES_NR:samples;
		chan_mix(channels, CHANNELS_MAX, vol, floats, nr);
		for (i = 0; i < nr*2; i ++)
			buf[i] = (signed short)(floats[i] * 16384.0);
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
			chan_free(&channels[i]);
			chan_init(&channels[i]);
		}
		return 0;
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_free(&channels[chan]);
	chan_init(&channels[chan]);
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

int
luaopen_synth(lua_State *L)
{
	int i;
	for (i = 0; i < CHANNELS_MAX; i++)
		chan_init(&channels[i]);
	luaL_newlib(L, synth_lib);
	return 1;
}

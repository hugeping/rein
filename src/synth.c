#include "external.h"
#include "platform.h"

#include "zvon.h"
#include "zvon_platform.h"
#include "zvon_sfx.h"

#define CHANNELS_MAX 32

#define CUSTOM_BUF (1024*2)
struct custom_synth_state {
	double data[CUSTOM_BUF];
	unsigned int head;
	unsigned int tail;
	unsigned int size;
	unsigned int free;
};

static void
custom_synth_init(struct custom_synth_state *s)
{
	s->head = s->tail = 0;
	s->free = s->size = CUSTOM_BUF;
}

static void
custom_synth_change(struct custom_synth_state *s, int param, float size, float *data)
{
	int i;
	unsigned int pos = s->tail;
	if (!s->free)
		return;
	for (i = 0; i < size && s->free; i ++) {
		s->data[pos++ % s->size] = data[i++];
		s->data[pos++ % s->size] = data[i++];
		s->tail = pos % s->size;
		s->free -= 2;
	}
}

static void
custom_synth_next(struct custom_synth_state *s, double *l, double *r)
{
	if (!(s->size - s->free))
		return;
	*l = s->data[s->head ++ % s->size];
	*r = s->data[s->head ++ % s->size];
	s->head %= s->size;
	s->free += 2;
}

static struct sfx_proto custom_box = {
	.name = "custom_stereo",
	.change = (sfx_change_func) custom_synth_change,
	.stereo = (sfx_stereo_func) custom_synth_next,
	.state_size = sizeof(struct custom_synth_state),
	.init = (sfx_init_func) custom_synth_init,
};

static double
empty_mono(struct custom_synth_state *s, double x)
{
	return 0.0;
}

static void
empty_change(void *s, int param, float val, float *data)
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


struct samples_synth_state {
	int stereo;
	double *data;
	unsigned int head;
	unsigned int size;
};

static void
samples_synth_init(struct samples_synth_state *s)
{
	s->head = 0;
}

static void
samples_synth_free(struct samples_synth_state *s)
{
	free(s->data);
}

static void
samples_synth_change(struct samples_synth_state *s, int param, float val, float *data)
{
	s->head = 0;
}

static double
samples_synth_next(struct samples_synth_state *s, double x)
{
	if (s->head >= s->size)
		return x;
	return s->data[s->head++];
}

static void
samples_synth_stereo_next(struct samples_synth_state *s, double *l, double *r)
{
	if (s->head >= s->size)
		return;
	*l = s->data[s->head++];
	*r = s->data[s->head++];
}

static struct sfx_proto samples_box = {
	.name = "samples",
	.change = (sfx_change_func) samples_synth_change,
	.mono = (sfx_mono_func) samples_synth_next,
	.state_size = sizeof(struct samples_synth_state),
	.init = (sfx_init_func) samples_synth_init,
	.free = (sfx_free_func) samples_synth_free,
};

static struct sfx_proto samples_stereo_box = {
	.name = "samples-stereo",
	.change = (sfx_change_func) samples_synth_change,
	.stereo = (sfx_stereo_func) samples_synth_stereo_next,
	.state_size = sizeof(struct samples_synth_state),
	.init = (sfx_init_func) samples_synth_init,
	.free = (sfx_free_func) samples_synth_free,
};

static struct sfx_proto *boxes[] = { &empty_box, &custom_box, &test_square_box, &test_saw_box, NULL };

static struct chan_state channels[CHANNELS_MAX];

static int
synth_change(lua_State *L)
{
	int len = 0, i;
	float f;
	float floats[64];
	const int chan = luaL_checkinteger(L, 1);
	const int nr = luaL_checkinteger(L, 2);
	const int param = luaL_checkinteger(L, 3);
	double val;
	struct sfx_box *box;
	if (lua_istable(L, 4)) {
		len = lua_rawlen(L, 4);
		if (len > 64)
			return luaL_error(L, "To much table");
		for (i = 0; i < len; i++) {
			lua_rawgeti(L, 4, i);
			f = luaL_checknumber(L, -1);
			lua_pop(L, 1);
			floats[i] = f;
		}
		val = len;
	} else {
		val = luaL_checknumber(L, 4);
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	if (nr >= channels[chan].stack_size)
		return luaL_error(L, "Wrong stack position");
	box = &channels[chan].stack[nr];
	box->proto->change(box->state, param, val, (len == 0)?NULL:floats);
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
		return luaL_error(L, "Unknown box name");
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
			chan_free(&channels[i]);
			chan_set(&channels[i], 0, 0, 0);
		}
		return 0;
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	chan_free(&channels[chan]);
	chan_set(&channels[chan], 0, 0, 0);
	return 0;
}

static int
synth_samples(lua_State *L)
{
	int stereo, len, chan, i;
	double f;
	struct samples_synth_state *box;
	chan = luaL_checkinteger(L, 1);
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	if (!lua_istable(L, 2))
		return 0;
	lua_getfield(L, 2, "stereo");
	stereo = lua_toboolean(L, -1);
	lua_pop(L, 1);

	len = lua_rawlen(L, 2);
	chan_free(&channels[chan]);
	box = (struct samples_synth_state*)chan_push(&channels[chan],
		(stereo)?&samples_stereo_box:&samples_box);
	box->data = (double *)calloc(len, sizeof(double));
	if (stereo)
		len &= ~1;
	box->size = len;
	box->stereo = stereo;
	for (i = 1; i <= len; i++) {
		lua_rawgeti(L, 2, i);
		f = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		box->data[i-1] = f;
	}
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
	{ "samples", synth_samples },
	{ NULL, NULL }
};

static struct {
	const char *name;
	int val;
} constants[] = {
	{ "NOTE_ON", ZV_NOTE_ON },
	{ "NOTE_OFF", ZV_NOTE_OFF },
	{ "VOLUME", ZV_VOLUME },
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

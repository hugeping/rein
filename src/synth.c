#include "external.h"
#include "platform.h"

#include "zvon.h"
#include "zvon_sfx.h"

enum {
    ZV_SAMPLES_LOAD = ZV_END + 1,
    ZV_SAMPLES_RESET,
};

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
	for (i = 0; i < size/2 && s->free; i ++) {
		s->data[pos++ % s->size] = data[i++];
		s->data[pos++ % s->size] = data[i++];
		s->tail = pos % s->size;
		s->free -= 2;
	}
}

static void
custom_synth_stereo(struct custom_synth_state *s, double *l, double *r)
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
	.stereo = (sfx_stereo_func) custom_synth_stereo,
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


struct samples_state {
	int stereo;
	float *data;
	unsigned int head;
	unsigned int size;
};

static void
samples_free(struct samples_state *s)
{
	free(s->data);
}

static void
samples_change(struct samples_state *s, int param, float val, float *data)
{
	int i;
	switch (param) {
	case ZV_SAMPLES_LOAD:
		free(s->data);
		s->data = calloc(val, sizeof(float));
		if (!data)
			break;
		for (i = 0; i < (int)val; i ++)
			s->data[i] = data[i];
		s->size = val;
		break;
	case ZV_SAMPLES_RESET:
		s->head = 0;
		break;
	default:
		s->head = 0;
	}
}

static double
samples_mono(struct samples_state *s, double x)
{
	if (s->head >= s->size || !s->data)
		return x;
	return s->data[s->head++];
}

static void
samples_stereo(struct samples_state *s, double *l, double *r)
{
	if (s->head >= s->size || !s->data)
		return;
	*l = s->data[s->head++];
	*r = s->data[s->head++];
}

static struct sfx_proto samples_box = {
	.name = "samples",
	.change = (sfx_change_func) samples_change,
	.mono = (sfx_mono_func) samples_mono,
	.state_size = sizeof(struct samples_state),
	.init = (sfx_init_func) empty_init,
	.free = (sfx_free_func) samples_free,
};

static struct sfx_proto samples_stereo_box = {
	.name = "samples-stereo",
	.change = (sfx_change_func) samples_change,
	.stereo = (sfx_stereo_func) samples_stereo,
	.state_size = sizeof(struct samples_state),
	.init = (sfx_init_func) empty_init,
	.free = (sfx_free_func) samples_free,
};

static struct sfx_proto *boxes[] = { &empty_box, &custom_box,
	&samples_box, &samples_stereo_box, &test_square_box,
	&test_saw_box, &sfx_delay, &sfx_dist, NULL };

static struct chan_state channels[CHANNELS_MAX];

static int
synth_change(lua_State *L)
{
	int len = 0, i;
	float f;
	float floats64[64];
	float *floats = floats64;
	const int chan = luaL_checkinteger(L, 1);
	const int nr = luaL_checkinteger(L, 2);
	const int param = luaL_checkinteger(L, 3);
	double val;
	struct sfx_box *box;
	if (lua_istable(L, 4)) {
		len = lua_rawlen(L, 4);
		if (len > 64)
			floats = calloc(len, sizeof(float));
		if (!floats)
			return luaL_error(L, "To much arg table");
		for (i = 1; i <= len; i++) {
			lua_rawgeti(L, 4, i);
			f = luaL_checknumber(L, -1);
			lua_pop(L, 1);
			floats[i - 1] = f;
		}
		val = len;
	} else {
		val  = luaL_optnumber(L, 4, 0);
	}
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	if (nr >= channels[chan].stack_size)
		return luaL_error(L, "Wrong stack position");
	box = &channels[chan].stack[nr];
	box->proto->change(box->state, param, val, (len == 0)?NULL:floats);
	if (floats != floats64)
		free(floats);
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
	{ "SAMPLES_LOAD", ZV_SAMPLES_LOAD },
	{ "SAMPLES_RESET", ZV_SAMPLES_RESET },
	{ "DRIVE", ZV_DRIVE },
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

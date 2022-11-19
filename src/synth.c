#include "external.h"
#include "platform.h"

#include "zvon.h"
#include "zvon_platform.h"

#define CHANNELS_MAX 32

extern struct box_proto test_box;

#define CUSTOM_BUF (1024*2)
struct custom_synth_state {
	double data[CUSTOM_BUF];
	unsigned int head;
	unsigned int tail;
	unsigned int size;
	unsigned int free;
};

void
custom_synth_init(struct custom_synth_state *s)
{
	s->head = s->tail = 0;
	s->free = s->size = CUSTOM_BUF;
}

void
custom_synth_change(struct custom_synth_state *s, int param, double elem, double val)
{
	unsigned int pos = s->tail;
	if (!s->free)
		return;
	s->data[pos++ % s->size] = val;
	s->data[pos++ % s->size] = elem;
	s->tail = pos % s->size;
	s->free -= 2;
}

void
custom_synth_next(struct custom_synth_state *s, double *l, double *r)
{
	if (!(s->size - s->free))
		return;
	*l = s->data[s->head ++ % s->size];
	*r = s->data[s->head ++ % s->size];
	s->head %= s->size;
	s->free += 2;
}

struct box_proto custom_box = {
	.name = "custom_stereo",
	.change = (box_change_func) custom_synth_change,
	.next_stereo = (box_next_stereo_func) custom_synth_next,
	.state_size = sizeof(struct custom_synth_state),
	.init = (box_init_func) custom_synth_init,
	.deinit = NULL
};

static struct box_proto *boxes[] = { &test_box, &custom_box, NULL };

static struct chan_state channels[CHANNELS_MAX];

static int
synth_change(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const int nr = luaL_checkinteger(L, 2);
	const int param = luaL_checkinteger(L, 3);
	const double val = luaL_checknumber(L, 4);
	const double elem = luaL_optnumber(L, 5, 0);
	struct box_state *box;
	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");
	if (nr >= channels[chan].stack_size)
		return luaL_error(L, "Wrong stack position");
	box = &channels[chan].stack[nr];
	box->proto->change(box->state, param, elem, val);
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
	while (boxes[i] && strcmp(boxes[i]->name, box)) i++;
	if (!boxes[i])
		return luaL_error(L, "Unknown box name");
	chan_push(&channels[chan], boxes[i]);
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
	{ "NOTE_ON", ZVON_NOTE_ON },
	{ "NOTE_OFF", ZVON_NOTE_OFF },
	{ NULL, },
};

int
luaopen_synth(lua_State *L)
{
	int i;
	for (i = 0; i < CHANNELS_MAX; i++)
		chan_init(&channels[i]);
	luaL_newlib(L, synth_lib);
	for (i = 0; constants[i].name; i++) {
		lua_pushstring(L, constants[i].name);
		lua_pushinteger(L, constants[i].val);
		lua_rawset(L, -3);
	}
	return 1;
}

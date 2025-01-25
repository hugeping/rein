#include "external.h"
#include "platform.h"
#include "zvon_sfx.h"
#include "stb_vorbis.h"
#undef L

#define ZV_SAMPLER_LOAD (ZV_END + 1)

#define CHANNELS_MAX 33 /* 1..32 in lua, 0 is always free */

#define WAV_BANK_SIZE 128
static struct {
	void *data;
	int size;
	int ref;
} wav_bank[WAV_BANK_SIZE] = { };

enum {
	ZV_BYPASS = ZV_END + 1,
};

static int mutex;

static int
wav_get(int i, void **data, int *size)
{
	if (i < 0 || i >= WAV_BANK_SIZE)
		return -1;
	MutexLock(mutex);
	if (wav_bank[i].data) {
		if (data)
			*data = wav_bank[i].data;
		if (size)
			*size = wav_bank[i].size;
		wav_bank[i].ref ++;
	} else
		i = -1;
	MutexUnlock(mutex);
	return i;
}

static int
wav_put(int i)
{
	int rc = -1;
	if (i < 0 || i >= WAV_BANK_SIZE)
		return rc;
	MutexLock(mutex);
	if (wav_bank[i].data) {
		wav_bank[i].ref --;
		if (wav_bank[i].ref <= 0) {
			free(wav_bank[i].data);
			wav_bank[i].data = NULL;
			wav_bank[i].size = 0;
		}
		rc = wav_bank[i].ref;
	} else
		rc = -1;
	MutexUnlock(mutex);
	return rc;
}

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

struct sfx_ogg_sampler_state {
	void *data;
	int id;
	int size;
	int pos;
	stb_vorbis *v;
	float **outputs;
	int channels;
	int frames;
	int frame;
};

static void
sfx_ogg_sampler_free(struct sfx_ogg_sampler_state *s)
{
	stb_vorbis_close(s->v);
	wav_put(s->id);
	s->data = NULL;
	s->size = 0;
}

static void
sfx_ogg_sampler_init(struct sfx_ogg_sampler_state *s)
{
	s->id = -1;
}

static void
sfx_ogg_sampler_stereo(struct sfx_ogg_sampler_state *s, double *l, double *r)
{
	if (!s->v || s->pos >= s->size)
		return;
	if (s->frame >= s->frames) {
		s->frames = 0;
		s->frame = 0;
		s->outputs = NULL;
		while (s->pos < s->size && !s->frames) {
			int used = stb_vorbis_decode_frame_pushdata(s->v, s->data + s->pos,
				s->size - s->pos, &s->channels, &s->outputs, &s->frames);
			if (!used) {
				s->pos = s->size;
				break;
			}
			s->pos += used;
		}
	}
	if (!s->outputs)
		return;

	*l = s->outputs[0][s->frame];
	*r = (s->channels > 1)?s->outputs[1][s->frame]:*l;

	s->frame ++;
}

static void
sfx_ogg_sampler_change(struct sfx_ogg_sampler_state *s, int param, int elem, double val)
{
	int used, error;
	switch (param) {
	case ZV_NOTE_OFF:
		s->pos = s->size;
		break;
	case ZV_NOTE_ON:
		if (s->data) {
			stb_vorbis_close(s->v);
			s->v = stb_vorbis_open_pushdata(s->data, s->size, &used, &error, NULL);
			s->pos = used;
			s->frame = 0;
			s->frames = 0;
		}
		break;
	case ZV_SAMPLER_LOAD:
		sfx_ogg_sampler_free(s);
		s->id = wav_get((int)val, &s->data, &s->size);
		s->pos = s->size;
	default:
		break;
	}
}

struct sfx_proto sfx_ogg_sampler = {
	.name = "ogg-sampler",
	.init = (sfx_init_func) sfx_ogg_sampler_init,
	.stereo = (sfx_stereo_func) sfx_ogg_sampler_stereo,
	.change = (sfx_change_func) sfx_ogg_sampler_change,
	.free = (sfx_free_func) sfx_ogg_sampler_free,
	.state_size = sizeof(struct sfx_ogg_sampler_state)
};

static struct sfx_proto *boxes[] = { &empty_box, &bypass_box, &sfx_delay, &sfx_dist, &sfx_synth,
	&sfx_filter, &sfx_ogg_sampler, NULL };

static int
lua_ogg_sampler_status(lua_State *L, void *state)
{
	struct sfx_ogg_sampler_state *s = state;
	lua_pushboolean(L, s->pos < s->size);
	lua_pushinteger(L, s->pos);
	return 2;
}

static struct {
	const char *name;
	int (*status)(lua_State *L, void *state);
} boxes_lua_status[] = {
	{ "ogg-sampler", lua_ogg_sampler_status },
	{ "", NULL },
};

static struct chan_state channels[CHANNELS_MAX];

static int
synth_chan_change(lua_State *L)
{
	const int chan = luaL_checkinteger(L, 1);
	const int param = luaL_checkinteger(L, 2);
	int elem = 0;
	double val;

	if (chan < 0 || chan >= CHANNELS_MAX)
		return luaL_error(L, "Wrong channel number");

	if (lua_isnumber(L, 4)) {
		elem = luaL_checkinteger(L, 3);
		val = luaL_checknumber(L, 4);
	} else
		val = luaL_checknumber(L, 3);
	MutexLock(mutex);
	chan_change(&channels[chan], param, elem, val);
	MutexUnlock(mutex);
	return 0;
}

static int
synth_chan(int chan, int nr)
{
	if (nr < 0)
		nr = channels[chan].stack_size + nr;
	if (nr < 0 || nr >= channels[chan].stack_size)
		return -1;
	return nr;
}

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
	nr = synth_chan(chan, nr);
	if (nr < 0) {
		MutexUnlock(mutex);
		return luaL_error(L, "Wrong stack position");
	}
	box = &channels[chan].stack[nr];
	sfx_box_change(box, param, elem, val);
	MutexUnlock(mutex);
	return 0;
}

static int
synth_load(lua_State *L)
{
	size_t sz = 0;
	const char *data = luaL_checklstring(L, 1, &sz);

	if (!sz)
		return 0;

	MutexLock(mutex);
	for (int i = 0; i < WAV_BANK_SIZE; i++) {
		if (wav_bank[i].data)
			continue;
		wav_bank[i].data = malloc(sz);
		wav_bank[i].size = sz;
		wav_bank[i].ref = 1;
		memcpy(wav_bank[i].data, data, sz);
		MutexUnlock(mutex);
		lua_pushinteger(L, i);
		return 1;
	}
	MutexUnlock(mutex);
	lua_pushboolean(L, 0);
	return 1;
}

static int
synth_unload(lua_State *L)
{
	int i = luaL_checkinteger(L, 1);

	if (i < 0 || i >= WAV_BANK_SIZE)
		return luaL_error(L, "Wrong resource handle");
	lua_pushboolean(L, wav_put(i) <= 0);
	return 1;
}

static int
synth_status(lua_State *L)
{
	int rc = 1;
	const int chan = luaL_checkinteger(L, 1);
	int nr = luaL_checkinteger(L, 2);
	struct sfx_box *box;

	if (chan < 0 || chan >= CHANNELS_MAX)
		return 0;

	MutexLock(mutex);
	nr = synth_chan(chan, nr);
	if (nr < 0) {
		MutexUnlock(mutex);
		return 0;
	}
	box = &channels[chan].stack[nr];
	lua_pushstring(L, box->proto->name);
	for (int i = 0; boxes_lua_status[i].status; i ++) {
		if (!strcmp(boxes_lua_status[i].name, box->proto->name)) {
			rc += boxes_lua_status[i].status(L, box->state);
			break;
		}
	}
	MutexUnlock(mutex);
	return rc;
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
synth_mix_table(lua_State *L)
{
	size_t i;
	int nr;
	int k = 1;
	int samples = luaL_checkinteger(L, 1);
	const double vol = luaL_optnumber(L, 2, 1.0f);
	#define SAMPLES_NR 128
	float floats[SAMPLES_NR*2];
	lua_newtable(L);
	while (samples) {
		nr = (samples > SAMPLES_NR)?SAMPLES_NR:samples;
		mix_process(channels, CHANNELS_MAX, vol, floats, nr);
		for (i = 0; i < nr * 2; i++) {
			lua_pushnumber(L, floats[i]);
			lua_rawseti(L, -2, k ++);
		}
		samples -= nr;
	}
	#undef SAMPLES_NR
	return 1;
}

static int
synth_mix(lua_State *L)
{
	int samples = luaL_checkinteger(L, 1);
	const double vol = luaL_optnumber(L, 2, 1.0f);
	double max_sample = 0.0f;
	double max_chunk;
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
		max_chunk = mix_process(channels, CHANNELS_MAX, vol, floats, nr);
		max_sample = MAX(max_sample, max_chunk);
		for (i = 0; i < nr*2; i ++)
			buf[i] = (signed short)(floats[i] * 32768.0);
		AudioWrite(buf, nr * 4);
		samples -= nr;
	}
	MutexUnlock(mutex);
	#undef SAMPLES_NR
	lua_pushinteger(L, written);
	lua_pushnumber(L, max_sample);
	return 2;
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
	{ "load", synth_load },
	{ "unload", synth_unload },
	{ "chan_change", synth_chan_change },
	{ "status", synth_status },
	{ "mix", synth_mix },
	{ "mix_table", synth_mix_table },
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
	{ "NOTE_ON", ZV_NOTE_ON },
	{ "NOTE_OFF", ZV_NOTE_OFF },
	{ "SET_GLIDE", ZV_SET_GLIDE },
	{ "GLIDE_RATE", ZV_GLIDE_RATE },
	{ "ATTACK", ZV_ATTACK },
	{ "DECAY", ZV_DECAY },
	{ "SUSTAIN", ZV_SUSTAIN },
	{ "RELEASE", ZV_RELEASE },
	{ "SET_SUSTAIN", ZV_SET_SUSTAIN },
	{ "SET_FM", ZV_SET_FM },
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
	/* delay */
	{ "DELAY_TIME", ZV_DELAY_TIME },
	{ "DELAY_LEVEL", ZV_DELAY_LEVEL },
	{ "DELAY_FB", ZV_DELAY_FB },
	/* dist */
	{ "DIST_GAIN", ZV_DIST_GAIN },
	/* filter */
	{ "FILTER_MODE", ZV_FILTER_MODE },
	{ "FILTER_WIDTH", ZV_FILTER_WIDTH },
	{ "FILTER_LP", FILTER_LP },
	{ "FILTER_HP", FILTER_HP },
	/* values */
	{ "OSC_SIN", OSC_SIN },
	{ "OSC_SAW", OSC_SAW },
	{ "OSC_SQUARE", OSC_SQUARE },
	{ "OSC_DSF", OSC_DSF },
	{ "OSC_DSF2", OSC_DSF2 },
	{ "OSC_PWM", OSC_PWM },
	{ "OSC_NOISE", OSC_NOISE },
	{ "OSC_LIN_NOISE", OSC_LIN_NOISE },
	{ "OSC_BAND_NOISE", OSC_BAND_NOISE },
	{ "OSC_LIN_BAND_NOISE", OSC_LIN_BAND_NOISE },
	{ "OSC_FREQ", OSC_FREQ },
	{ "OSC_FMUL", OSC_FMUL },
	{ "OSC_AMP", OSC_AMP },
	{ "OSC_WIDTH", OSC_WIDTH },
	{ "OSC_OFFSET", OSC_OFFSET },
	{ "LFO_ZERO", LFO_ZERO },
	{ "LFO_SIN", LFO_SIN },
	{ "LFO_SAW", LFO_SAW },
	{ "LFO_SQUARE", LFO_SQUARE },
	{ "LFO_TRIANGLE", LFO_TRIANGLE },
	{ "LFO_SEQ", LFO_SEQ },
	{ "LFO_LIN_SEQ", LFO_LIN_SEQ },
	{ "SAMPLER_LOAD", ZV_SAMPLER_LOAD },
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
	for (int i = 0; i < CHANNELS_MAX; i ++)
		chan_drop(&channels[i]);
	for (int i = 0; i < WAV_BANK_SIZE; i ++)
		free(wav_bank[i].data);
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

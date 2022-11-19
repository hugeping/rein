#include <stdlib.h>
#include "zvon_platform.h"
#include "zvon.h"

struct test_synth_state {
	struct phasor_state p;
	double freq;
};

void test_synth_init(struct test_synth_state *s) {
	phasor_init(&s->p);
	s->freq = 0;
}

void test_synth_change(struct test_synth_state *s, int param, double elem, double val) {
	(void) elem;
	if (param == ZVON_NOTE_ON) {
		s->freq = val;
	}
}

double test_synth_next(struct test_synth_state *s, double x) {
	(void) x;
	return square(phasor_next(&s->p, s->freq), 0.5);
}

struct box_proto test_box = {
	.name = "test",
	.change = (box_change_func) test_synth_change,
	.next = (box_next_func) test_synth_next,
	.state_size = sizeof(struct test_synth_state),
	.init = (box_init_func) test_synth_init
};

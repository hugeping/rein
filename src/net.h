#ifndef __NET_H
#define __NET_H

/* the socket userdata made by net.dial; the TLS binding takes the
 * descriptor out of it */
struct lua_sock {
	int fd;
};

#endif

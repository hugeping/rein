local poll = {}
if PLATFORM == 'Windows' or type(jit) ~= 'table' then
  return poll
end

local ffi = require "ffi"
ffi.cdef[[
  struct pollfd {
    int   fd;         /* file descriptor */
    short events;     /* requested events */
    short revents;    /* returned events */
  };
  int fileno(struct FILE* stream);
  int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]
function poll.poll(f)
  local fds = ffi.new("struct pollfd[1]")
  fds[0].fd = ffi.C.fileno(f)
  fds[0].events = 1
  return ffi.C.poll(fds, 1, 200) > 0 and
    bit.band(fds[0].revents, 1)
end

return poll

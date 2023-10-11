local posix = { sighup = function() end }

if PLATFORM == 'Windows' or type(jit) ~= 'table' then
  return posix
end

local ffi = require "ffi"
ffi.cdef[[
  unsigned long signal(int signum, unsigned long);
  struct pollfd {
    int   fd;         /* file descriptor */
    short events;     /* requested events */
    short revents;    /* returned events */
  };
  int fileno(struct FILE* stream);
  int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

function posix.sighup(on)
  ffi.C.signal(13, on and 0 or 1) -- SIGPIPE, SIG_IGN
end

function posix.poll(f)
  local fds = ffi.new("struct pollfd[1]")
  fds[0].fd = ffi.C.fileno(f)
  fds[0].events = 1
  return ffi.C.poll(fds, 1, 200) > 0 and
    bit.band(fds[0].revents, 1)
end

return posix

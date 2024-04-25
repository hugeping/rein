local posix = { sighup = function() end,
    poll = function() return true, true end,
    read = function(f, size) return f:read(size) end,
--    popen = function(cmd, m) return io.popen(cmd, m) end,
}

if PLATFORM == 'Windows' or type(jit) ~= 'table' then
  return posix
end

posix.have_poll = true

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
  int fcntl(int fd, int cmd, int arg);
  size_t read(int fd, void* buf, size_t count);
  void* popen(const char* cmd, const char* mode);
  int pclose(void* stream);
]]

function posix.sighup(on)
  ffi.C.signal(13, on and 0 or 1) -- SIGPIPE, SIG_IGN
end

--[[
function posix.popen(cmd, mode)
	local f = ffi.C.popen(cmd, mode)
	if f then
		ffi.C.fcntl(ffi.C.fileno(f), 4, 2048)
	end
	return f
end

function posix.pclose(f)
	return ffi.C.pclose(f)
end
]]--

function posix.read(f, size)
	local b = ffi.new('uint8_t[?]', size)
	local n = ffi.C.read(ffi.C.fileno(f), b, size)
	if n > 0 then
		return ffi.string(b, n)
	end
	return nil
end

function posix.poll(f)
  local fds = ffi.new("struct pollfd[1]")
  fds[0].fd = ffi.C.fileno(f)
  fds[0].events = 1
  local ret = ffi.C.poll(fds, 1, 1000)
  return ret > 0 and bit.band(fds[0].revents, 1) == 1,
    ret >= 0 and
    bit.band(fds[0].revents, 0x8) ~= 0x8 and
    bit.band(fds[0].revents, 0x11) ~= 0x10
end

return posix

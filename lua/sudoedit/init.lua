---@class M
---@field parent boolean
---@field filename string
---@field filenames table<integer, string> bufnr -> filename
local M = {}

M.parent = false
M.filename = "%F"
M.cmdline = {}

local is_linux = vim.fn.has("linux") == 1
local is_bsd = vim.fn.has("bsd") == 1

--- Create a subarray of arr[start, end)
---@param arr any[]
---@param start_pos integer
---@param end_pos integer
---@return any[]
local function slice(arr, start_pos, end_pos)
  local pos, new = 1, {}
  for i = start_pos, end_pos do
    new[pos] = arr[i]
    pos = pos + 1
  end
  return new
end

--- Get content of /proc/pid/status, nil on unsupported OS
---@param pid integer? nil for current process
---@return string? status
function M.get_proc_status(pid)
  if pid then
    return vim.fn.readfile(string.format("/proc/%i/status", pid))
  end
  if is_linux then
    return vim.fn.readfile("/proc/self/status")
  elseif is_bsd then
    return vim.fn.readfile("/proc/curproc/status")
  end
  return nil
end

--- Get parent pid, nil on unsupported OS
---@param pid integer? nil for current process
---@return integer? ppid
function M.get_ppid(pid)
  local status = M.get_proc_status(pid)

  if not status then
    return nil
  end

  if is_linux then
    return vim.fn.matchlist(status, [[^PPid:\s\+\(\d\+\)]])[2]
  elseif is_bsd then
    return vim.fn.split(status[1], " ")[3]
  end
end

--- Get cmdline of the process, empty on unsupported OS
---@param pid integer? nil for current process
---@return string[] cmdline
function M.get_cmdline(pid)
  if not (is_linux or is_bsd) then
    return {}
  end

  if not pid then
    pid = vim.fn.getpid()
  end

  local cmdline = vim.fn.readfile(string.format("/proc/%i/cmdline", pid))[1]
  return vim.fn.split(cmdline, "\n")
end

--- Helper function for getting cmdline of the parent process
---@return string[]
function M.get_parent_cmdline()
  if M.parent then
    return M.get_cmdline(M.get_ppid())
  end
  return M.get_cmdline(M.get_ppid(M.get_ppid()))
end

--- Check if sudoedit is a (grand)parent of current process
---@return boolean
function M.is_sudoedit()
  local cmdline = M.get_parent_cmdline()
  if next(cmdline) == nil then
    return false
  end
  local cmd = vim.split(cmdline[1], "/")

  if cmd[#cmd] == "sudoedit" then
    M.cmdline = slice(cmdline, 2, #cmdline)
    return true
  elseif cmd[#cmd] == "sudo" and (cmdline[2] == "-e" or cmdline[2] == "--edit") then
    M.cmdline = slice(cmdline, 3, #cmdline)
    return true
  end
  return false
end

--- Detect filetype if nvim is spawned by sudoedit
---@param buf integer The bufnr
function M.detect(buf)
  if not (is_linux or is_bsd) then
    return
  end

  if not M.is_sudoedit() then
    return
  end

  local ft, on_detect = vim.filetype.match({
    -- TODO: check whether bufnr to cmdline mapping is consistent
    filename = M.cmdline[buf],
    buf = buf,
  })

  if ft then
    -- TODO: verify on_detect actually takes effect
    if on_detect then
      on_detect(buf)
    end

    vim.filetype.add({
      filename = {
        [vim.api.nvim_buf_get_name(buf)] = ft,
      },
    })
    return
  end
end

--- Return true if the buffer is being edited by sudoedit
---@param buf integer? The bufnr, empty for current buffer
---@return boolean
function M.detected(buf)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
  end
  return not (M.cmdline[buf] == nil)
end

--- Return the actual filename used by sudoedit, or M.filename
---@param buf integer?
---@return string filename
function M.get_filename(buf)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
  end
  if M.cmdline[buf] then
    return M.cmdline[buf]
  end
  return M.filename
end

function M.setup(opts)
  if opts.parent then -- sudoedit is a parent of nvim instead of grandparent
    M.parent = opts.parent
  end
  if opts.filename then -- default filename when no filetype is detect
    M.filename = opts.filename
  end
end

return M

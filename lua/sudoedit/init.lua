---@class M
---@field parent boolean
---@field filename string
---@field filenames table<integer, string> bufnr -> filename
local M = {}

M.parent = false
M.filename = "%F"
M.filenames = {}

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

--- Check if an array contains a value
---@param arr any[]
---@param val any
---@return boolean
local function has_value(arr, val)
  for _, value in pairs(arr) do
    if value == val then
      return true
    end
  end
  return false
end

--- Get content of /proc/pid/status, nil on unsupported OS
---@param pid integer? nil for current process
---@return string? status
function M.get_proc_status(pid)
  if pid then
    return vim.fn.readfile(string.format("/proc/%i/status", pid))
  else
    if is_linux then
      return vim.fn.readfile("/proc/self/status")
    elseif is_bsd then
      return vim.fn.readfile("/proc/curproc/status")
    end
  end
end

--- Get parent pid, nil on unsupported OS
---@param pid integer? nil for current process
---@return integer? ppid
function M.get_ppid(pid)
  local status = M.get_proc_status(pid)

  if status then
    if is_linux then
      return vim.fn.matchlist(status, [[^PPid:\s\+\(\d\+\)]])[2]
    elseif is_bsd then
      return vim.fn.split(status[1], " ")[3]
    end
  end
end

--- Get cmdline of the process, empty on unsupported OS
---@param pid integer
---@return string[] cmdline
function M.get_cmdline(pid)
  if not (is_linux or is_bsd) then
    return {}
  end

  local cmdline = vim.fn.readfile(string.format("/proc/%i/cmdline", pid))[1]
  return vim.fn.split(cmdline, "\n")
end

--- Check if sudoedit is a (grand)parent of current process
---@return boolean
---@return string[] cmdline The cmdline of sudoedit without the head (sudo --edit, etc.)
function M.is_sudoedit()
  local ppid
  if M.parent then
    ppid = M.get_ppid()
  else
    -- somehow sudoedit is a "grandparent" of current process
    ppid = M.get_ppid(M.get_ppid())
  end

  if not ppid then
    return false, {}
  end

  local cmdline = M.get_cmdline(ppid)

  if cmdline[1] == "sudoedit" then
    return true, slice(cmdline, 2, #cmdline)
  elseif cmdline[1] == "sudo" and (cmdline[2] == "-e" or cmdline[2] == "--edit") then
    return true, slice(cmdline, 3, #cmdline)
  end
  return false, {}
end

--- Detect filetype if nvim is spawned by sudoedit
function M.detect(buf)
  if not (is_linux or is_bsd) then
    return
  end

  local is_sudoedit, cmdline = M.is_sudoedit()

  if not is_sudoedit then
    return
  end

  -- TODO: check whether bufnr to cmdline mapping is consistent
  local filename = cmdline[buf]

  local ft, on_detect = vim.filetype.match({
    filename = filename,
    buf = buf,
  })

  M.filenames[buf] = filename

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
---@param buf any
---@return boolean
function M.detected(buf)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
  end
  return not (M.filenames[buf] == nil)
end

--- Return the actual filename used by sudoedit, or M.filename
---@param buf integer?
---@return string filename
function M.get_filename(buf)
  if not buf then
    buf = vim.api.nvim_get_current_buf()
  end
  if M.filenames[buf] then
    return M.filenames[buf]
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

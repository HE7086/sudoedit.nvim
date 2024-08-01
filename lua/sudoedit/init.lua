local M = {}

M.parent = false

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
  else
    if is_linux then
      return vim.fn.readfile("/proc/self/status")
    elseif is_bsd then
      return vim.fn.readfile("/proc/curproc/status")
    end
  end
end

--- Get parent pid, -1 on unsupported OS
---@param pid integer? nil for current process
---@return integer ppid
function M.get_ppid(pid)
  local status = M.get_proc_status(pid)

  if status then
    if is_linux then
      return vim.fn.matchlist(status, [[^PPid:\s\+\(\d\+\)]])[2]
    elseif is_bsd then
      return vim.fn.split(status[1], " ")[3]
    end
  end
  return -1
end

--- Get cmdline of the process, empty on unsupported OS
---@param pid integer
---@return string[] cmdline
function M.get_cmdline(pid)
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

  local cmdline = M.get_cmdline(ppid)

  if cmdline[1] == "sudoedit" then
    return true, slice(cmdline, 2, #cmdline)
  elseif cmdline[1] == "sudo" and (cmdline[2] == "-e" or cmdline[2] == "--edit") then
    return true, slice(cmdline, 3, #cmdline)
  end
  return false, {}
end

--- Detect filetype if nvim is spawned by sudoedit
function M.detect()
  if not (is_linux or is_bsd) then
    return
  end

  local is_sudoedit, cmdline = M.is_sudoedit()

  if not is_sudoedit then
    return
  end

  for _, filename in pairs(cmdline) do
    local buf = vim.api.nvim_get_current_buf()

    -- Taken from /usr/share/nvim/runtime/filetype.lua --
    local ft, on_detect = vim.filetype.match({
      filename = filename,
      buf = buf,
    })

    if ft then
      if on_detect then
        on_detect(buf)
      end

      vim.api.nvim_buf_call(buf, function()
        vim.api.nvim_cmd({ cmd = "setf", args = { ft } }, {})
      end)
    end
    -- Taken from /usr/share/nvim/runtime/filetype.lua --
  end
end

function M.setup(opts)
  if opts.parent then -- sudoedit is a parent of nvim instead of grandparent
    M.parent = opts.parent
  end
end

return M

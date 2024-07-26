local M = {}

M.parent = false
M.cmdline = {}

local is_linux = vim.fn.has("linux") == 1
local is_bsd = vim.fn.has("bsd") == 1

local function slice(arr, start, end_pos)
  local pos, new = 1, {}
  for i = start, end_pos do
    new[pos] = arr[i]
    pos = pos + 1
  end
  return new
end

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

function M.get_ppid(pid)
  local status = M.get_proc_status(pid)

  if is_linux then
    return vim.fn.matchlist(status, [[^PPid:\s\+\(\d\+\)]])[2]
  elseif is_bsd then
    return vim.fn.split(status[1], " ")[3]
  end
end

function M.get_cmdline(pid)
  local ppid = M.get_ppid(pid)
  local cmdline = vim.fn.readfile(string.format("/proc/%i/cmdline", ppid))[1]
  return vim.fn.split(cmdline, "\n")
end

function M.is_sudoedit()
  if M.parent then
    M.cmdline = M.get_cmdline()
  else
    -- somehow sudoedit is a "grandparent" of current process
    local ppid = M.get_ppid()
    M.cmdline = M.get_cmdline(ppid)
  end

  if M.cmdline[1] == "sudoedit" then
    M.cmdline = slice(M.cmdline, 2, #M.cmdline)
    return true
  elseif M.cmdline[1] == "sudo" and (M.cmdline[2] == "-e" or M.cmdline[2] == "--edit") then
    M.cmdline = slice(M.cmdline, 3, #M.cmdline)
    return true
  end
  return false
end

function M.detect()
  if (is_linux or is_bsd) and M.is_sudoedit() then

    for _, filename in pairs(M.cmdline) do
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
end

function M.setup(opts)
  if opts.parent then -- sudoedit is a parent of nvim instead of grandparent
    M.parent = opts.parent
  end
end

return M

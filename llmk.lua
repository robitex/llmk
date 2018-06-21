#!/usr/bin/env texlua

--
-- llmk.lua
--

-- program information
prog_name = 'llmk'
version = '0.0.0'
author = 'Takuto ASAKURA (wtsnjp)'

-- option flags (default)
debug = {
  ['version'] = false,
  ['config'] = false,
}
verbosity_level = 0

-- config table (default)
config = {
  ['latex'] = 'lualatex',
  ['max_repeat'] = 3,
}

----------------------------------------

-- library
require 'lfs'

-- global functions
function err_print(err_type, msg)
  if (verbosity_level > 0) or (err_type == 'error') then
    io.stderr:write(prog_name .. ' ' .. err_type .. ': ' .. msg .. '\n')
  end
end

function dbg_print(dbg_type, msg)
  if debug[dbg_type] then
    io.stderr:write(prog_name .. ' debug-' .. dbg_type .. ': ' .. msg .. '\n')
  end
end

----------------------------------------

do
  local function parse_toml(toml)
    -- basic local variables
    local ws = '[\009\032]'
    local nl = '[\10\13\10]'

    local buffer = ''
    local cursor = 1

    local res = {}
    local obj = res

    -- basic local functions
    local function char(n)
      n = n or 0
      return toml:sub(cursor + n, cursor + n)
    end

    local function step(n)
      n = n or 1
      cursor = cursor + n
    end

    local function skip_ws()
      while(char():match(ws)) do
        step()
      end
    end

    local function trim(str)
      return str:gsub('^%s*(.-)%s*$', '%1')
    end

    local function bounds()
      return cursor <= toml:len()
    end

    -- parse functions for each type
    local function parse_string()
      -- TODO: multiline
      local del = char() -- ' or "
      local str = ''

      -- skip the quotes
      step()

      while(bounds()) do
        -- end of string
        if char() == del then
          step()
          break
        end

        if char():match(nl) then
          err_print('error', 'Single-line string cannot contain line break')
        end

        -- TODO: process escape characters
        str = str .. char()
        step()
      end

      return str
    end

    local function parse_number()
      -- TODO: exp, date
      local num = ''

      while(bounds()) do
        if char():match('[%+%-%.eE_0-9]') then
          if char() ~= '_' then
            num = num .. char()
          end
        elseif char():match(ws) or char() == '#' or char():match(nl) then
          break
        else
          err_print('Invalid number')
        end
        step()
      end

      return tonumber(num)
    end

    -- judge the type and get the value
    local function get_value()
      if (char() == '"' or char() == "'") then
        return parse_string()
      elseif char():match('[%+%-0-9]') then
        return parse_number()
      -- TODO: array, inline table, boolean
      end
    end

    -- main loop of parser
    while(cursor <= toml:len()) do
      -- ignore comments and whitespace
      if char() == '#' then
        while(not char():match(nl)) do
          step()
        end
      end

      if char():match(nl) then
        -- do nothing; skip
      end

      if char() == '=' then
        step()
        skip_ws()

        -- prepare the key
        key = trim(buffer)
        buffer = ''

        if key == '' then
          err_print('error', 'Empty key name')
        end

        local value = get_value()
        if value then
          -- duplicate keys are not allowed
          if obj[key] then
            err_print('error', 'Cannot redefine key "' .. key .. '"')
          end
          obj[key] = value
        end

        -- skip whitespace and comments
        skip_ws()
        if char() == '#' then
          while(bounds() and not char():match(nl)) do
            step()
          end
        end

        -- if garbage remains on this line, raise an error
        if not char():match(nl) and cursor < toml:len() then
          err_print('error', 'Invalid primitive')
        end

      --elseif char() == '[' then
        -- TODO: arrays

      --elseif (char() == '"' or char() == "'") then
        -- TODO: quoted keys
      end

      -- put the char to the buffer and proceed
      buffer = buffer .. (char():match(nl) and '' or char())
      step()
    end

    return res
  end

  local function get_toml(fn)
    local toml = ''
    local toml_area = false

    f = io.open(fn)

    for l in f:lines() do
      if string.match(l, '^%s*%%%s*%+%+%++%s*$') then
        toml_area = not toml_area
      else
        if toml_area then
          toml = toml .. string.match(l, '^%s*%%%s*(.*)%s*$') .. '\n'
        end
      end
    end

    f:close()

    return toml
  end

  local function update_config(tab)
    for k, v in pairs(tab) do
      config[k] = v
    end
  end

  function fetch_config(fns)
    local fn = fns[1]

    local toml = get_toml(fn)
    local new_config = parse_toml(toml)
    update_config(new_config)
  end
end

----------------------------------------

do
  local function run_latex(fn)
    local tex_cmd = config.latex .. ' ' .. fn
    err_print('info', 'TeX command: "' .. tex_cmd .. '"')
    os.execute(tex_cmd)
  end

  function make(fns)
    fn = fns[1]
    run_latex(fn)
  end
end

----------------------------------------

do
  -- exit codes
  local exit_ok = 0
  local exit_error = 1
  local exit_usage = 2

  -- help texts
  local usage_text = [[
Usage: llmk[.lua] [OPTION...] [FILE...]

Options:
  -h, --help            Print this help message.
  -V, --version         Print the version number.

Please report bugs to <tkt.asakura@gmail.com>.
]]

  local version_text = [[
%s %s

Copyright 2018 %s.
License: The MIT License <https://opensource.org/licenses/mit-license.php>.
This is free software: you are free to change and redistribute it.
]]

  local error_msg = "ERROR"

  -- show uasage / help
  local function show_usage(out, text)
    out:write(usage_text:format(text))
  end

  -- execution functions
  local function read_options()
    if #arg == 0 then
      show_usage(io.stderr, '')
      os.exit(exit_usage)
    end

    local curr_arg
    local action = false

    -- modified Alternative Get Opt
    -- cf. http://lua-users.org/wiki/AlternativeGetOpt
    local function getopt(arg, options)
      local tmp
      local tab = {}
      local saved_arg = { table.unpack(arg) }
      for k, v in ipairs(saved_arg) do
        if string.sub(v, 1, 2) == "--" then
          table.remove(arg, 1)
          local x = string.find(v, "=", 1, true)
          if x then tab[string.sub(v, 3, x-1)] = string.sub(v, x+1)
          else   tab[string.sub(v, 3)] = true
          end
        elseif string.sub(v, 1, 1) == "-" then
          table.remove(arg, 1)
          local y = 2
          local l = string.len(v)
          local jopt
          while (y <= l) do
            jopt = string.sub(v, y, y)
            if string.find(options, jopt, 1, true) then
              if y < l then
                tmp = string.sub(v, y+1)
                y = l
              else
                table.remove(arg, 1)
                tmp = saved_arg[k + 1]
              end
              if string.match(tmp, '^%-') then
                tab[jopt] = false
              else
                tab[jopt] = tmp
              end
            else
              tab[jopt] = true
            end
            y = y + 1
          end
        end
      end
      return tab
    end

    opts = getopt(arg, 'd')
    for k, v in pairs(opts) do
      if #k == 1 then
        curr_arg = '-' .. k
      else
        curr_arg = '--' .. k
      end

      -- action
      if (curr_arg == '-h') or (curr_arg == '--help') then
        action = 'help'
      elseif (curr_arg == '-V') or (curr_arg == '--version') then
        action = 'version'
      else
        err_print('error', 'unknown option: ' .. curr_arg)
        err_print('error', error_msg)
        os.exit(exit_error)
      end
    end

    return action
  end

  local function do_action()
    if action == 'help' then
      show_usage(io.stdout, action_text)
    elseif action == 'version' then
      io.stdout:write(version_text:format(prog_name, version, author))
    end
  end

  function main()
    action = read_options()

    if action then
      do_action()
      os.exit(exit_ok)
    end

    fetch_config(arg)
    make(arg)
    os.exit(exit_ok)
  end
end

----------------------------------------

main()

-- EOF

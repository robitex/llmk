#!/usr/bin/env texlua

-- The Light LaTeX Make tool
-- This is the file `llmk.lua'.
--
-- Copyright 2018 Takuto ASAKURA (wtsnjp)
--   GitHub:   https://github.com/wtsnjp
--   Twitter:  @wtsnjp
--
-- This sofware is distributed under the MIT License.
-- for more information, please refer to LICENCE file

-- program information
local llmk_info = {
  _VERSION     = 'llmk v0.1',
  _NAME        = 'llmk',
  _AUTHOR      = 'Takuto ASAKURA (wtsnjp)',
  _DESCRIPTION = 'The Light LaTeX Make tool',
  _URL         = 'https://github.com/wtsnjp/llmk',
  _LICENSE     = 'MIT LICENSE (https://opensource.org/licenses/mit-license)',
}

----------------------------------------

-- module 'getopt' : read options from the command line
local GetOpt = {}

-- modified Alternative Get Opt
-- cf. http://lua-users.org/wiki/AlternativeGetOpt
function GetOpt.from_arg(arg, options)
  local tmp
  local tab = {}
  local saved_arg = {table.unpack(arg)}
  for k, v in ipairs(saved_arg) do
    if string.sub(v, 1, 2) == '--' then
      table.remove(arg, 1)
      local x = string.find(v, '=', 1, true)
        if x then
          table.insert(tab, {string.sub(v, 3, x-1), string.sub(v, x+1)})
        else
          table.insert(tab, {string.sub(v, 3), true})
        end
    elseif string.sub(v, 1, 1) == '-' then
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
            table.insert(tab, {jopt, false})
          else
            table.insert(tab, {jopt, tmp})
          end
        else
          table.insert(tab, {jopt, true})
        end
        y = y + 1
      end
    end
  end
  return tab
end

-- library references
local lfs = require 'lfs'
local md5 = require 'md5'

llmk_toml = 'llmk.toml'
start_time = os.time()

-- option flags (default)
debug = {
  config = false,
  parser = false,
  run = false,
  fdb = false,
  programs = false,
}
verbosity_level = 1

-- exit codes
exit_ok = 0
exit_error = 1
exit_parser = 2
exit_failure = 3

----------------------------------------

-- global functions
function err_print(err_type, msg)
  if (verbosity_level > 1) or (err_type == 'error') then
    io.stderr:write(llmk_info._NAME .. ' ' .. err_type .. ': ' .. msg .. '\n')
  end
end

function dbg_print(dbg_type, msg)
  if debug[dbg_type] then
    io.stderr:write(llmk_info._NAME .. ' debug-' .. dbg_type .. ': ' .. msg .. '\n')
  end
end

function dbg_print_table(dbg_type, table)
  if not debug[dbg_type] then return end

  local indent = 2

  local function helper(tab, ind)
    for k, v in pairs(tab) do
      if type(v) == 'table' then
        dbg_print(dbg_type, string.rep(' ', ind) .. k .. ':')
        helper(v, ind + indent)
      elseif type(v) == 'string' then
        dbg_print(dbg_type, string.rep(' ', ind) .. k .. ': "' .. (v) .. '"')
      else -- number,  boolean, etc.
        dbg_print(dbg_type, string.rep(' ', ind) .. k .. ': ' .. tostring(v))
      end
    end
  end

  helper(table, indent)
end

function init_config()
  -- basic config table
  config = {
    latex = 'lualatex',
    bibtex = 'bibtex',
    makeindex = 'makeindex',
    dvipdf = 'dvipdfmx',
    dvips = 'dvips',
    ps2pdf = 'ps2pdf',
    sequence = {'latex', 'bibtex', 'makeindex', 'dvipdf'},
    max_repeat = 3,
  }

  -- program presets
  config.programs = {
    latex = {
      opts = {
        '-interaction=nonstopmode',
        '-file-line-error',
        '-synctex=1',
      },
      auxiliary = '%B.aux',
    },
    bibtex = {
      target = '%B.bib',
      args = '%B', -- "%B.bib" will result in an error
      postprocess = 'latex',
    },
    makeindex = {
      target = '%B.idx',
      force = false,
      postprocess = 'latex',
    },
    dvipdf = {
      target = '%B.dvi',
      force = false,
    },
    dvips = {
      target = '%B.dvi',
    },
    ps2pdf = {
      target = '%B.ps',
    },
  }
end

----------------------------------------

do
  local function parser_err(msg)
    err_print('error', 'parser: ' .. msg)
    os.exit(exit_parser)
  end

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
          parser_err('Single-line string cannot contain line break')
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
          parser_err('Invalid number')
        end
        step()
      end

      return tonumber(num)
    end

    local parse_array, get_value

    function parse_array()
      step()
      skip_ws()

      local a_type
      local array = {}

      while(bounds()) do
        if char() == ']' then
          break
        elseif char():match(nl) then
          step()
          skip_ws()
        elseif char() == '#' then
          while(bounds() and not char():match(nl)) do
            step()
          end
        else
          local v = get_value()
          if not v then break end

          if a_type == nil then
            a_type = type(v)
          elseif a_type ~= type(v) then
            parser_err('Mixed types in array')
          end

          array = array or {}
          table.insert(array, v)

          if char() == ',' then
            step()
          end
          skip_ws()
        end
      end
      step()

      return array
    end

    function parse_boolean()
      local bool

      if toml:sub(cursor, cursor + 3) == 'true' then
        step(4)
        bool = true
      elseif toml:sub(cursor, cursor + 4) == 'false' then
        step(5)
        bool = false
      else
        parser_err('Invalid primitive')
      end

      skip_ws()
      if char() == '#' then
        while(not char():match(nl)) do
          step()
        end
      end

      return bool
    end

    -- judge the type and get the value
    function get_value()
      if (char() == '"' or char() == "'") then
        return parse_string()
      elseif char():match('[%+%-0-9]') then
        return parse_number()
      elseif char() == '[' then
        return parse_array()
      -- TODO: array of table, inline table
      else
        return parse_boolean()
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
          parser_err('Empty key name')
        end

        local value = get_value()
        if value then
          -- duplicate keys are not allowed
          if obj[key] then
            parser_err('Cannot redefine key "' .. key .. '"')
          end
          obj[key] = value
          --dbg_print('parser', 'Entry "' .. key .. ' = ' .. value .. '"')
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
          parser_err('Invalid primitive')
        end

      elseif char() == '[' then
        buffer = ''
        step()
        local table_array = false

        if char() == '[' then
          table_array = true
          step()
        end

        obj = res

        local function process_key(is_last)
          is_last = is_last or false
          buffer = trim(buffer)

          if buffer == '' then
            parser_err('Empty table name')
          end

          if is_last and obj[buffer] and not table_array and #obj[buffer] > 0 then
            parser_err('Cannot redefine tabel')
          end

          if table_array then
            if obj[buffer] then
              obj = obj[buffer]
              if is_last then
                table.insert(obj, {})
              end
              obj = obj[#obj]
            else
              obj[buffer] = {}
              obj = obj[buffer]
              if is_last then
                table.insert(obj, {})
                obj = obj[1]
              end
            end
          else
            obj[buffer] = obj[buffer] or {}
            obj = obj[buffer]
          end
        end

        while(bounds()) do
          if char() == ']' then
            if table_array then
              if char(1) ~= ']' then
                parser_err('Mismatching brackets')
              else
                step()
              end
            end
            step()

            process_key(true)
            buffer = ''
            break
          --elseif char() == '"' or char() == "'" then
            -- TODO: quoted keys
          elseif char() == '.' then
            step()
            process_key()
            buffer = ''
          else
            buffer = buffer .. char()
            step()
          end
        end

        buffer = ''
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
    local toml_field = false
    local toml_source = fn

    local f = io.open(toml_source)

    dbg_print('config', 'Fetching TOML from the file "' .. toml_source .. '".')

    local first_line = true
    local shebang

    for l in f:lines() do
      -- 1. llmk-style TOML field
      if string.match(l, '^%s*%%%s*%+%+%++%s*$') then
        -- NOTE: only topmost field is valid
        if not toml_field then toml_field = true
        else break end
      else
        if toml_field then
          toml = toml .. string.match(l, '^%s*%%%s*(.*)%s*$') .. '\n'
        end
      end

      -- 2. shebang
      if first_line then
        first_line = false
        shebang = string.match(l, '^%s*%%#!%s*(.*)%s*$')
      end
    end

    f:close()

    -- shebang to TOML
    if toml == '' and shebang then
      toml = 'latex = "' .. shebang .. '"\n'
    end

    return toml
  end

  -- copy command name from top level
  local function fetch_from_top_level(name)
    if config.programs[name] then
      if not config.programs[name].command and config[name] then
        config.programs[name].command = config[name]
      end
    end
  end

  local function update_config(tab)
    -- merge the table from TOML
    local function merge_table(tab1, tab2)
      for k, v in pairs(tab2) do
        if type(tab1[k]) == 'table' then
          tab1[k] = merge_table(tab1[k], v)
        else
          tab1[k] = v
        end
      end
      return tab1
    end
    config = merge_table(config, tab)

    -- set essential program names from top-level
    local prg_names = {'latex', 'bibtex', 'makeindex', 'dvipdf', 'dvips', 'ps2pdf'}
    for _, name in pairs(prg_names) do
      fetch_from_top_level(name)
    end

    -- show config table (for debug)
    dbg_print('config', 'The final config table is as follows:')
    dbg_print_table('config', config)
  end

  function fetch_config_from_latex_source(fn)
    local toml = get_toml(fn)
    if toml == '' then
      err_print('warning',
        'Neither TOML field nor shebang is found in "' .. fn ..
        '"; using default config.')
    end

    update_config(parse_toml(toml))
  end

  function fetch_config_from_llmk_toml()
    local f = io.open(llmk_toml)
    if f ~= nil then
      local toml = f:read('*all')
      update_config(parse_toml(toml))
      f:close()
    else
      err_print('error', 'No target specified and no ' .. llmk_toml .. ' found.')
      os.exit(exit_error)
    end
  end
end

----------------------------------------

do
  local function table_copy(org)
    local org_type = type(org)
    local copy
    if org_type == 'table' then
      copy = {}
      for org_key, org_value in next, org, nil do
        copy[table_copy(org_key)] = table_copy(org_value)
      end
      setmetatable(copy, table_copy(getmetatable(org)))
    else -- number, string, boolean, etc.
        copy = org
    end
    return copy
  end

  local function replace_specifiers(str, source, target)
    local tmp = '/' .. source
    local basename = tmp:match('^.*/(.*)%..*$')

    str = str:gsub('%%S', source)
    str = str:gsub('%%T', target)

    if basename then
      str = str:gsub('%%B', basename)
    else
      str = str:gsub('%%B', source)
    end

    return str
  end

  local function setup_programs(fn)
    --[[Setup the programs table for each sequence.

    Collecting tables of only related programs, which appears in the
    `config.sequence` or `prog.postprocess`, and replace all specifiers.

    Args:
      fn (str): the input FILE name

    Returns:
      table of program tables
    ]]
    local prog_names = {}
    local new_programs = {}

    -- collect related programs
    local function add_prog_name(name)
      -- is the program known?
      if not config.programs[name] then
        err_print('error', 'Unknown program "' .. name .. '" is in the sequence.')
        os.exit(exit_error)
      end

      -- if not new, no addition
      for _, c in pairs(prog_names) do
        if c == name then
          return
        end
      end

      -- if new, add it!
      prog_names[#prog_names + 1] = name
    end

    for _, name in pairs(config.sequence) do
      -- add the program name
      add_prog_name(name)

      -- add postprocess program if any
      local postprocess = config.programs[name].postprocess
      if postprocess then
        add_prog_name(postprocess)
      end
    end

    -- setup the programs
    for _, name in ipairs(prog_names) do
      local prog = table_copy(config.programs[name])

      -- setup the `prog.target`
      local cur_target

      if not prog.target then
        -- the default value of `prog.target` is `fn`
        cur_target = fn
      else
        -- here, %T should be replaced by `fn`
        cur_target = replace_specifiers(prog.target, fn, fn)
      end

      prog.target = cur_target

      -- setup the `prog.opts`
      if prog.opts then -- `prog.opts` is optional
        -- normalize to a table
        if type(prog.opts) ~= 'table' then
          prog.opts = {prog.opts}
        end

        -- replace specifiers as usual
        for idx, opt in ipairs(prog.opts) do
          prog.opts[idx] = replace_specifiers(opt, fn, cur_target)
        end
      end

      -- setup the `prog.args`
      if not prog.args then
        -- the default value of `prog.args` is [`cur_target`]
        prog.args = {cur_target}
      else
        -- normalize to a table
        if type(prog.args) ~= 'table' then
          prog.args = {prog.args}
        end

        -- replace specifiers as usual
        for idx, arg in ipairs(prog.args) do
          prog.args[idx] = replace_specifiers(arg, fn, cur_target)
        end
      end

      -- setup the `prog.auxiliary`
      if prog.auxiliary then -- `prog.auxiliary` is optional
        -- replace specifiers as usual
        prog.auxiliary = replace_specifiers(prog.auxiliary, fn, cur_target)
      end

      -- setup the `prog.force`
      if prog.force == nil then
        -- the default value of `prog.force` is true
        prog.force = true
      end

      -- register the program
      new_programs[name] = prog
    end

    return new_programs
  end

  local function file_mtime(path)
    return lfs.attributes(path, 'modification')
  end

  local function file_size(path)
    return lfs.attributes(path, 'size')
  end

  local function file_md5sum(path)
    local f = assert(io.open(path, 'rb'))
    local content = f:read('*a')
    f:close()
    return md5.sumhexa(content)
  end

  local function file_status(path)
    return {
      mtime = file_mtime(path),
      size = file_size(path),
      md5sum = file_md5sum(path),
    }
  end

  local function init_file_database(programs, fn)
    -- the template
    local fdb = {
      targets = {},
      auxiliary = {},
    }

    -- investigate current status
    for _, v in ipairs(config.sequence) do
      -- names
      local cur_target = programs[v].target
      local cur_aux = programs[v].auxiliary

      -- target
      if lfs.isfile(cur_target) and not fdb.targets[cur_target] then
        fdb.targets[cur_target] = file_status(cur_target)
      end

      -- auxiliary
      if cur_aux then -- `prog.auxiliary` is optional
        if lfs.isfile(cur_aux) and not fdb.auxiliary[cur_aux] then
          fdb.auxiliary[cur_aux] = file_status(cur_aux)
        end
      end
    end

    return fdb
  end

  local function construct_cmd(prog, fn, target)
    -- construct the option
    local cmd_opt = ''

    if prog.opts then
      -- construct each option
      for _, opt in ipairs(prog.opts) do
        if #opt > 0 then
          cmd_opt = cmd_opt .. ' ' .. opt
        end
      end
    end

    -- construct the argument
    local cmd_arg = ''

    -- construct each argument
    for _, arg in ipairs(prog.args) do
      cmd_arg = cmd_arg .. ' "' .. arg .. '"'
    end

    -- whole command
    return prog.command .. cmd_opt .. cmd_arg
  end

  local function check_rerun(prog, fdb)
    dbg_print('run', 'Checking the neccessity of rerun.')

    local aux = prog.auxiliary
    local old_aux_exist = false
    local old_status

    -- if aux file does not exist, no chance of rerun
    if not aux then
      dbg_print('run', 'No auxiliary file specified.')
      return false, fdb
    end

    -- if aux file does not exist, no chance of rerun
    if not lfs.isfile(aux) then
      dbg_print('run', 'The auxiliary file "' .. aux .. '" does not exist.')
      return false, fdb
    end

    -- copy old information and update fdb
    if fdb.auxiliary[aux] then
      old_aux_exist = true
      old_status = table_copy(fdb.auxiliary[aux])
    end
    local aux_status = file_status(aux)
    fdb.auxiliary[aux] = aux_status

    -- if aux file is not new, no rerun
    local new = aux_status.mtime >= start_time
    if not new and old_aux_exist then
      new = aux_status.mtime > old_status.mtime
    end

    if not new then
      dbg_print('run', 'No rerun because the aux file is not new.')
      return false, fdb
    end

    -- if aux file is empty (or almost), no rerun
    if aux_status.size < 9 then -- aux file contains "\\relax \n" by default
      dbg_print('run', 'No rerun because the aux file is (almost) empty.')
      return false, fdb
    end

    -- if new aux is not different from older one, no rerun
    if old_aux_exist then
      if aux_status.md5sum == old_status.md5sum then
        dbg_print('run', 'No rerun because the aux file has not been changed.')
        return false, fdb
      end
    end

    -- ok, then try rerun
    dbg_print('run', 'Try to rerun!')
    return true, fdb
  end

  local function run_program(prog, fn, fdb)
    -- does command specified?
    if #prog.command < 1 then
      dbg_print('run',
        'Skiping "' .. prog.command .. '" because command does not exist.')
      return false
    end

    -- does target exist?
    if not lfs.isfile(prog.target) then
      dbg_print('run',
        'Skiping "' .. prog.command .. '" because target (' ..
        prog.target .. ') does not exist.')
      return false
    end

    -- is the target modified?
    if not prog.force and file_mtime(prog.target) < start_time then
      dbg_print('run',
        'Skiping "' .. prog.command .. '" because target (' ..
        prog.target .. ') is not updated.')
      return false
    end

    local cmd = construct_cmd(prog, fn, prog.target)
    err_print('info', 'Running command: ' .. cmd)
    local status = os.execute(cmd)

    if status > 0 then
      err_print('error',
        'Fail running '.. cmd .. ' (exit code: ' .. status .. ')')
      os.exit(exit_failure)
    end

    return true
  end

  local function process_program(programs, name, fn, fdb)
    local prog = programs[name]
    local should_rerun

    -- check prog.command
    -- TODO: move this to pre-checking process
    if type(prog.command) ~= 'string' then
      err_print('error', 'Command name for "' .. name .. '" is not detected.')
      os.exit(exit_error)
    end

    -- TODO: move this to pre-checking process
    if type(prog.target) ~= 'string' then
      err_print('error', 'Target for "' .. name .. '" is not valid.')
      os.exit(exit_error)
    end

    -- execute the command
    local run = false
    local exe_count = 0
    while true do
      exe_count = exe_count + 1
      run = run_program(prog, fn, fdb)

      -- if the run is skipped, break immediately
      if not run then break end

      -- if not neccesarry to rerun or reached to max_repeat, break the loop
      should_rerun, fdb = check_rerun(prog, fdb)
      if not ((exe_count < config.max_repeat) and should_rerun) then
        break
      end
    end

    -- go to the postprocess process
    if prog.postprocess and run then
      dbg_print('run', 'Going to postprocess "' .. prog.postprocess .. '".')
      process_program(programs, prog.postprocess, fn, fdb)
    end
  end

  local function run_sequence(fn)
    err_print('info', 'Beginning a sequence for "' .. fn .. '".')

    -- setup the programs table
    local programs = setup_programs(fn)
    dbg_print('programs', 'Current programs table:')
    dbg_print_table('programs', programs)

    -- create a file database
    local fdb = init_file_database(programs, fn)
    dbg_print('fdb', 'The initial file database is as follows:')
    dbg_print_table('fdb', fdb)

    for _, name in ipairs(config.sequence) do
      dbg_print('run', 'Preparing for program "' .. name .. '".')
      process_program(programs, name, fn, fdb)
    end
  end

  -- return the filename if exits, even if the ".tex" extension is omitted
  -- otherwise return nil
  local function check_filename(fn)
    if lfs.isfile(fn) then
      return fn -- ok
    end

    local ext = fn:match('%.(.-)$')
    if ext ~= nil then
      return nil
    end

    local new_fn = fn .. '.tex'
    if lfs.isfile(new_fn) then
      return new_fn
    else
      return nil
    end
  end

  function make(fns)
    if #fns > 0 then
      for _, fn in ipairs(fns) do
        init_config()
        local checked_fn = check_filename(fn)
        if checked_fn then
          fetch_config_from_latex_source(checked_fn)
          run_sequence(checked_fn)
        else
          err_print('error', 'No source file found for "' .. fn .. '".')
          os.exit(exit_error)
        end
      end
    else
      init_config()
      fetch_config_from_llmk_toml()
      if type(config.source) == 'string' then
        run_sequence(config.source)
      elseif type(config.source) == 'table' then
        for _, fn in ipairs(config.source) do
          run_sequence(fn)
        end
      else
        err_print('error', 'No source detected.')
        os.exit(exit_error)
      end
    end
  end
end

----------------------------------------

do
  -- help texts
  local help_text = [[
Usage: llmk[.lua] [OPTION...] [FILE...]

Options:
  -h, --help            Print this help message.
  -V, --version         Print the version number.

  -q, --quiet           Suppress warnings and most error messages.
  -v, --verbose         Print additional information.
  -D, --debug           Activate all debug output (equal to "--debug=all").
  -d CAT, --debug=CAT   Activate debug output restricted to CAT.

Please report bugs to <tkt.asakura@gmail.com>.
]]

  -- execution functions
  local function read_options()
    local curr_arg
    local action = false

    local opts = GetOpt.from_arg(arg, 'd')
    for _, tp in pairs(opts) do
      local k, v = tp[1], tp[2]
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
      -- debug
      elseif (curr_arg == '-D') or
        (curr_arg == '--debug' and (v == 'all' or v == true)) then
        for c, _ in pairs(debug) do
          debug[c] = true
        end
      elseif (curr_arg == '-d') or (curr_arg == '--debug') then
        if debug[v] == nil then
          err_print('warning', 'unknown debug category: ' .. v)
        else
          debug[v] = true
        end
      -- verbosity
      elseif (curr_arg == '-q') or (curr_arg == '--quiet') then
        verbosity_level = 0
      elseif (curr_arg == '-v') or (curr_arg == '--verbose') then
        verbosity_level = 2
      -- problem
      else
        err_print('error', 'unknown option: ' .. curr_arg)
        os.exit(exit_error)
      end
    end

    return action
  end

  local function do_action()
    if action == 'help' then
      io.stdout:write(help_text)
    elseif action == 'version' then
      local info = string.format([[
This is %s
%s

Copyright 2018 %s.
License: %s.
This is free software: you are free to change and redistribute it.

]],
        llmk_info._VERSION,
        llmk_info._DESCRIPTION,
        llmk_info._AUTHOR,
        llmk_info._LICENSE
      )
      io.stdout:write(info)
    end
  end

  function main()
    action = read_options()

    if action then
      do_action()
      os.exit(exit_ok)
    end

    make(arg)
    os.exit(exit_ok)
  end
end

----------------------------------------

main()

-- EOF

-- ============================================================================
-- Native Lazy Loader for Neovim 0.12
-- Built on top of vim.pack
--
-- Compatible with common lazy.nvim plugin specs:
--
-- {
--     "author/plugin",
--     event = "VeryLazy",
--     ft = { "lua", "javascript" },
--     cmd = { "SomeCommand" },
--     keys = {
--         { "<leader>x", "<cmd>SomeCommand<CR>" },
--     },
--     dependencies = {
--         "author/dependency",
--     },
--     opts = {},
--     config = function(_, opts)
--         require("plugin").setup(opts)
--     end,
--     build = ":SomeBuildCommand",
--     branch = "main",
--     version = "1.0",
-- }
--
-- ============================================================================

local M = {}

M.plugins = {}
M.loaded = {}
M.specs = {}
M.initialized = {}

local GROUP_PREFIX = "NativeLazy"

-- ============================================================================
-- Helpers
-- ============================================================================

local function notify(message, level)
    vim.schedule(function()
        vim.notify(message, level or vim.log.levels.INFO, {
            title = "Native Lazy",
        })
    end)
end

local function as_list(value)
    if value == nil then
        return {}
    end

    if type(value) == "table" then
        return value
    end

    return { value }
end

local function is_string(value)
    return type(value) == "string" and value ~= ""
end

local function normalize_src(src)
    if not is_string(src) then
        return src
    end

    -- Sudah berupa URL / Git source
    if src:match("^https?://")
        or src:match("^ssh://")
        or src:match("^git://")
        or src:match("^git@")
    then
        return src
    end

    -- GitHub shorthand:
    --
    -- nvim-lua/plenary.nvim
    -- ->
    -- https://github.com/nvim-lua/plenary.nvim
    --
    if src:match("^[%w_.%-]+/[%w_.%-]+$") then
        return "https://github.com/" .. src
    end

    return src
end

local function resolve_version(spec)
    local version = spec.version

    if not is_string(version) then
        return nil
    end

    -- ---------------------------------------------------------------
    -- Exact tag / branch / commit
    --
    -- Examples:
    -- v2.5.0
    -- main
    -- master
    -- abc123...
    -- ---------------------------------------------------------------

    if not version:find("[%*xX]") then
        return version
    end

    -- ---------------------------------------------------------------
    -- lazy.nvim semver wildcard
    --
    -- v2.*
    -- v2.x
    -- v2.x.x
    --
    -- 1.*
    -- 1.x
    -- 1.x.x
    -- ---------------------------------------------------------------

    local major, minor = version:match("^v?(%d+)%.(%d+)%.[%*xX]$")

    if not major then
        major, minor = version:match("^v?(%d+)%.([%*xX])$")
    end

    if not major then
        major = version:match("^v?(%d+)%.[%*xX]")
    end

    if not major then
        return version
    end

    local src = normalize_src(spec.src)

    if not src then
        return version
    end

    -- ---------------------------------------------------------------
    -- Get tags from git
    -- ---------------------------------------------------------------

    local result = vim.system(
        {
            "git",
            "ls-remote",
            "--tags",
            "--refs",
            src,
        },
        {
            text = true,
        }
    ):wait()

    if result.code ~= 0 then
        notify(
            "Unable to resolve version "
                .. version
                .. " for "
                .. spec.name,
            vim.log.levels.WARN
        )

        return nil
    end

    local tags = {}

    for line in result.stdout:gmatch("[^\r\n]+") do
        local hash, tag = line:match("^(%x+)%s+refs/tags/(.+)$")

        if hash and tag then
            tags[#tags + 1] = tag
        end
    end

    -- ---------------------------------------------------------------
    -- Filter matching tags
    -- ---------------------------------------------------------------

    local matching = {}

    for _, tag in ipairs(tags) do
        local clean = tag:gsub("^v", "")

        local tag_major, tag_minor, tag_patch =
            clean:match("^(%d+)%.(%d+)%.(%d+)$")

        if tag_major then
            local matches = false

            if minor then
                if minor == "x"
                    or minor == "*"
                then
                    matches =
                        tonumber(tag_major)
                        == tonumber(major)
                else
                    matches =
                        tonumber(tag_major)
                            == tonumber(major)
                        and tonumber(tag_minor)
                            == tonumber(minor)
                end
            else
                matches =
                    tonumber(tag_major)
                    == tonumber(major)
            end

            if matches then
                matching[#matching + 1] = {
                    tag = tag,
                    major = tonumber(tag_major),
                    minor = tonumber(tag_minor),
                    patch = tonumber(tag_patch),
                }
            end
        end
    end

    if #matching == 0 then
        notify(
            "No tag found matching "
                .. version
                .. " for "
                .. spec.name,
            vim.log.levels.WARN
        )

        return nil
    end

    -- ---------------------------------------------------------------
    -- Sort newest first
    -- ---------------------------------------------------------------

    table.sort(
        matching,
        function(a, b)
            if a.major ~= b.major then
                return a.major > b.major
            end

            if a.minor ~= b.minor then
                return a.minor > b.minor
            end

            return a.patch > b.patch
        end
    )

    return matching[1].tag
end

local function plugin_name(spec)
    if type(spec) ~= "table" then
        return nil
    end

    if is_string(spec.name) then
        return spec.name
    end

    local src = spec.src

    if not src and type(spec[1]) == "string" then
        src = spec[1]
    end

    if not is_string(src) then
        return nil
    end

    src = src:gsub("/$", "")
    src = src:gsub("%.git$", "")

    return src:match("([^/:]+)$")
end

local function normalize_spec(spec)
    -- ---------------------------------------------------------------
    -- String:
    --
    -- "nvim-lua/plenary.nvim"
    -- ---------------------------------------------------------------

    if type(spec) == "string" then
        spec = {
            src = spec,
        }

    elseif type(spec) ~= "table" then
        error(
            "Invalid plugin specification: expected table/string, got "
                .. type(spec)
        )

    else
        spec = vim.deepcopy(spec)
    end

    -- ---------------------------------------------------------------
    -- lazy.nvim:
    --
    -- {
    --     "author/plugin",
    -- }
    -- ---------------------------------------------------------------

    if spec.src == nil and type(spec[1]) == "string" then
        spec.src = spec[1]
        spec[1] = nil
    end

    -- ---------------------------------------------------------------
    -- lazy.nvim aliases
    -- ---------------------------------------------------------------

    if spec.src == nil and is_string(spec.url) then
        spec.src = spec.url
    end

    -- lazy.nvim branch
    if spec.version == nil and is_string(spec.branch) then
        spec.version = spec.branch
    end

    -- lazy.nvim tag
    if spec.version == nil and is_string(spec.tag) then
        spec.version = spec.tag
    end

    -- lazy.nvim commit
    if spec.version == nil and is_string(spec.commit) then
        spec.version = spec.commit
    end

    spec.src = normalize_src(spec.src)
    spec.name = spec.name or plugin_name(spec)

    if not is_string(spec.name) then
        error(
            "Unable to determine plugin name from specification:\n"
                .. vim.inspect(spec)
        )
    end

    if not is_string(spec.src) then
        error(
            "Plugin '" .. spec.name .. "' does not have a valid src.\n"
                .. "Expected something like:\n\n"
                .. '{ "author/plugin" }\n'
        )
    end

    return spec
end

-- ============================================================================
-- Recursive flatten
-- ============================================================================

local function is_plugin_spec(value)
    if type(value) == "string" then
        return true
    end

    if type(value) ~= "table" then
        return false
    end

    -- Explicit plugin source
    if value.src ~= nil then
        return true
    end

    -- Explicit plugin name
    if value.name ~= nil then
        return true
    end

    -- lazy.nvim style:
    --
    -- {
    --     "author/plugin",
    -- }
    --
    -- Only consider it a plugin spec when
    -- the first element is a string.
    if type(value[1]) == "string" then
        return true
    end

    return false
end


local function flatten_specs(input, output)
    output = output or {}

    if type(input) == "string" then
        output[#output + 1] = normalize_spec(input)
        return output
    end

    if type(input) ~= "table" then
        error(
            "Invalid plugin list: expected table/string, got "
                .. type(input)
        )
    end

    ------------------------------------------------------------------------
    -- IMPORTANT:
    --
    -- Check whether this table itself is a plugin spec.
    --
    -- A nested list such as:
    --
    -- {
    --     {
    --         "plugin-a",
    --     },
    --     {
    --         "plugin-b",
    --     },
    -- }
    --
    -- must NOT be passed to normalize_spec().
    ------------------------------------------------------------------------

    if is_plugin_spec(input) then
        output[#output + 1] = normalize_spec(input)
        return output
    end

    ------------------------------------------------------------------------
    -- Otherwise it is a container/list.
    ------------------------------------------------------------------------

    for _, item in ipairs(input) do
        flatten_specs(item, output)
    end

    return output
end

function M.normalize(specs)
    if specs == nil then
        return {}
    end

    return flatten_specs(specs)
end

-- ============================================================================
-- Enabled / condition
-- ============================================================================

local function is_enabled(spec)
    if spec.enabled == false then
        return false
    end

    if type(spec.enabled) == "function" then
        local ok, result = pcall(spec.enabled)

        if not ok then
            notify(
                "enabled() failed for " .. spec.name,
                vim.log.levels.ERROR
            )

            return false
        end

        if not result then
            return false
        end
    end

    if type(spec.cond) == "function" then
        local ok, result = pcall(spec.cond)

        if not ok then
            notify(
                "cond() failed for " .. spec.name,
                vim.log.levels.ERROR
            )

            return false
        end

        if not result then
            return false
        end
    elseif spec.cond == false then
        return false
    end

    return true
end

-- ============================================================================
-- Plugin information
-- ============================================================================

local function get_pack(name)
    local plugins = vim.pack.get()

    for _, plugin in ipairs(plugins) do
        if plugin.spec and plugin.spec.name == name then
            return plugin
        end
    end

    return nil
end

local function plugin_installed(name)
    return get_pack(name) ~= nil
end

-- ============================================================================
-- Main module detection
-- ============================================================================

local function guess_main(spec)
    if is_string(spec.main) then
        return spec.main
    end

    local name = spec.name

    -- Remove common suffix
    name = name:gsub("%.nvim$", "")
    name = name:gsub("%.lua$", "")

    -- nvim-telescope/telescope.nvim -> telescope
    -- folke/noice.nvim -> noice
    -- lewis6991/gitsigns.nvim -> gitsigns

    local main = name:match("/(.+)$") or name

    main = main:gsub("^nvim%-", "")
    main = main:gsub("^mini%.", "")

    return main
end

-- ============================================================================
-- opts
-- ============================================================================

local function get_opts(spec)
    if spec.opts == nil then
        return nil
    end

    if type(spec.opts) == "function" then
        local ok, result = pcall(spec.opts, spec, {})

        if not ok then
            notify(
                "opts() failed for " .. spec.name .. ":\n" .. tostring(result),
                vim.log.levels.ERROR
            )

            return nil
        end

        return result
    end

    return spec.opts
end

-- ============================================================================
-- init
-- ============================================================================

local function run_init(spec)
    if M.initialized[spec.name] then
        return
    end

    M.initialized[spec.name] = true

    if type(spec.init) ~= "function" then
        return
    end

    local ok, err = pcall(spec.init, spec)

    if not ok then
        notify(
            "init() failed for "
                .. spec.name
                .. ":\n"
                .. tostring(err),
            vim.log.levels.ERROR
        )
    end
end

-- ============================================================================
-- Automatic setup from opts
-- ============================================================================

local function automatic_setup(spec, opts)
    if opts == nil then
        return false
    end

    if spec.config ~= nil then
        return false
    end

    if spec.main == false then
        return false
    end

    local main = guess_main(spec)

    if not is_string(main) then
        return false
    end

    local ok, module = pcall(require, main)

    if not ok then
        return false
    end

    if type(module) ~= "table" then
        return false
    end

    if type(module.setup) ~= "function" then
        return false
    end

    local setup_ok, setup_err = pcall(
        module.setup,
        opts
    )

    if not setup_ok then
        notify(
            "setup() failed for "
                .. spec.name
                .. ":\n"
                .. tostring(setup_err),
            vim.log.levels.ERROR
        )

        return false
    end

    return true
end

-- ============================================================================
-- Build
-- ============================================================================

local function execute_build(spec, path)
    if not spec.build then
        return
    end

    local build = spec.build

    -- lazy.nvim allows:
    --
    -- build = false
    -- build = function()
    -- build = ":TSUpdate"
    -- build = "make"
    -- build = { "make", "install" }

    if build == false then
        return
    end

    if type(build) == "function" then
        local ok, err = pcall(build)

        if not ok then
            notify(
                "Build failed for "
                    .. spec.name
                    .. ":\n"
                    .. tostring(err),
                vim.log.levels.ERROR
            )
        end

        return
    end

    if type(build) == "string" then
        -- Vim command
        if build:sub(1, 1) == ":" then
            local command = build:sub(2)

            vim.schedule(function()
                vim.cmd("silent " .. command)
            end)

            return
        end

        -- Shell command
        vim.system(
            { "sh", "-c", build },
            {
                cwd = path,
                text = true,
            },
            function(result)
                if result.code ~= 0 then
                    notify(
                        "Build failed for "
                            .. spec.name,
                        vim.log.levels.ERROR
                    )
                else
                    notify(
                        "Build completed: "
                            .. spec.name
                    )
                end
            end
        )

        return
    end

    if type(build) == "table" then
        vim.system(
            build,
            {
                cwd = path,
                text = true,
            },
            function(result)
                if result.code ~= 0 then
                    notify(
                        "Build failed for "
                            .. spec.name,
                        vim.log.levels.ERROR
                    )
                end
            end
        )
    end
end

-- ============================================================================
-- PackChanged build hook
-- ============================================================================

local function register_pack_hooks(specs)
    vim.api.nvim_create_autocmd("PackChanged", {
        group = vim.api.nvim_create_augroup(
            "NativeLazyPackHooks",
            { clear = true }
        ),

        callback = function(event)
            if not event.data then
                return
            end

            local data = event.data
            local name = data.spec and data.spec.name

            if not name then
                return
            end

            local spec = M.specs[name]

            if not spec then
                return
            end

            if data.kind == "install"
                or data.kind == "update"
            then
                if spec.build then
                    execute_build(
                        spec,
                        data.path
                    )
                end
            end
        end,
    })
end

-- ============================================================================
-- Dependencies
-- ============================================================================

local function register_dependency(dep)
    local spec = normalize_spec(dep)

    if not M.specs[spec.name] then
        M.specs[spec.name] = spec
        M.plugins[spec.name] = spec
    end

    return spec
end

local function register_dependencies(spec)
    for _, dependency in ipairs(
        as_list(spec.dependencies)
    ) do
        if type(dependency) == "table"
            and dependency[1] == nil
            and dependency.src == nil
            and dependency.name == nil
        then
            -- Nested dependency list
            for _, nested in ipairs(dependency) do
                register_dependency(nested)
            end
        else
            register_dependency(dependency)
        end
    end
end

-- ============================================================================
-- Dependency loading
-- ============================================================================

local function load_dependencies(spec)
    for _, dependency in ipairs(
        as_list(spec.dependencies)
    ) do
        local dep

        if type(dependency) == "table"
            and dependency[1] == nil
            and dependency.src == nil
            and dependency.name == nil
        then
            for _, nested in ipairs(dependency) do
                dep = normalize_spec(nested)
                M.specs[dep.name] = dep
                M.plugins[dep.name] = dep
                M.load(dep.name)
            end
        else
            dep = normalize_spec(dependency)

            M.specs[dep.name] =
                M.specs[dep.name] or dep

            M.plugins[dep.name] =
                M.plugins[dep.name] or dep

            M.load(dep.name)
        end
    end
end

-- ============================================================================
-- Plugin load
-- ============================================================================

function M.load(name)
    if M.loaded[name] then
        return true
    end

    local spec = M.specs[name]

    if not spec then
        notify(
            "Plugin specification not found: "
                .. tostring(name),
            vim.log.levels.ERROR
        )

        return false
    end

    if not is_enabled(spec) then
        return false
    end

    --------------------------------------------------------------------------
    -- Dependencies
    --------------------------------------------------------------------------

    load_dependencies(spec)

    --------------------------------------------------------------------------
    -- Remove lazy command wrappers before packadd
    --------------------------------------------------------------------------

    if spec.cmd then
        for _, command in ipairs(
            as_list(spec.cmd)
        ) do
            pcall(
                vim.api.nvim_del_user_command,
                command
            )
        end
    end

    --------------------------------------------------------------------------
    -- Load plugin
    --------------------------------------------------------------------------

    if not plugin_installed(name) then
        notify(
            "Plugin is not installed: "
                .. name,
            vim.log.levels.ERROR
        )

        return false
    end

    local ok, err = pcall(
        vim.cmd.packadd,
        name
    )

    if not ok then
        notify(
            "Failed to load "
                .. name
                .. ":\n"
                .. tostring(err),
            vim.log.levels.ERROR
        )

        return false
    end

    M.loaded[name] = true

    --------------------------------------------------------------------------
    -- opts
    --------------------------------------------------------------------------

    local opts = get_opts(spec)

    --------------------------------------------------------------------------
    -- config
    --------------------------------------------------------------------------

    if type(spec.config) == "function" then
        local config_ok, config_err =
            pcall(
                spec.config,
                spec,
                opts
            )

        if not config_ok then
            notify(
                "config() failed for "
                    .. name
                    .. ":\n"
                    .. tostring(config_err),
                vim.log.levels.ERROR
            )

            return false
        end

    else
        ----------------------------------------------------------------------
        -- Automatic:
        --
        -- opts = {}
        --
        -- becomes:
        --
        -- require("plugin").setup({})
        ----------------------------------------------------------------------

        automatic_setup(spec, opts)
    end

    return true
end

-- ============================================================================
-- Event
-- ============================================================================

local function register_event(spec)
    if not spec.event then
        return
    end

    local group = vim.api.nvim_create_augroup(
        GROUP_PREFIX .. "_" .. spec.name,
        { clear = true }
    )

    for _, event in ipairs(
        as_list(spec.event)
    ) do
        ----------------------------------------------------------------------
        -- lazy.nvim:
        --
        -- event = "VeryLazy"
        --
        -- is actually a User event.
        ----------------------------------------------------------------------

        if event == "VeryLazy" then
            vim.api.nvim_create_autocmd(
                "User",
                {
                    group = group,
                    pattern = "VeryLazy",

                    once = true,

                    callback = function()
                        M.load(spec.name)
                    end,

                    desc = "Load " .. spec.name,
                }
            )
        else
            vim.api.nvim_create_autocmd(
                event,
                {
                    group = group,

                    once = true,

                    callback = function()
                        M.load(spec.name)
                    end,

                    desc = "Load " .. spec.name,
                }
            )
        end
    end
end

-- ============================================================================
-- Filetype
-- ============================================================================

local function register_ft(spec)
    if not spec.ft then
        return
    end

    local group = vim.api.nvim_create_augroup(
        GROUP_PREFIX .. "_FT_" .. spec.name,
        { clear = true }
    )

    vim.api.nvim_create_autocmd(
        "FileType",
        {
            group = group,

            pattern = as_list(spec.ft),

            callback = function()
                M.load(spec.name)
            end,

            desc = "Load " .. spec.name,
        }
    )
end

-- ============================================================================
-- Command
-- ============================================================================

local function command_exists(command)
    return vim.fn.exists(":" .. command) == 2
end

local function register_cmd(spec)
    if not spec.cmd then
        return
    end

    local group = vim.api.nvim_create_augroup(
        GROUP_PREFIX .. "_CMD_" .. spec.name,
        { clear = true }
    )

    for _, command in ipairs(
        as_list(spec.cmd)
    ) do
        if not command_exists(command) then
            vim.api.nvim_create_user_command(
                command,
                function(opts)
                    M.load(spec.name)

                    local args = opts.args or ""

                    local command_line = command

                    if opts.bang then
                        command_line = command_line .. "!"
                    end

                    if args ~= "" then
                        command_line =
                            command_line .. " " .. args
                    end

                    if opts.range > 0 then
                        command_line =
                            "'<,'>" .. command_line
                    end

                    vim.cmd(command_line)
                end,
                {
                    nargs = "*",
                    bang = true,
                    range = true,

                    complete = "file",

                    desc =
                        "Lazy load "
                        .. spec.name,
                }
            )
        end
    end
end

-- ============================================================================
-- Keymaps
-- ============================================================================

local function register_keys(spec)
    if not spec.keys then
        return
    end

    local keys = spec.keys

    -- Support:
    --
    -- keys = {
    --     "<leader>x",
    -- }
    --
    -- and:
    --
    -- keys = {
    --     {
    --         "<leader>x",
    --         "<cmd>Something<CR>",
    --     },
    -- }

    if type(keys) == "string" then
        keys = {
            { keys },
        }

    elseif keys[1]
        and type(keys[1]) == "string"
    then
        keys = {
            keys,
        }
    end

    for _, key_spec in ipairs(keys) do
        if type(key_spec) ~= "table" then
            goto continue
        end

        local lhs = key_spec[1]
        local rhs = key_spec[2]

        if not lhs then
            goto continue
        end

        local mode = key_spec.mode
            or key_spec[3]
            or "n"

        local opts = {
            silent = key_spec.silent ~= false,
            noremap = key_spec.noremap ~= false,
        }

        if key_spec.desc then
            opts.desc = key_spec.desc
        end

        if key_spec.expr ~= nil then
            opts.expr = key_spec.expr
        end

        vim.keymap.set(
            mode,
            lhs,
            function(...)
                ----------------------------------------------------------------
                -- Load plugin
                ----------------------------------------------------------------

                local loaded =
                    M.load(spec.name)

                if not loaded then
                    return
                end

                ----------------------------------------------------------------
                -- Function RHS
                ----------------------------------------------------------------

                if type(rhs) == "function" then
                    return rhs(...)
                end

                ----------------------------------------------------------------
                -- String RHS
                ----------------------------------------------------------------

                if type(rhs) == "string" then
                    vim.api.nvim_feedkeys(
                        vim.api.nvim_replace_termcodes(
                            rhs,
                            true,
                            false,
                            true
                        ),
                        "m",
                        false
                    )
                end
            end,
            opts
        )

        ::continue::
    end
end

-- ============================================================================
-- Register lazy triggers
-- ============================================================================

local function register(spec)
    if not is_enabled(spec) then
        return
    end

    register_event(spec)
    register_ft(spec)
    register_cmd(spec)
    register_keys(spec)
end

-- ============================================================================
-- vim.pack.add
-- ============================================================================

local function install(specs)
    local pack_specs = {}

    for _, spec in ipairs(specs) do
        if is_enabled(spec) then
            local pack_spec = {
                src = spec.src,
                name = spec.name,
            }

            local version = resolve_version(spec)

            if version ~= nil then
                pack_spec.version = version
            end

            pack_specs[#pack_specs + 1] =
                pack_spec
        end
    end

    if #pack_specs == 0 then
        return
    end

    vim.pack.add(
        pack_specs,
        {
            load = false,
            confirm = false,
        }
    )
end

-- ============================================================================
-- Startup ordering
-- ============================================================================

local function sort_startup(specs)
    table.sort(
        specs,
        function(a, b)
            local pa = tonumber(a.priority) or 50
            local pb = tonumber(b.priority) or 50

            return pa > pb
        end
    )

    return specs
end

-- ============================================================================
-- VeryLazy
-- ============================================================================

local function register_very_lazy()
    vim.api.nvim_create_autocmd(
        "VimEnter",
        {
            group = vim.api.nvim_create_augroup(
                "NativeLazyVeryLazy",
                { clear = true }
            ),

            once = true,

            callback = function()
                vim.schedule(function()
                    vim.api.nvim_exec_autocmds(
                        "User",
                        {
                            pattern = "VeryLazy",
                        }
                    )
                end)
            end,
        }
    )
end

-- ============================================================================
-- Commands
-- ============================================================================

local function register_commands()
    --------------------------------------------------------------------------
    -- :Lazy
    --------------------------------------------------------------------------

    vim.api.nvim_create_user_command(
        "Lazy",
        function()
            vim.cmd("packupdate")
        end,
        {
            desc = "Update plugins",
        }
    )

    --------------------------------------------------------------------------
    -- :LazyUpdate
    --------------------------------------------------------------------------

    vim.api.nvim_create_user_command(
        "LazyUpdate",
        function()
            vim.cmd("packupdate")
        end,
        {
            desc = "Update plugins",
        }
    )

    --------------------------------------------------------------------------
    -- :LazySync
    --------------------------------------------------------------------------

    vim.api.nvim_create_user_command(
        "LazySync",
        function()
            vim.cmd("packupdate")
        end,
        {
            desc = "Update plugins",
        }
    )

    --------------------------------------------------------------------------
    -- :LazyClean
    --------------------------------------------------------------------------

    vim.api.nvim_create_user_command(
        "LazyClean",
        function()
            vim.cmd("packdel ++all")
        end,
        {
            desc = "Delete inactive plugins",
        }
    )

    --------------------------------------------------------------------------
    -- :LazyProfile
    --------------------------------------------------------------------------

    vim.api.nvim_create_user_command(
        "LazyProfile",
        function()
            local lines = {
                "",
                "Native vim.pack Plugin Status",
                "==============================",
                "",
            }

            local names = {}

            for name in pairs(M.specs) do
                names[#names + 1] = name
            end

            table.sort(names)

            for _, name in ipairs(names) do
                local status

                if M.loaded[name] then
                    status = "LOADED"
                else
                    status = "LAZY"
                end

                lines[#lines + 1] =
                    string.format(
                        "%-45s %s",
                        name,
                        status
                    )
            end

            vim.cmd("new")

            local buffer = vim.api.nvim_get_current_buf()

            vim.bo[buffer].buftype = "nofile"
            vim.bo[buffer].bufhidden = "wipe"
            vim.bo[buffer].swapfile = false
            vim.bo[buffer].modifiable = true

            vim.api.nvim_buf_set_lines(
                buffer,
                0,
                -1,
                false,
                lines
            )

            vim.bo[buffer].modifiable = false
        end,
        {
            desc = "Show plugin loading status",
        }
    )

    --------------------------------------------------------------------------
    -- :LazyLoad
    --------------------------------------------------------------------------

    vim.api.nvim_create_user_command(
        "LazyLoad",
        function(opts)
            if opts.args == "" then
                notify(
                    "Usage: :LazyLoad plugin-name",
                    vim.log.levels.WARN
                )

                return
            end

            M.load(opts.args)
        end,
        {
            nargs = 1,
            complete = function()
                local result = {}

                for name in pairs(M.specs) do
                    result[#result + 1] = name
                end

                table.sort(result)

                return result
            end,

            desc = "Load plugin manually",
        }
    )
end

-- ============================================================================
-- Setup
-- ============================================================================

function M.setup(specs)
    if vim.fn.has("nvim-0.12") ~= 1 then
        error(
            "Native lazy loader requires Neovim 0.12+"
        )
    end

    --------------------------------------------------------------------------
    -- Normalize / flatten
    --------------------------------------------------------------------------

    local normalized =
        M.normalize(specs)

    --------------------------------------------------------------------------
    -- Register top-level specs
    --------------------------------------------------------------------------

    for _, spec in ipairs(normalized) do
        if is_enabled(spec) then
            M.specs[spec.name] = spec
            M.plugins[spec.name] = spec
        end
    end

    --------------------------------------------------------------------------
    -- Register dependencies recursively
    --------------------------------------------------------------------------

    local changed = true

    while changed do
        changed = false

        local before = vim.tbl_count(M.specs)

        for _, spec in pairs(M.specs) do
            register_dependencies(spec)
        end

        local after = vim.tbl_count(M.specs)

        if after ~= before then
            changed = true
        end
    end

    --------------------------------------------------------------------------
    -- Initialize plugins
    --
    -- Equivalent to lazy.nvim's init.
    --------------------------------------------------------------------------

    for _, spec in pairs(M.specs) do
        if is_enabled(spec) then
            run_init(spec)
        end
    end

    --------------------------------------------------------------------------
    -- PackChanged hooks MUST be registered before vim.pack.add().
    --------------------------------------------------------------------------

    register_pack_hooks(M.specs)

    --------------------------------------------------------------------------
    -- Install all plugins but DON'T load them.
    --------------------------------------------------------------------------

    local all_specs = {}

    for _, spec in pairs(M.specs) do
        all_specs[#all_specs + 1] = spec
    end

    install(all_specs)

    --------------------------------------------------------------------------
    -- Register lazy triggers
    --------------------------------------------------------------------------

    for _, spec in pairs(M.specs) do
        register(spec)
    end

    --------------------------------------------------------------------------
    -- Startup plugins
    --
    -- lazy = false
    -- OR
    -- no lazy trigger
    --------------------------------------------------------------------------

    local startup = {}

    for _, spec in pairs(M.specs) do
        local has_trigger =
            spec.event ~= nil
            or spec.ft ~= nil
            or spec.cmd ~= nil
            or spec.keys ~= nil

        local is_lazy =
            spec.lazy == true
            or has_trigger

        if spec.lazy == false then
            is_lazy = false
        end

        if not is_lazy then
            startup[#startup + 1] = spec
        end
    end

    startup = sort_startup(startup)

    for _, spec in ipairs(startup) do
        M.load(spec.name)
    end

    --------------------------------------------------------------------------
    -- VeryLazy
    --------------------------------------------------------------------------

    register_very_lazy()

    --------------------------------------------------------------------------
    -- Commands
    --------------------------------------------------------------------------

    register_commands()
end

-- ============================================================================
-- Public API
-- ============================================================================

function M.load_plugin(name)
    return M.load(name)
end

function M.is_loaded(name)
    return M.loaded[name] == true
end

function M.get(name)
    return M.specs[name]
end

function M.list()
    return M.specs
end

return M
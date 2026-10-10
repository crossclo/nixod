# Neovim: LSP, completion, Telescope, tokyonight-day (light theme).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkIf config.nixod.home.neovim.enable (
    lib.mkMerge [
      (defaults {
        programs.neovim = {
          enable = true;
          defaultEditor = true;
          viAlias = true;
          vimAlias = true;
        };
      })

      # Additive: the instance can add packages, plugins and Lua config.
      {
        programs.neovim = {

          # Language servers and tools visible to Neovim.
          extraPackages = with pkgs; [
            clang-tools # clangd
            nil # nix
            lua-language-server
            typescript-language-server
            vscode-langservers-extracted # html, css, json
            pyright
            jdt-language-server # java
            bash-language-server
            nixfmt
            ripgrep # needed by Telescope
            fd
          ];

          plugins = with pkgs.vimPlugins; [
            tokyonight-nvim
            (nvim-treesitter.withPlugins (
              p: with p; [
                c
                cpp
                java
                python
                javascript
                typescript
                tsx
                html
                css
                sql
                nix
                lua
                bash
                make
                cmake
                markdown
                markdown_inline
                json
                yaml
                toml
                dockerfile
                gitcommit
                diff
                regex
                vim
                vimdoc
                query
              ]
            ))
            nvim-lspconfig
            nvim-cmp
            cmp-nvim-lsp
            cmp-buffer
            cmp-path
            luasnip
            cmp_luasnip
            telescope-nvim
            plenary-nvim
            lualine-nvim
            nvim-web-devicons
            gitsigns-nvim
            which-key-nvim
            nvim-autopairs
            indent-blankline-nvim
            oil-nvim
          ];

          initLua = ''
            -- ===== Options =====
            vim.g.mapleader = " "
            vim.opt.number = true
            vim.opt.relativenumber = true
            vim.opt.tabstop = 4
            vim.opt.shiftwidth = 4
            vim.opt.expandtab = true
            vim.opt.smartindent = true
            vim.opt.colorcolumn = "80"     -- 80-column guide
            vim.opt.clipboard = "unnamedplus"
            vim.opt.undofile = true
            vim.opt.ignorecase = true
            vim.opt.smartcase = true
            vim.opt.termguicolors = true
            vim.opt.signcolumn = "yes"
            vim.opt.scrolloff = 8
            vim.opt.updatetime = 250

            -- ===== Theme =====
            -- "day": tokyonight's light variant, matching the light desktop.
            vim.opt.background = "light"
            require("tokyonight").setup({ style = "day" })
            vim.cmd.colorscheme("tokyonight")

            -- ===== UI =====
            require("lualine").setup({ options = { theme = "tokyonight" } })
            require("gitsigns").setup()
            require("which-key").setup()
            require("nvim-autopairs").setup()
            require("ibl").setup()
            require("oil").setup({ view_options = { show_hidden = true } })

            -- ===== Treesitter =====
            require("nvim-treesitter.configs").setup({
              highlight = { enable = true },
              indent = { enable = true },
            })

            -- ===== Completion =====
            local cmp = require("cmp")
            local luasnip = require("luasnip")
            cmp.setup({
              snippet = {
                expand = function(args) luasnip.lsp_expand(args.body) end,
              },
              mapping = cmp.mapping.preset.insert({
                ["<C-Space>"] = cmp.mapping.complete(),
                ["<CR>"] = cmp.mapping.confirm({ select = true }),
                ["<Tab>"] = cmp.mapping.select_next_item(),
                ["<S-Tab>"] = cmp.mapping.select_prev_item(),
              }),
              sources = cmp.config.sources({
                { name = "nvim_lsp" },
                { name = "luasnip" },
                { name = "path" },
              }, {
                { name = "buffer" },
              }),
            })

            -- ===== LSP (API Neovim 0.11) =====
            vim.lsp.config("*", {
              capabilities = require("cmp_nvim_lsp").default_capabilities(),
            })
            vim.lsp.enable({
              "clangd", "nil_ls", "lua_ls", "ts_ls", "pyright",
              "jdtls", "bashls", "html", "cssls", "jsonls",
            })

            vim.diagnostic.config({
              virtual_text = true,
              severity_sort = true,
            })

            -- ===== Keymaps =====
            local map = vim.keymap.set
            local telescope = require("telescope.builtin")
            map("n", "<leader>ff", telescope.find_files, { desc = "Files" })
            map("n", "<leader>fg", telescope.live_grep, { desc = "Grep project" })
            map("n", "<leader>fb", telescope.buffers, { desc = "Buffers" })
            map("n", "<leader>fd", telescope.diagnostics, { desc = "Diagnostics" })
            map("n", "-", "<cmd>Oil<cr>", { desc = "File explorer" })
            map("n", "<leader>f", function() vim.lsp.buf.format() end, { desc = "Format" })
            map("n", "gd", vim.lsp.buf.definition, { desc = "Definition" })
            map("n", "K", vim.lsp.buf.hover, { desc = "Documentation" })
            map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
            map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code actions" })
          '';
        };
      }
    ]
  );
}

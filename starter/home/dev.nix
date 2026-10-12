# Development tools: C/C++, Node, Python, SQLite.
# Add your own languages here, or in another file of home/.
{ lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    # ---- C / C++ ----
    (lib.hiPrio gcc) # hiPrio: gcc provides `cc` (clang offers it too)
    clang
    gdb
    valgrind
    clang-tools # clangd, clang-format, clang-tidy
    gnumake
    cmake
    bear # generates compile_commands.json for clangd (`bear -- make`)
    pkg-config
    man-pages # man 2/3: syscalls and libc
    man-pages-posix

    # ---- Web ----
    nodejs_22

    # ---- Python ----
    uv # Python package/venv manager

    # ---- Databases ----
    sqlite

    # ---- Misc ----
    lazygit # git TUI
    httpie # readable HTTP client
  ];
}

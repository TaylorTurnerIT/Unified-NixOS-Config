# home/taylor/terminal.nix
# Ptyxis terminal emulator, zellij multiplexer, and all terminal utility packages.
# Fully synced between fiji and tuvalu — no hardware conditionals.
{ pkgs, ... }:
{
  # Ptyxis — GTK4/libadwaita terminal with container support
  home.packages = with pkgs; [ ptyxis ];

  # GTK theming — aligns libadwaita (Ptyxis) closer to KDE Plasma color palette
  gtk.enable = true;

  # zellij — terminal multiplexer for persistent remote sessions
  # Primary use: homelab SSH sessions where panes must survive a disconnect
  # Distinct from Ptyxis tabs: Ptyxis = local sessions, zellij = remote persistent panes
  programs.zellij = {
    enable      = true;
    # Layouts declared as YAML in ~/.config/zellij/layouts/
    # Phase 2: declare a "homelab" layout that opens panes to vm1/vm2/vm3
  };

  # Terminal utilities — all synced, no exceptions
  home.packages = with pkgs; [
    # Navigation and search
    zoxide       # frecency-based smart cd — learns your directories, 'z proj' just works
    fzf          # fuzzy finder — backs fzf.fish Ctrl+R, Ctrl+T, Alt+C
    fd           # fast 'find' replacement — respects .gitignore, intuitive: fd pattern
    ripgrep      # fast 'grep' replacement (rg) — respects .gitignore, better output

    # File viewing
    bat          # 'cat' with syntax highlighting, line numbers, git change markers
                 # also set as MANPAGER for readable man pages
    eza          # modern 'ls' — icons, git status, tree view (aliased in shell.nix)
    glow         # renders Markdown in the terminal — for READMEs and documentation

    # File management
    yazi         # TUI file manager — fast previews for code, images, PDFs, archives
                 # shell integration: ya shell-init fish exits into navigated directory

    # System monitoring
    btop         # resource monitor — per-core CPU, memory, disk I/O, network, processes
                 # AMDGPU plugin active on fiji via the AMD GPU module
    gdu          # TUI disk usage analyzer — first tool for investigating /persist usage
                 # Usage: gdu /persist

    # Multiplexer
    # zellij declared above via programs.zellij

    # Reference
    tldr         # simplified community man pages — faster than man for common usage
    navi         # interactive cheatsheet tool — personal searchable knowledge base

    # Data processing (also in dev.nix for editor integration)
    jq           # JSON processor — essential for API work and nix eval --json | jq
    yq-go        # YAML processor — useful for NixOS config inspection
  ];

  # bat as MANPAGER — makes man pages readable with syntax highlighting
  home.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };
}

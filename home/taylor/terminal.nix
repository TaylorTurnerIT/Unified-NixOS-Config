# home/taylor/terminal.nix
# Ptyxis terminal emulator, zellij multiplexer, and all terminal utility packages.
# Fully synced between fiji and tuvalu — no hardware conditionals.
{ pkgs, ... }:
{
  gtk.enable = true;

  programs.zellij = {
    enable = true;
  };

  home.packages = with pkgs; [
    ptyxis      # GTK4/libadwaita terminal — container-aware, clean tab model

    # Navigation and search
    zoxide      # frecency-based smart cd
    fzf         # fuzzy finder — backs fzf.fish Ctrl+R, Ctrl+T, Alt+C
    fd          # fast find replacement — respects .gitignore
    ripgrep     # fast grep replacement (rg) — respects .gitignore

    # File viewing
    bat         # cat with syntax highlighting, line numbers, git markers
    eza         # modern ls — icons, git status, tree view
    glow        # renders Markdown in terminal

    # File management
    yazi        # TUI file manager — fast previews

    # System monitoring
    btop        # resource monitor — replaces htop
    gdu         # TUI disk usage analyzer

    # Reference
    tldr        # simplified man pages
    navi        # interactive cheatsheet tool

    # Data processing
    jq          # JSON processor
    yq-go       # YAML processor
  ];

  home.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };
}

# home/taylor/shell.nix
# Fish shell, Starship prompt, aliases, environment variables, and Fish plugins.
# Fully synced between fiji-desktop and tuvalu-laptop — no hardware conditionals.
{ pkgs, ... }:
{
  # Fish shell — interactive shell
  programs.fish = {
    enable = true;

    # Fish plugins — declared here, not installed imperatively via fisher
    plugins = [
      {
        # bass — runs bash scripts from Fish; essential for tools that emit bash init scripts
        name = "bass";
        src  = pkgs.fishPlugins.bass.src;
      }
      {
        # fzf.fish — wires fzf into Fish: Ctrl+R history, Ctrl+T file picker, Alt+C cd
        name = "fzf-fish";
        src  = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        # autopair.fish — auto-closes brackets, quotes, parentheses
        name = "autopair";
        src  = pkgs.fishPlugins.autopair.src;
      }
      {
        # puffer-fish — text expansion: ... -> ../.., .... -> ../../.. etc
        name = "puffer";
        src  = pkgs.fishPlugins.puffer.src;
      }
    ];

    # Shell aliases — override GNU coreutils with modern replacements
    shellAliases = {
      # eza replaces ls — icons, git status, tree view
      ls   = "eza --icons";
      l    = "ll";
      ll   = "eza --icons -la";
      la   = "eza --icons -a";
      tree = "eza --icons --tree";

      # bat replaces cat — syntax highlighting, line numbers, git markers
      cat  = "bat";

      # fd replaces find — faster, respects .gitignore, intuitive syntax
      find = "fd";

      # ripgrep replaces grep — faster, respects .gitignore, better output
      grep = "rg";

      # btop replaces htop/top — per-core CPU, memory, disk I/O, network, process tree
      top  = "btop";

      # zoxide replaces cd — frecency-based smart jump (z learns your directories)
      # 'cd' alias only works after zoxide has learned some directories
      cd   = "z";

      # Convenience
      g    = "git";
      lg   = "lazygit";
      c    = "clear";

      # Manual Building with early stop via flake check
      nix-build = "nix flake check && sudo nixos-rebuild switch --flake .#tuvalu-laptop";
    };

    # Interactive shell initialization — runs on every Fish session start
    interactiveShellInit = ''
      # zoxide — initialize after Fish starts
      # Provides: z <partial-path> to jump to frecent directories
      ${pkgs.zoxide}/bin/zoxide init fish | source

      # atuin — replace Fish's default Ctrl+R with atuin's rich history search
      # History stored in SQLite: timestamp, directory, exit code, duration
      ${pkgs.atuin}/bin/atuin init fish | source

      # direnv — activate .envrc automatically on directory change
      # With nix-direnv: Nix dev shells activate instantly (cached)
      ${pkgs.direnv}/bin/direnv hook fish | source
    '';
  };

  # Starship — cross-shell prompt
  programs.starship = {
    enable = true;
    settings = {
      format = "$all";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol   = "[➜](bold red)";
      };
      nix_shell = {
        disabled = false;
        symbol   = " ";
      };
      git_branch.symbol = " ";
      directory.truncation_length = 4;
    };
  };

  # direnv + nix-direnv — auto-activate Nix dev shells per directory
  programs.direnv = {
    enable             = true;
    nix-direnv.enable  = true;  # caches shells — re-entry is instant, no rebuild
  };

  # atuin — shell history in SQLite
  programs.atuin = {
    enable   = true;
    settings = {
      auto_sync    = false;  # local-only; no sync server configured
      sync_address = "";
      search_mode  = "fuzzy";
      filter_mode  = "directory"; # Ctrl+R shows history for current directory first
    };
  };
}

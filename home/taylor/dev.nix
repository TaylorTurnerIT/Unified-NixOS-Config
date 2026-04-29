# home/taylor/dev.nix
# Git configuration, delta diff pager, lazygit, and development tools.
# Fully synced between fiji and tuvalu — no hardware conditionals.
{ pkgs, ... }:
{
  # Git — declarative config via Home Manager
  programs.git = {
    enable    = true;
    userName  = "Taylor";
    userEmail = "taylort3450@proton.me"; # TODO: confirm email

    # delta — syntax-highlighted diff pager
    # Replaces the default diff output with side-by-side highlighted diffs
    extraConfig = {
      core.pager         = "${pkgs.delta}/bin/delta";
      interactive.diffFilter = "${pkgs.delta}/bin/delta --color-only";
      delta = {
        navigate    = true;   # n/N to move between diff sections
        side-by-side = true;
        line-numbers = true;
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved     = "default";
      init.defaultBranch  = "main";
      pull.rebase         = true;
    };
  };

  home.packages = with pkgs; [
    delta    # git diff pager — syntax highlighting, side-by-side (configured above)
    lazygit  # TUI git client — interactive rebase, hunk staging, branch management
             # keyboard-driven, good for careful commit hygiene on a public repo
  ];
}

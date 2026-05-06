# home/taylor/dev.nix
{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name  = "Taylor";
      user.email = "taylort3450@proton.me";
      core.pager = "${pkgs.delta}/bin/delta";
      interactive.diffFilter = "${pkgs.delta}/bin/delta --color-only";
      delta = {
        navigate     = true;
        side-by-side = true;
        line-numbers = true;
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved     = "default";
      init.defaultBranch  = "main";
      pull.rebase         = true;
    };
  };

  # GitHub CLI configuration
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };

  home.packages = with pkgs; [
    delta
    lazygit
    zed-editor
    tea
  ];
}

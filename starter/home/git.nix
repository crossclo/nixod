# Git habits: delta diffs, rebase on pull, remembered conflict fixes.
# (nixod itself sets the identity and commit signing.)
{
  programs.git.settings = {
    init.defaultBranch = "main";
    pull.rebase = true;
    push.autoSetupRemote = true;
    rerere.enabled = true;
  };

  # Colored, readable diffs.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };
}

{ pkgs, ... }:

{
  home.stateVersion = "26.05";

  programs.git = {
    enable = true;
    lfs.enable = true;

    signing = {
      key = "8D635033E52672B6";
      signByDefault = true;
    };

    settings = {
      user = {
        name = "DjLeChuck";
        email = "djlechuck@gmail.com";
      };

      core.excludesFile = "~/.gitignoreglobal";

      pull.rebase = false;
      fetch.prune = true;
      init.defaultBranch = "main";
      rerere.enabled = true;
      lfs.locksverify = true;

      credential.helper = "${pkgs.gitFull}/lib/git-core/git-credential-libsecret";

      alias = {
        di = "diff -D";
        co = "checkout";
        ci = "commit";
        st = "status -s";
        br = "branch -v";
        re = "remote -v";
        hist = ''log --pretty=format:"%h %ad | %s%d [%an]" --graph --date=short'';
        rh = "reset HEAD";
        rhh = "reset --hard HEAD";
        map = ''log --graph --full-history --all --color --pretty=format:"%Credm%h%Creset%x09%x1b[32m%d%x1b[0m%x20%s %Cgreen(%cr) %C(bold blue)<%an>%Creset"'';
        logme = "log --author='vdebona@umanit.fr'";
        files = "!sh -c 'git diff-tree --no-commit-id --name-only -r $0'";
        amend = "commit --amend";
        ignore = "!sh -c 'git ls-files -z $0 | xargs -0 git update-index --skip-worktree'";
        unignore = "!sh -c 'git ls-files -z $0 | xargs -0 git update-index --no-skip-worktree'";
        ignored = ''!git ls-files -v | grep "^S"'';
        undo = "reset --soft HEAD^";
        alias = ''! git config --get-regexp ^alias\\. | sed -e s/^alias\\.// -e s/\\ /\\ =\\ /'';
        mr = "!sh -c 'git fetch $1 merge-requests/$2/head:mr-$1-$2 && git checkout mr-$1-$2' -";
      };
    };

    includes = [
      {
        condition = "gitdir:~/development/php/";
        contents = {
          user = {
            email = "vdebona@umanit.fr";
            name = "Vivien DE BONA";
          };
        };
      }
      {
        condition = "gitdir:~/development/php/perso/";
        contents = {
          user = {
            email = "djlechuck@gmail.com";
            name = "DjLeChuck";
          };
        };
      }
    ];

    ignores = [
      ".idea/"
      ".intellijPlatform/"
      "**/_akkalia.yaml"
      "**/.claude/settings.local.json"
    ];
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      # Remove greeting message
      set -g fish_greeting

      # Global variables
      set -gx EDITOR vim
      set -gx CDG_DIR ~/development/php
      set -gx GPG_TTY (tty)

      # Colors (custom theme)
      set -g fish_color_autosuggestion 969896
      set -g fish_color_cancel -r
      set -g fish_color_command c397d8
      set -g fish_color_comment e7c547
      set -g fish_color_cwd green
      set -g fish_color_cwd_root red
      set -g fish_color_end c397d8
      set -g fish_color_error d54e53
      set -g fish_color_escape 00a6b2
      set -g fish_color_history_current --bold
      set -g fish_color_host normal
      set -g fish_color_host_remote yellow
      set -g fish_color_match --background=brblue
      set -g fish_color_normal normal
      set -g fish_color_operator 00a6b2
      set -g fish_color_param 7aa6da
      set -g fish_color_quote b9ca4a
      set -g fish_color_redirection 70c0b1
      set -g fish_color_search_match white --background=brblack
      set -g fish_color_selection white --bold --background=brblack
      set -g fish_color_status red
      set -g fish_color_user brgreen
      set -g fish_color_valid_path --underline
      set -g fish_key_bindings fish_default_key_bindings
      set -g fish_pager_color_completion normal
      set -g fish_pager_color_description B3A06D yellow
      set -g fish_pager_color_prefix normal --bold --underline
      set -g fish_pager_color_progress brwhite --background=cyan
      set -g fish_pager_color_selected_background -r
    '';

    shellAbbrs = {
      dc = "docker compose";
      dcc = "docker compose cp";
      dcd = "docker compose cp";
      dce = "docker compose exec";
      dcu = "docker compose up";
      sf = "symfony";
      sfp = "symfony proxy:start";
      slc = "symfony console c:c && symfony console lint:cont";
      yid = "yarn install && yarn dev";
    };

    shellAliases = {
      ll = "ls -alhs";
      claude-home = "CLAUDE_CONFIG_DIR=~/.claude-home claude";
    };

    functions = {
      # Fast cd to PHP projects
      cdg = "cd $CDG_DIR/$argv";

      # sudo !! support
      sudo = {
        description = "Replacement for Bash 'sudo !!' command to run last command using sudo.";
        body = ''
          if test "$argv" = !!
            echo sudo $history[1]
            eval command sudo $history[1]
          else
            command sudo $argv
          end
        '';
      };

      # Prompt custom
      fish_prompt = builtins.readFile ./dotfiles/fish_prompt.fish;

      # Right prompt (git status + hours)
      fish_right_prompt = builtins.readFile ./dotfiles/fish_right_prompt.fish;
    };
  };

  programs.bash = {
    enable = true;

    historyControl = [ "ignoreboth" ];
    historySize = 1000;
    historyFileSize = 2000;

    shellOptions = [
      "histappend"
      "checkwinsize"
    ];

    shellAliases = {
      ll = "ls -alhs";
      la = "ls -A";
      l = "ls -CF";
      grep = "grep --color=auto";
      fgrep = "fgrep --color=auto";
      egrep = "egrep --color=auto";
    };

    sessionVariables = {
      EDITOR = "vim";
      VISUAL = "vim";
      GPG_TTY = "$(tty)";
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    includes = [ "~/.ssh/config.d/*.conf" ];

    settings = {
      nas = {
        hostname = "192.168.0.42";
        port = 9222;
        user = "truenas_admin";
      };

      "*" = {
        HostKeyAlgorithms = "+ssh-rsa";
        PubkeyAcceptedKeyTypes = "+ssh-rsa";
        # find ~ -name "*bitwarden*ssh*" 2>/dev/null
        # IdentityAgent = "~/.bitwarden-ssh-agent.sock";
        IgnoreUnknown = "AddKeysToAgent,UseKeychain";
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
      };
    };
  };

  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };
}

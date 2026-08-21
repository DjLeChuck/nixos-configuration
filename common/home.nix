{
  config,
  pkgs,
  osConfig,
  toggl-redmine,
  direnv-ide-shim,
  self,
  ...
}:

let
  variables = import ./variables.nix;
  gnomeExtensionNames = import ./gnome-extension-names.nix;
  privateToolsEnabled = variables.privateTools.enable;

  gitGlobalIgnores = [
    ".idea/"
    ".intellijPlatform/"
    "**/_akkalia.yaml"
    "**/.claude/settings.local.json"
    ".direnv/"
  ];
  # core.excludesFile patterns are always anchored at the repo root, never at
  # an absolute filesystem path, so scoping to /srv/development needs a gitdir
  # includeIf (below) pointing at this separate, superset ignore file.
  gitDevelopmentIgnoreFile = pkgs.writeText "gitignore-development" (
    pkgs.lib.concatMapStrings (pattern: pattern + "\n") gitGlobalIgnores
  );

  # https://github.com/sanduhrs/phpstorm-url-handler - lets browser links like
  # phpstorm://open?file=<path>&line=<n> (Symfony profiler, Whoops, etc.) open
  # the file directly in PhpStorm via the desktop entry + MIME association below.
  phpstormUrlHandler = pkgs.writeShellScriptBin "phpstorm-url-handler" ''
    # phpstorm://open?url=file://@file&line=@line
    # phpstorm://open?file=@file&line=@line
    # phpstorm://open?url=file://@file:@line
    # phpstorm://open?file=@file:line
    #
    # @license GPL
    # @author Stefan Auditor <stefan@auditor.email>

    function urldecode() { : "''${*//+/ }"; echo -e "''${_//%/\\x}"; }

    arg=$(urldecode "''${1}")
    pattern=".*file(:\/\/|\=)(.*)(:|&line=)(.*)"

    # Get the file path.
    file=$(echo "''${arg}" | sed -r "s/''${pattern}/\2/")

    # Get the line number.
    line=$(echo "''${arg}" | sed -r "s/''${pattern}/\4/")

    # PhpStorm's CLI only accepts --line when the first argument is a project
    # directory: since 2026.2 the launcher rejects `phpstorm --line <n> <file>`
    # outright with "unrecognized option: --line". Walk up from the file to the
    # nearest .idea/ to recover the project the file belongs to.
    project=""
    dir=$(dirname "''${file}")
    while [ -n "''${dir}" ] && [ "''${dir}" != "/" ]; do
        if [ -d "''${dir}/.idea" ]; then
            project="''${dir}"
            break
        fi
        dir=$(dirname "''${dir}")
    done

    if [ -n "''${project}" ]; then
        ${pkgs.jetbrains.phpstorm}/bin/phpstorm "''${project}" --line "''${line}" "''${file}"
    else
        # No project found: at least open the file, without jumping to the line.
        ${pkgs.jetbrains.phpstorm}/bin/phpstorm "''${file}"
    fi

    # Raising the window is best-effort: without the guard, an empty match makes
    # `wmctrl -i -a` swallow the next argument and fail.
    filename=$(basename "''${file}")
    window=$(${pkgs.wmctrl}/bin/wmctrl -l | grep -F "''${filename}" | tail -n 1 | cut -d ' ' -f1)
    if [ -n "''${window}" ]; then
        ${pkgs.wmctrl}/bin/wmctrl -i -a "''${window}"
    fi

    exit 0
  '';

  # Pushes/pulls ~/.claude/{projects,plans,CLAUDE.md,statusline.py} to the
  # shared pCloud remote configured by modules/rclone-pcloud.nix. Wired to
  # Claude Code's SessionStart/SessionEnd hooks (see ~/.claude/settings.json
  # on each machine) plus the claude-sync-push timer below as a crash safety
  # net. `--update` only overwrites older files and never deletes, since the
  # two machines are never used at the same time - a plain additive merge.
  claudeSync = pkgs.writeShellScriptBin "claude-sync" ''
    if [ "''${FLOCKED:-}" != "1" ]; then
      # Backgrounded (see the SessionStart/SessionEnd hooks in
      # ~/.claude/settings.json) syncs can now overlap - e.g. switching
      # project quickly enough that one session's detached push is still
      # running when the next one's pull starts - so wait for the lock
      # instead of dropping the sync silently on contention.
      exec env FLOCKED=1 ${pkgs.util-linux}/bin/flock -w 60 /tmp/claude-code-sync.lock "$0" "$@"
    fi

    direction="''${1:-}"
    # ~/.claude/settings.json interpolates ''${CLAUDE_PROJECT_DIR} into the
    # hook command before running it (Claude Code hooks reference), so
    # SessionStart/SessionEnd pass their project's directory as $2 here and
    # only that one project gets synced - not every project on disk, which is
    # what made each session start/stop take several seconds. Manual calls and
    # the claude-sync-push timer below omit it and get a full sync.
    target_dir="''${2:-}"
    remote="pcloud:claude-code-sync"
    local_dir="$HOME/.claude"
    opts=(--update --contimeout 5s --timeout 10s --retries 1 -q)
    failed=0

    # Claude Code keys ~/.claude/projects/<slug> off a literal transform of
    # the project's absolute path (every non-alnum char becomes "-"). Two
    # machines with different usernames get a different slug for the same
    # $HOME-rooted project (this nixos-config checkout included) and would
    # otherwise never merge. Map the local $HOME prefix to a stable,
    # machine-independent one on the remote side, and back on the way in, so
    # any $HOME-rooted project - present or future - merges the same way the
    # /srv/development-rooted ones already do.
    home_slug="$(printf '%s' "$HOME" | ${pkgs.gnused}/bin/sed -E 's/[^A-Za-z0-9]/-/g')"
    canonical_slug="-HOMESYNC"

    raw_slug() { printf '%s' "$1" | ${pkgs.gnused}/bin/sed -E 's/[^A-Za-z0-9]/-/g'; }

    remote_slug_for() {
      case "$1" in
        "$home_slug"-*) printf '%s' "$canonical_slug''${1#$home_slug}" ;;
        *) printf '%s' "$1" ;;
      esac
    }

    local_slug_for() {
      case "$1" in
        "$canonical_slug"*) printf '%s' "$home_slug''${1#$canonical_slug}" ;;
        *) printf '%s' "$1" ;;
      esac
    }

    run_rclone() {
      local out rc
      out="$(${pkgs.rclone}/bin/rclone "$@" 2>&1)"
      rc=$?
      # 3/4 = directory/file not found: expected on a first-ever sync before
      # the remote has anything yet, not a real failure.
      if [ "$rc" != 0 ] && [ "$rc" != 3 ] && [ "$rc" != 4 ]; then
        failed=1
        # Detached hook runs discard stdout/stderr (see settings.json), so this
        # is the only place a real failure's detail survives - without it,
        # notify-send's "check the journal" would point at an empty journal.
        printf 'rclone %s (exit %s):\n%s\n' "$*" "$rc" "$out" | ${pkgs.util-linux}/bin/logger -t claude-sync -p user.err
      fi
    }

    sync_one() {
      case "$1:$direction" in
        dir:pull) run_rclone copy "$remote/$2" "$local_dir/$2" "''${opts[@]}" --create-empty-src-dirs ;;
        dir:push) run_rclone copy "$local_dir/$2" "$remote/$2" "''${opts[@]}" ;;
        file:pull) run_rclone copyto "$remote/$2" "$local_dir/$2" "''${opts[@]}" ;;
        file:push) run_rclone copyto "$local_dir/$2" "$remote/$2" "''${opts[@]}" ;;
      esac
    }

    # One rclone call per project - never a bulk copy of the whole `projects`
    # tree - so a hook scoped to $target_dir only pays for listing/comparing
    # its own project instead of every project on disk.
    sync_projects() {
      case "$direction" in
        push)
          if [ -n "$target_dir" ]; then
            slug="$(raw_slug "$target_dir")"
            d="$local_dir/projects/$slug"
            [ -d "$d" ] && run_rclone copy "$d" "$remote/projects/$(remote_slug_for "$slug")" "''${opts[@]}"
          else
            for d in "$local_dir"/projects/*/; do
              [ -d "$d" ] || continue
              slug="$(${pkgs.coreutils}/bin/basename "$d")"
              run_rclone copy "$d" "$remote/projects/$(remote_slug_for "$slug")" "''${opts[@]}"
            done
          fi
          ;;
        pull)
          if [ -n "$target_dir" ]; then
            slug="$(raw_slug "$target_dir")"
            run_rclone copy "$remote/projects/$(remote_slug_for "$slug")" "$local_dir/projects/$slug" "''${opts[@]}" --create-empty-src-dirs
          else
            while IFS= read -r remote_name; do
              [ -n "$remote_name" ] || continue
              run_rclone copy "$remote/projects/$remote_name" "$local_dir/projects/$(local_slug_for "$remote_name")" "''${opts[@]}" --create-empty-src-dirs
            done < <(${pkgs.rclone}/bin/rclone lsf "$remote/projects" --dirs-only 2>/dev/null | ${pkgs.gnused}/bin/sed 's:/$::')
          fi
          ;;
      esac
    }

    case "$direction" in
      pull|push)
        sync_projects
        sync_one dir plans
        sync_one file CLAUDE.md
        sync_one file statusline.py
        ;;
      *)
        echo "usage: claude-sync {pull|push} [project-dir]" >&2
        exit 1
        ;;
    esac

    if [ "$failed" = 1 ]; then
      if [ -n "$target_dir" ]; then
        label="$(${pkgs.coreutils}/bin/basename "$target_dir")"
      else
        label="all projects"
      fi
      ${pkgs.libnotify}/bin/notify-send -u critical "Claude Code sync" "Sync ($direction, $label) failed - journalctl -t claude-sync"
    fi
  '';

in
{
  home.stateVersion = "26.05";

  home.packages =
    with pkgs;
    [
      bitwarden-desktop
      bitwarden-cli
      brave
      claudeSync
      gawk
      gimp
      gitflow
      jetbrains.goland
      jetbrains.phpstorm
      jpegoptim
      jq
      k6
      libreoffice
      libwebp
      mattermost-desktop
      meld
      nixd
      nixfmt
      phpstormUrlHandler
      pngquant
      postman
      rclone
      signal-desktop
      spotify
      symfony-cli
      toggl-redmine.packages.${pkgs.stdenv.hostPlatform.system}.default
      direnv-ide-shim.packages.${pkgs.stdenv.hostPlatform.system}.default
      tree
      trivy
      vlc
      wmctrl
    ]
    ++ pkgs.lib.optionals privateToolsEnabled [
      self.packages.${pkgs.stdenv.hostPlatform.system}.lock-excel
      self.packages.${pkgs.stdenv.hostPlatform.system}.excel2jsonl
    ];

  xdg.configFile."fish/completions/cdg.fish".text = ''
    complete -c cdg -f -a "(path basename $CDG_DIR/*/)"
  '';

  # Composer only recognizes gitlab.com as a GitLab host by default; we are
  # adding custom one here, forcing https.
  xdg.configFile."composer/config.json".text = builtins.toJSON {
    config = {
      gitlab-domains = [ variables.privateTools.gitlabHost ];
      gitlab-protocol = "https";
    };
  };

  # Written by hand instead of via `xdg.desktopEntries`: that module is
  # broken on the pinned home-manager release (it always sets the removed
  # `extraConfig` option internally - https://github.com/nix-community/home-manager,
  # modules/misc/xdg-desktop-entries.nix - and errors on any entry).
  xdg.dataFile."applications/phpstorm-url-handler.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=PhpStorm URL Handler
    Comment=Handle URL Scheme phpstorm://open?url=file://@file&line=@line and phpstorm://open?file=@file&line=@line
    Icon=phpstorm
    NoDisplay=true
    Categories=TextEditor;Utility;
    Exec=phpstorm-url-handler %u
    Terminal=false
    MimeType=x-scheme-handler/phpstorm;x-scheme-handler/pstorm;x-scheme-handler/txmt;
  '';

  # Overrides the package's own Mattermost.desktop (same filename, so it
  # shadows it) to add StartupWMClass: recent Electron versions changed the
  # window's WM_CLASS to "Mattermost.Desktop", and without this GNOME Shell
  # can't match the running window back to this app, so the dock/taskbar
  # falls back to a generic "icon not found" placeholder.
  xdg.dataFile."applications/Mattermost.desktop".text = ''
    [Desktop Entry]
    Name=Mattermost
    Comment=Mattermost Desktop application for Linux
    Exec="${pkgs.mattermost-desktop}/bin/mattermost-desktop" %U
    Terminal=false
    Type=Application
    MimeType=x-scheme-handler/mattermost
    Icon=mattermost-desktop
    Categories=Network;InstantMessaging;
    StartupWMClass=Mattermost.Desktop
  '';

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/phpstorm" = "phpstorm-url-handler.desktop";
      "x-scheme-handler/pstorm" = "phpstorm-url-handler.desktop";
      "x-scheme-handler/txmt" = "phpstorm-url-handler.desktop";
    };
  };

  # mimeapps.list/xdg-mime are correct as soon as it's written, but GNOME's
  # own app-chooser (what the browser's URL-open portal call goes through)
  # reads applications/mimeinfo.cache instead, which is only ever rebuilt by
  # this command - without it, new scheme handlers silently show as "no app
  # available" until something else happens to trigger the rebuild.
  home.activation.updateDesktopDatabase = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database $VERBOSE_ARG "${config.xdg.dataHome}/applications"
  '';

  dconf.settings = {
    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions =
        (map (name: pkgs.gnomeExtensions.${name}.extensionUuid) (
          gnomeExtensionNames ++ osConfig.custom.gnomeExtensionNames
        ))
        ++ [ self.packages.${pkgs.stdenv.hostPlatform.system}.openvpn3-switcher.extensionUuid ];
      always-show-log-out = true;
    };

    "system/proxy" = {
      mode = "auto";
      autoconfig-url = "http://127.0.0.1:7080/proxy.pac";
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
      num-workspaces = 1;
    };

    "org/gnome/desktop/wm/keybindings" = {
      begin-move = [ ];
    };

    "org/gnome/desktop/sound" = {
      event-sounds = false;
      theme-name = "__custom";
    };

    "org/gnome/desktop/interface" = {
      enable-hot-corners = false;
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = false;
    };

    "org/gnome/nautilus/preferences" = {
      default-folder-viewer = "list-view";
    };

    "org/gnome/nautilus/list-view" = {
      default-zoom-level = "small";
      use-tree-view = true;
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      running-indicator-style = "DOTS";
      click-action = "focus-or-appspread";
      dock-position = "LEFT";
      extend-height = true;
      intellihide = false;
      autohide = false;
    };
  };

  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  systemd.user.services.symfony-proxy = {
    Unit.Description = "Symfony CLI local proxy";

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.symfony-cli}/bin/symfony proxy:start";
      ExecStop = "${pkgs.symfony-cli}/bin/symfony proxy:stop";
    };

    Install.WantedBy = [ "default.target" ];
  };

  # Nix flakes have no per-package update notifications like apt/GNOME
  # Software: every installed program comes from whichever nixpkgs commit is
  # pinned in flake.lock, so "updates" only exist relative to that pin (and
  # the other flake inputs: home-manager, sops-nix, foundryvtt, claude-code).
  # This periodically compares each input's locked rev to its remote branch
  # HEAD and nudges via a desktop notification when any have diverged.
  systemd.user.services.nixpkgs-update-check = {
    Unit.Description = "Check for available flake input updates";

    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nixpkgs-update-check" ''
        set -euo pipefail

        flake_dir="$HOME/.config/nixos-config"
        outdated=()

        while IFS=$'\t' read -r name owner repo rev ref; do
          if [ "$ref" = "HEAD" ]; then
            query="HEAD"
          else
            query="refs/heads/$ref"
          fi

          latest=$(${pkgs.git}/bin/git ls-remote "https://github.com/$owner/$repo" "$query" | cut -f1)

          if [ -n "$latest" ] && [ "$latest" != "$rev" ]; then
            outdated+=("$name")
          fi
        done < <(${pkgs.jq}/bin/jq -r '
          .nodes as $nodes
          | $nodes.root.inputs
          | to_entries[]
          | .key as $name
          | $nodes[.value].locked as $l
          | select($l.type == "github")
          | [$name, $l.owner, $l.repo, $l.rev, ($nodes[.value].original.ref // "HEAD")]
          | @tsv
        ' "$flake_dir/flake.lock")

        if [ ''${#outdated[@]} -gt 0 ]; then
          ${pkgs.libnotify}/bin/notify-send \
            --icon=software-update-available \
            "Mise à jour NixOS disponible" \
            "Inputs en retard : ''${outdated[*]}. Lancer : nh os switch -u"
        fi
      '';
    };
  };

  systemd.user.timers.nixpkgs-update-check = {
    Unit.Description = "Daily check for available flake input updates";

    Timer = {
      OnCalendar = [
        "*-*-* 09:30:00"
        "*-*-* 14:30:00"
      ];
      Persistent = true;
    };

    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.claude-sync-push = {
    Unit.Description = "Push Claude Code conversations/plans/CLAUDE.md to pCloud";

    Service = {
      Type = "oneshot";
      ExecStart = "${claudeSync}/bin/claude-sync push";
    };
  };

  # Claude Code's own SessionEnd hook already pushes on clean exit; this timer
  # is the fallback for crashes/kill -9, where SessionEnd never fires -
  # bounds how much unsynced work a crash can lose to ~3h.
  systemd.user.timers.claude-sync-push = {
    Unit.Description = "Periodic Claude Code sync safety net";

    Timer = {
      OnStartupSec = "5m";
      OnUnitActiveSec = "3h";
    };

    Install.WantedBy = [ "timers.target" ];
  };

  programs.ghostty = {
    enable = true;

    settings = {
      background-opacity = 0.9;
    };
  };

  programs.zed-editor = {
    enable = true;
    extensions = [ "nix" ];
    extraPackages = [ pkgs.nixd ];

    userSettings = {
      cli_default_open_behavior = "new_window";
      project_panel.dock = "left";
      autosave = "on_focus_change";
      ui_font_size = 16;
      buffer_font_size = 15;
      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };
      # The "nix" extension registers both nil and nixd; nixd is picked
      # explicitly for its flake-aware eval-based completion/hover.
      languages.Nix.language_servers = [
        "nixd"
        "!nil"
      ];
      lsp.nixd.binary.path = "${pkgs.nixd}/bin/nixd";
    };
  };

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

      tag.gpgSign = false;

      pull.rebase = false;
      fetch.prune = true;
      init.defaultBranch = "main";
      rerere.enabled = true;
      lfs.locksverify = true;

      credential.helper = "${pkgs.gitFull}/bin/git-credential-libsecret";

      alias = {
        di = "diff -D";
        co = "checkout";
        st = "status -s";
        files = "!sh -c 'git diff-tree --no-commit-id --name-only -r $0'";
        amend = "commit --amend";
        ignore = "!sh -c 'git ls-files -z $0 | xargs -0 git update-index --skip-worktree'";
        unignore = "!sh -c 'git ls-files -z $0 | xargs -0 git update-index --no-skip-worktree'";
        ignored = ''!git ls-files -v | grep "^S"'';
      };
    };

    includes = [
      {
        condition = "gitdir:/srv/development/php/";
        contents = {
          user = {
            email = "vdebona@umanit.fr";
            name = "Vivien DE BONA";
          };
        };
      }
      {
        condition = "gitdir:/srv/development/php/perso/";
        contents = {
          user = {
            email = "djlechuck@gmail.com";
            name = "DjLeChuck";
          };
        };
      }
      {
        condition = "gitdir:/srv/development/**";
        contents.core.excludesFile = "${gitDevelopmentIgnoreFile}";
      }
    ];

    ignores = gitGlobalIgnores;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = true;

    config = {
      global.hide_env_diff = true;
      whitelist.prefix = [ "/srv/development" ];
    };
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = pkgs.lib.mkMerge [
      (pkgs.lib.mkBefore ''
        # NIXOS_CONFIG_DIR must be set before any other interactiveShellInit
        # runs, since machine-specific snippets (e.g. NH_OS_FLAKE) expand it
        # immediately - mkBefore pins this ahead regardless of module order.
        set -gx NIXOS_CONFIG_DIR ~/.config/nixos-config
        set -gx NH_FLAKE $NIXOS_CONFIG_DIR
      '')
      ''
        # Remove greeting message
        set -g fish_greeting

        # Global variables
        set -gx EDITOR vim
        set -gx CDG_DIR /srv/development/php
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
      ''
    ];

    shellAbbrs = {
      dc = "docker compose";
      dcc = "docker compose cp";
      dcd = "docker compose down";
      dce = "docker compose exec";
      dcu = "docker compose up";
      sfc = "php bin/console";
      sfp = "symfony proxy:start";
      sfs = "symfony serve";
      yid = "yarn install && yarn dev";
    };

    shellAliases = {
      ll = "ls -alhs";
      cc = "claude";
    };

    functions = {
      # Fast cd to PHP projects
      cdg = "cd $CDG_DIR/$argv";

      # Set up (or refresh) the shared PHP dev shell in the current directory.
      # The actual flake.nix lives only in $NIXOS_CONFIG_DIR/templates/php
      # and is referenced from there via an impure flake path, so the only
      # file ever placed in the project is .envrc — which direnv reads
      # straight off disk and Nix never needs, so it never needs `git add`,
      # never shows up in `git status`, and never has to be committed.
      phpinit = {
        description = "Set up (or refresh) the shared PHP dev shell in the current directory";
        body = ''
          cp $NIXOS_CONFIG_DIR/templates/php/.envrc ./.envrc
          direnv allow
        '';
      };

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
      nas = variables.nas;

      "*" = {
        HostKeyAlgorithms = "+ssh-rsa";
        PubkeyAcceptedKeyTypes = "+ssh-rsa";
        IdentityAgent = "~/.bitwarden-ssh-agent.sock";
        IgnoreUnknown = "AddKeysToAgent,UseKeychain";
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
        # Ghostty's default TERM (xterm-ghostty) has no terminfo entry on
        # most remote servers, breaking color/formatting in anything
        # terminfo-based (vim, tmux, less -R, htop...). Override just what's
        # sent to the server; local Ghostty sessions keep their real TERM.
        SetEnv.TERM = "xterm-256color";
      };
    };
  };

  # ~/.ssh/config.d is intentionally left unmanaged above (see `includes`):
  # its content lives in a private git repo. Clone it once over HTTPS using
  # the sops-provided token; the token ends up in that clone's local
  # .git/config, so later updates are just a manual `git pull` in there - no
  # auto-pull on every switch. On the very first switch the token may not be
  # decrypted yet (see README), so this skips instead of failing.
  #
  # `-c credential.helper=` disables the credential helper for this clone and
  # (per `git clone`'s documented behavior) persists that empty value into the
  # new repo's local .git/config. Without it, git still calls the configured
  # helper's "store" step after a successful URL-embedded auth, and since
  # `credential.helper` below is global (libsecret) and keyed by host, that
  # silently overwrote the personal dev token for this same GitLab host.
  home.activation.cloneSshConfigPrivate = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    tokenFile="/run/secrets/ssh-config-private-token"
    target="${config.home.homeDirectory}/.ssh/config.d"
    repoUrl="${variables.sshConfigPrivate.repoPath}"

    if [ -d "$target/.git" ]; then
      :
    elif [ ! -f "$tokenFile" ]; then
      echo "ssh-config-private: secret not yet decrypted, skipping clone (retry after next switch)"
    else
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
        -c credential.helper= \
        "https://oauth2:$(cat "$tokenFile")@''${repoUrl#https://}" \
        "$target"
    fi
  '';

  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
    SSH_AUTH_SOCK = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
    # claude-code's nix wrapper hardcodes DISABLE_AUTOUPDATER=1, which also
    # silently disables plugin auto-updates; this re-enables just those.
    FORCE_AUTOUPDATE_PLUGINS = "1";
  };

  programs.mise = {
    enable = true;
    enableFishIntegration = true;

    globalConfig = {
      settings = {
        all_compile = false;
        node.compile = false;
        trusted_config_paths = [ "/srv/development" ];
      };
    };
  };
}

# symfony-cli caches its PHP-version discovery in a machine-global
# ~/.config/symfony-cli/php_versions.json with no staleness check against the
# current $PATH. `symfony php`/`symfony console` (local/php/executor.go,
# Executor.Config) look up PHP with forceReload=false first and only retry
# with forceReload=true if that lookup returns an error - a stale cache entry
# from a different, previously-active project/terminal doesn't error, so the
# reload path never triggers and the wrong PHP binary silently gets used.
# `symfony serve`/`local:php:list`/`local:php:refresh` already hardcode
# forceReload=true and are unaffected. This forces the same always-reload
# behavior for the `php`/`console` codepath.
# Upstream: https://github.com/symfony-cli/symfony-cli/blob/v5.17.1/local/php/executor.go#L219
final: prev: {
  symfony-cli = prev.symfony-cli.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace local/php/executor.go \
        --replace-fail 'e.lookupPHP(cliDir, false)' 'e.lookupPHP(cliDir, true)'
    '';
  });
}

HOSTS := home work vm-home vm-work

.PHONY: help status checklist vars-check sops-refs
.DEFAULT_GOAL := help

help:
	@echo "Bootstrap/reinstall checklist tool (read-only, no target mutates anything)"
	@echo ""
	@echo "  make status                     Show automatic checks for all hosts"
	@echo "  make checklist HOST=<name>      Full step-by-step checklist for one host"
	@echo "  make vars-check                 Structural check of common/variables.nix"
	@echo "  make sops-refs HOST=<name>      List secrets referencing this host in .sops.yaml"
	@echo ""
	@echo "Valid HOST values: $(HOSTS)"

status:
	@printf "%-10s %-22s %-16s %-24s\n" "HOST" "hardware-config.nix" "in nixos-hosts.nix" "age key in .sops.yaml"
	@for h in $(HOSTS); do \
		hw="MISSING"; test -f machines/$$h/hardware-configuration.nix && hw="OK"; \
		fl="MISSING"; grep -qE "^[[:space:]]+$$h = mkHost" flake-modules/nixos-hosts.nix && fl="OK"; \
		anchor="host_$$(echo $$h | tr '-' '_')"; \
		line=$$(grep -E "^[[:space:]]*-[[:space:]]*&$${anchor}[[:space:]]" .sops.yaml); \
		if [ -z "$$line" ]; then age="MISSING (commented out)"; \
		elif echo "$$line" | grep -q TODO_REPLACE; then age="PLACEHOLDER (needs real key)"; \
		else age="OK"; fi; \
		printf "%-10s %-22s %-16s %-24s\n" "$$h" "$$hw" "$$fl" "$$age"; \
	done
	@echo ""
	@echo "Not auto-verifiable (always manual): common/variables.nix real values, GPG key import,"
	@echo "private-tools token, ssh-config-private token. See 'make checklist HOST=<name>'."

checklist:
	@if [ -z "$(HOST)" ]; then \
		echo "Usage: make checklist HOST=<name>"; \
		echo "Valid hosts: $(HOSTS)"; \
		echo ""; \
		$(MAKE) --no-print-directory status; \
		exit 1; \
	fi
	@case " $(HOSTS) " in *" $(HOST) "*) ;; *) echo "Unknown HOST '$(HOST)'. Valid: $(HOSTS)"; exit 1;; esac
	@anchor="host_$$(echo $(HOST) | tr '-' '_')"; \
	echo "==================================================================="; \
	echo " Bootstrap checklist for host: $(HOST)"; \
	echo "==================================================================="; \
	echo ""; \
	echo "1) Hardware configuration"; \
	if test -f machines/$(HOST)/hardware-configuration.nix; then \
		echo "   [DONE] machines/$(HOST)/hardware-configuration.nix exists"; \
	else \
		echo "   [TODO] Generate it on the target machine, then copy it in manually:"; \
		echo "          sudo nixos-generate-config --show-hardware-config \\"; \
		echo "            > machines/$(HOST)/hardware-configuration.nix"; \
	fi; \
	echo ""; \
	echo "2) flake-modules/nixos-hosts.nix registration"; \
	if grep -qE "^[[:space:]]+$(HOST) = mkHost" flake-modules/nixos-hosts.nix; then \
		echo "   [DONE] '$(HOST)' has a mkHost block in flake-modules/nixos-hosts.nix"; \
	else \
		echo "   [TODO] Add a '$(HOST) = mkHost { ... }' block to flake-modules/nixos-hosts.nix"; \
		echo "          (copy the shape of an existing host block as a template)"; \
	fi; \
	echo ""; \
	echo "3) Age key + .sops.yaml"; \
	line=$$(grep -E "^[[:space:]]*-[[:space:]]*&$${anchor}[[:space:]]" .sops.yaml); \
	if [ -n "$$line" ] && ! echo "$$line" | grep -q TODO_REPLACE; then \
		echo "   [DONE] &$${anchor} anchor is active with a real key in .sops.yaml"; \
	else \
		echo "   [TODO] On the target machine, after first (partial) rebuild, get its host age key:"; \
		echo "          nix run github:Mic92/ssh-to-age -- < /etc/ssh/ssh_host_ed25519_key.pub"; \
		echo "          (or read it from /var/lib/sops-nix/key.txt / the host's sops-nix setup)"; \
		echo "          Then in .sops.yaml: uncomment and fill '&$${anchor} age1...' with the real key."; \
	fi; \
	echo ""; \
	echo "4) Re-encrypt affected secrets (manual, after step 3 is really done)"; \
	$(MAKE) --no-print-directory sops-refs HOST=$(HOST); \
	echo "   [TODO] For each file above, once its key_groups line for $(HOST) is uncommented,"; \
	echo "          run:  sops updatekeys secrets/<file>"; \
	echo "          (do NOT run this automatically here; it mutates the encrypted files)"; \
	echo ""; \
	echo "5) common/variables.nix (local-only, skip-worktree)"; \
	$(MAKE) --no-print-directory vars-check; \
	echo "  [TODO] Review every field above for values specific to '$(HOST)' (NAS/Wi-Fi/dev path/"; \
	echo "          private tool URLs+hashes/ssh-config-private repo)."; \
	echo ""; \
	echo "6) One-time manual steps from README.md (run only what applies to this host)"; \
	echo "   - GPG key: gpg --export-secret-keys --armor <KEY_ID> > secrets/gpg/private-key.asc"; \
	echo "              sops --encrypt --in-place secrets/gpg/private-key.asc"; \
	echo "              (then, post-switch: gpg --batch --import /run/secrets/gpg-private-key)"; \
	echo "   - Private GitLab tools token: sops secrets/private-tools.yaml"; \
	echo "   - Private ssh-config token:   sops secrets/ssh-config-private.yaml"; \
	echo "   - Then: sudo nixos-rebuild switch --flake .#$(HOST)  (run twice for token bootstrap, see README)"; \
	echo ""; \
	echo "==================================================================="

vars-check:
	@echo "common/variables.nix structural check:"
	@if [ ! -f common/variables.nix ]; then \
		echo "  [MISSING] common/variables.nix does not exist on disk"; \
	else \
		for key in nas wifi development privateTools sshConfigPrivate; do \
			if grep -qE "^[[:space:]]*$${key}[[:space:]]*=" common/variables.nix; then \
				echo "  [OK]      $$key"; \
			else \
				echo "  [MISSING] $$key"; \
			fi; \
		done; \
		if ! grep -qE "^[[:space:]]*enable[[:space:]]*=" common/variables.nix; then \
			echo "  [MISSING] privateTools.enable - required key, add it (see README)"; \
		elif grep -qE "^[[:space:]]*enable[[:space:]]*=[[:space:]]*true" common/variables.nix; then \
			echo "  [OK]      privateTools.enable = true"; \
		else \
			echo "  [OFF]     privateTools.enable = false - lock-excel/excel2jsonl won't be built"; \
			echo "            (expected until the real URLs/sha256/token are set up, see README)"; \
		fi; \
	fi

# Best-effort line scanner over .sops.yaml, not a real YAML parser.
sops-refs:
	@if [ -z "$(HOST)" ]; then echo "Usage: make sops-refs HOST=<name>"; exit 1; fi
	@anchor="host_$$(echo $(HOST) | tr '-' '_')"; \
	echo "   Secrets referencing $${anchor} in .sops.yaml creation_rules:"; \
	awk -v anchor="$$anchor" ' \
		/path_regex:/ { rule=$$0; sub(/^[^:]*:[[:space:]]*/, "", rule) } \
		$$0 ~ ("\\*" anchor "([^A-Za-z0-9_]|$$)") { \
			commented = ($$0 ~ /^[[:space:]]*#/) ? "commented-out (needs uncommenting)" : "active"; \
			printf "     - %-40s %s\n", rule, commented; \
		} \
	' .sops.yaml

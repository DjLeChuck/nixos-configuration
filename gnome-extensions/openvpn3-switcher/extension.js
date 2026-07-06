import GObject from "gi://GObject";
import Gio from "gi://Gio";
import St from "gi://St";

import {
  Extension,
  gettext as _,
} from "resource:///org/gnome/shell/extensions/extension.js";
import * as PanelMenu from "resource:///org/gnome/shell/ui/panelMenu.js";
import * as PopupMenu from "resource:///org/gnome/shell/ui/popupMenu.js";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

Gio._promisify(
  Gio.Subprocess.prototype,
  "communicate_utf8_async",
  "communicate_utf8_finish",
);

const ICON_CONNECTED = "network-vpn-symbolic";
const ICON_PENDING = "network-vpn-acquiring-symbolic";
const ICON_DISCONNECTED = "network-vpn-disabled-symbolic";

async function runOpenvpn3(args) {
  const proc = Gio.Subprocess.new(
    ["openvpn3", ...args],
    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
  );
  const [stdout, stderr] = await proc.communicate_utf8_async(null, null);
  return { ok: proc.get_successful(), stdout, stderr };
}

async function listConfigNames() {
  const { ok, stdout, stderr } = await runOpenvpn3(["configs-list", "--json"]);
  if (!ok) {
    logError(new Error(stderr), "openvpn3 configs-list failed");
    return [];
  }
  try {
    return Object.values(JSON.parse(stdout))
      .map((c) => c.name)
      .sort();
  } catch (e) {
    logError(e, "openvpn3 configs-list --json returned invalid JSON");
    return [];
  }
}

// sessions-list has no --json output. Its text format is a series of blocks
// separated by dashed lines, each with a "Config name:" and a "Status:"
// line. Parsing per block (rather than testing substrings on the raw text)
// avoids false matches between config names that share a common prefix.
async function getSessionStatuses() {
  const { ok, stdout } = await runOpenvpn3(["sessions-list"]);
  const statuses = new Map();
  if (!ok) return statuses;

  for (const block of stdout.split(/^-{5,}$/m)) {
    const nameMatch = block.match(/^\s*Config name:\s*(.+)$/m);
    if (!nameMatch) continue;
    const statusMatch = block.match(/^\s*Status:\s*(.+)$/m);
    statuses.set(nameMatch[1].trim(), statusMatch ? statusMatch[1].trim() : "");
  }
  return statuses;
}

function isConnected(status) {
  return status.includes("Client connected");
}

// Right after session-start, the backend needs a moment to reach the auth
// server before the URL becomes available, so this polls briefly instead of
// checking just once.
async function waitForAuthUrl(name, { attempts = 5, intervalMs = 1000 } = {}) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const { ok, stdout } = await runOpenvpn3(["session-auth"]);
    if (ok) {
      for (const block of stdout.split(/^-{5,}$/m)) {
        const nameMatch = block.match(/^\s*Config name:\s*(.+)$/m);
        if (!nameMatch || nameMatch[1].trim() !== name) continue;
        const urlMatch = block.match(/^\s*Auth URL:\s*(\S+)$/m);
        if (urlMatch) return urlMatch[1].trim();
      }
    }
    if (attempt < attempts - 1)
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return null;
}

function openUrl(url) {
  try {
    Gio.AppInfo.launch_default_for_uri(url, null);
  } catch (e) {
    logError(e, `openvpn3-switcher: failed to open auth URL ${url}`);
  }
}

const OpenVPN3Indicator = GObject.registerClass(
  class OpenVPN3Indicator extends PanelMenu.Button {
    _init() {
      super._init(0.5, "OpenVPN3 Switcher", false);

      this._busy = false;
      this._icon = new St.Icon({
        icon_name: ICON_DISCONNECTED,
        style_class: "system-status-icon",
      });
      // A .system-status-icon added directly to a panel button gets extra
      // padding/margin meant for a lone icon; wrapping it in the same
      // indicators box the built-in indicators use keeps its rendered size
      // in line with them.
      const box = new St.BoxLayout({ style_class: "panel-status-indicators-box" });
      box.add_child(this._icon);
      this.add_child(box);

      // PopupMenu.open() is a no-op while the menu has zero items, so it
      // must never start empty or it could never open at all.
      this.menu.addMenuItem(
        new PopupMenu.PopupMenuItem(_("Loading…"), { reactive: false }),
      );

      this.menu.connect("open-state-changed", (menu, open) => {
        if (open)
          this._refresh().catch((e) =>
            logError(e, "openvpn3-switcher refresh failed"),
          );
      });
    }

    async _refresh() {
      this.menu.removeAll();
      const names = await listConfigNames();
      const statuses = await getSessionStatuses();

      const connectedNames = names.filter((name) =>
        isConnected(statuses.get(name) ?? ""),
      );
      const pendingNames = names.filter(
        (name) => statuses.has(name) && !isConnected(statuses.get(name)),
      );

      this._icon.icon_name =
        connectedNames.length > 0
          ? ICON_CONNECTED
          : pendingNames.length > 0
            ? ICON_PENDING
            : ICON_DISCONNECTED;

      if (names.length === 0) {
        this.menu.addMenuItem(
          new PopupMenu.PopupMenuItem(_("No openvpn3 config found"), {
            reactive: false,
          }),
        );
        return;
      }

      for (const name of names) {
        const status = statuses.get(name);
        const connected = isConnected(status ?? "");
        const label = status && !connected ? `${name} (${_("Pending")})` : name;

        const item = new PopupMenu.PopupMenuItem(label);
        if (connected) item.setOrnament(PopupMenu.Ornament.CHECK);
        else if (status) item.setOrnament(PopupMenu.Ornament.DOT);
        item.connect("activate", () => this._switchTo(name, statuses));
        this.menu.addMenuItem(item);
      }

      if (statuses.size > 0) {
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const disconnectItem = new PopupMenu.PopupMenuItem(_("Disconnect"));
        disconnectItem.connect("activate", () => this._disconnectAll(statuses));
        this.menu.addMenuItem(disconnectItem);
      }
    }

    async _switchTo(targetName, statuses) {
      if (this._busy) return;
      if (isConnected(statuses.get(targetName) ?? "")) return;

      this._busy = true;
      try {
        for (const name of statuses.keys())
          await runOpenvpn3([
            "session-manage",
            "--config",
            name,
            "--disconnect",
          ]);

        const { ok, stderr } = await runOpenvpn3([
          "session-start",
          "--config",
          targetName,
          "--background",
        ]);
        if (!ok) {
          logError(
            new Error(stderr),
            `openvpn3 session-start failed for ${targetName}`,
          );
        } else {
          // Give instant feedback rather than waiting for the full refresh
          // below, which can take a few seconds while polling for the auth URL.
          this._icon.icon_name = ICON_PENDING;
          const authUrl = await waitForAuthUrl(targetName);
          if (authUrl) openUrl(authUrl);
        }
      } finally {
        this._busy = false;
        await this._refresh();
      }
    }

    async _disconnectAll(statuses) {
      if (this._busy) return;
      this._busy = true;
      try {
        for (const name of statuses.keys())
          await runOpenvpn3([
            "session-manage",
            "--config",
            name,
            "--disconnect",
          ]);
      } finally {
        this._busy = false;
        await this._refresh();
      }
    }
  },
);

export default class OpenVPN3SwitcherExtension extends Extension {
  enable() {
    this._indicator = new OpenVPN3Indicator();
    Main.panel.addToStatusArea(this.uuid, this._indicator);
  }

  disable() {
    this._indicator?.destroy();
    this._indicator = null;
  }
}

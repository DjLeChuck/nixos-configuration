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
// While a session is pending (auth started but not yet "Client connected"),
// poll fast so the icon updates without the user reopening the menu. Once
// connected, polling only needs to watch for an unexpected drop, so it can
// run much less often.
const PENDING_POLL_INTERVAL_MS = 3000;
const CONNECTED_POLL_INTERVAL_MS = 30000;
// GNOME Shell 50.2's message tray has a bug where firing two notifications
// in the same tick can throw inside its internal state machine and
// permanently jam banner display until the next Shell restart. Staggering
// avoids ever calling Main.notify() twice in one synchronous pass.
const NOTIFY_STAGGER_MS = 500;

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
      this._pollTimerId = null;
      this._pollIntervalMs = null;
      // Baseline session status from the previous refresh, used to detect
      // connect/disconnect transitions worth notifying about. null means
      // "no baseline yet" so the first-ever refresh never notifies on
      // whatever state already existed before the extension enabled.
      this._knownStatus = null;
      this._refreshing = false;
      this._refreshQueued = false;
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

      this.connect("destroy", () => this._stopPolling());
    }

    // Thin wrapper serializing concurrent calls: _doRefresh() spans multiple
    // awaits (two subprocess round trips) and is called from several places
    // (menu open, end of _switchTo/_disconnectAll, and the poll timer) that
    // can now overlap for the entire lifetime of a connection rather than
    // just a brief window, so two overlapping runs could otherwise write
    // this._knownStatus out of order and fire a wrong notification. Queueing
    // a single follow-up run (rather than dropping the request) still
    // guarantees callers like _switchTo's `finally` get a fresh render.
    async _refresh() {
      if (this._refreshing) {
        this._refreshQueued = true;
        return;
      }
      this._refreshing = true;
      try {
        await this._doRefresh();
      } finally {
        this._refreshing = false;
        if (this._refreshQueued) {
          this._refreshQueued = false;
          this._refresh();
        }
      }
    }

    async _doRefresh() {
      this.menu.removeAll();
      const names = await listConfigNames();
      const statuses = await getSessionStatuses();

      const oldStatus = this._knownStatus;
      this._knownStatus = statuses;
      if (oldStatus !== null) {
        const allNames = new Set([...oldStatus.keys(), ...statuses.keys()]);
        const pendingNotifications = [];
        for (const name of allNames) {
          const was = isConnected(oldStatus.get(name) ?? "");
          const now = isConnected(statuses.get(name) ?? "");
          if (!was && now) pendingNotifications.push([_("VPN connected"), name]);
          else if (was && !now)
            pendingNotifications.push([_("VPN disconnected"), name]);
        }
        pendingNotifications.forEach(([title, body], i) => {
          setTimeout(() => Main.notify(title, body), i * NOTIFY_STAGGER_MS);
        });
      }

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

      // Keep polling only while something is genuinely in-flight; every other
      // call site (menu open, end of _switchTo/_disconnectAll) already calls
      // _refresh(), so this is the single place that decides start vs. stop.
      // Fast while pending (auth window, responsiveness matters), slow once
      // fully connected (just watching for a drop).
      if (pendingNames.length > 0)
        this._startPolling(PENDING_POLL_INTERVAL_MS);
      else if (connectedNames.length > 0)
        this._startPolling(CONNECTED_POLL_INTERVAL_MS);
      else this._stopPolling();

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

    _startPolling(intervalMs) {
      if (this._pollTimerId !== null && this._pollIntervalMs === intervalMs)
        return;
      this._stopPolling();
      this._pollIntervalMs = intervalMs;
      this._pollTimerId = setInterval(() => {
        this._refresh().catch((e) =>
          logError(e, "openvpn3-switcher poll refresh failed"),
        );
      }, intervalMs);
    }

    _stopPolling() {
      if (this._pollTimerId === null) return;
      clearInterval(this._pollTimerId);
      this._pollTimerId = null;
      this._pollIntervalMs = null;
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
          Main.notify(_("VPN connection failed"), targetName);
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

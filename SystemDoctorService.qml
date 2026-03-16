pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Public metrics ---
    property real cpuPct: 0
    property real ramPct: 0
    property int ramUsedMb: 0
    property int ramTotalMb: 0
    property real diskPct: 0
    property real tempC: -1
    property var topProcs: []
    property var logErrors: []

    // --- GPU metrics (throttled ~15s) ---
    property bool gpuAvailable: false
    property real gpuPct: 0
    property int gpuVramUsedMb: 0
    property int gpuVramTotalMb: 0
    property real gpuTempC: -1

    // --- Pending updates (apt/dnf/pacman/brew/choco) ---
    property string updateManager: ""       // "apt" | "dnf" | "pacman" | "brew" | "choco" | ""
    property int updateCount: 0
    property int updateSecurity: 0
    property int updateBugfix: 0
    property int updateFeature: 0
    property string updateEtaLabel: ""      // e.g. "~5 min" or ""
    property bool updateInProgress: false
    property real updateProgressPct: 0
    property string updateProgressLabel: ""

    // --- Health state (includes reason for status pill) ---
    property int healthScore: 100
    property string healthLabel: "Good"
    property string healthIcon: "monitor_heart"
    property string healthReason: ""        // Short text: "CPU high" / "RAM high" / ""

    // --- Thresholds and AI config (written by plugin settings handler) ---
    property int cpuThreshold: 85
    property int ramThreshold: 85
    property int diskThreshold: 90
    property string ollamaModel: "llama3.2"
    property bool useAdaptiveThresholds: true
    property int adaptiveHistorySize: 20   // samples for baseline

    // --- Adaptive baseline (rolling history for smart thresholds) ---
    property var _cpuHistory: []
    property var _ramHistory: []
    property var _diskHistory: []

    // --- Safe-mode prechecks ---
    property real freeSpaceGb: 0
    property bool onBattery: false
    property bool snapshotAvailable: false
    property string snapshotProvider: ""   // "timeshift" | "btrfs" | "zfs" | "apfs" | "restorepoint" | ""

    // --- Snapshot/restore ---
    property string lastSnapshotId: ""
    property bool restoreSuggested: false   // set true if post-action anomalies detected

    // --- CPU delta tracking ---
    property real _prevTotal: 0
    property real _prevIdle: 0

    // --- UI throttle: 1s for displayed values (from cache), 5s full metrics ---
    property int _lightIntervalMs: 1000
    property int _heavyIntervalMs: 5000
    property int _gpuIntervalMs: 15000
    property int _updateCheckIntervalMs: 60000

    // --- Initialization ---
    Component.onCompleted: {
        console.log("DankSystemDoctor: Service started");
        refreshMetrics();
        Qt.callLater(refreshLogs);
        Qt.callLater(refreshGpu);
        Qt.callLater(refreshUpdates);
        Qt.callLater(refreshPrechecks);
        Qt.callLater(detectSnapshotProvider);
    }

    Component.onDestruction: {
        console.log("DankSystemDoctor: Service stopped");
    }

    // --- Metric polling: light (1s) only updates UI-bound cached values from last full read ---
    Timer {
        interval: root._lightIntervalMs
        repeat: true
        running: true
        onTriggered: { /* UI can bind to cpuPct/ramPct etc directly; they're already updated by heavy timer */ }
    }

    // --- Heavy metric polling (every 5s) ---
    Timer {
        interval: root._heavyIntervalMs
        repeat: true
        running: true
        onTriggered: root.refreshMetrics()
    }

    // --- Log polling timer (every 30 seconds) ---
    Timer {
        id: logTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refreshLogs()
    }

    // --- GPU polling (every 15s) ---
    Timer {
        interval: root._gpuIntervalMs
        repeat: true
        running: true
        onTriggered: root.refreshGpu()
    }

    // --- Update check (every 60s) ---
    Timer {
        id: updateCheckTimer
        interval: root._updateCheckIntervalMs
        repeat: true
        running: true
        onTriggered: root.refreshUpdates()
    }

    // --- Prechecks refresh (every 30s) ---
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refreshPrechecks()
    }

    // --- Generic shell command runner ---
    Component {
        id: cmdRunner
        Process {
            id: cmdProc
            property string shellCmd: ""
            property var onFinished: null
            command: ["bash", "-c", shellCmd]
            stdout: StdioCollector {
                onStreamFinished: {
                    if (cmdProc.onFinished) cmdProc.onFinished(text);
                }
            }
            stderr: StdioCollector {}
            onExited: exitCode => { cmdProc.destroy(); }
        }
    }

    function run(shellCmd, cb) {
        var p = cmdRunner.createObject(root, { shellCmd: shellCmd, onFinished: cb });
        p.running = true;
    }

    // --- Metric collection ---
    function refreshMetrics() {
        run("head -1 /proc/stat", parseCpu);
        run("free -m", parseRam);
        run("df / 2>/dev/null | awk 'NR==2{gsub(/%/,\"\",$5); print $5}'", parseDisk);
        run("cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1", parseTemp);
        run("ps aux --sort=-%cpu | head -9", parseProcs);
    }

    function refreshLogs() {
        run("journalctl -p 3 -n 20 --no-pager --output=short 2>/dev/null", parseLogs);
    }

    // --- GPU: nvidia-smi (Linux/Windows WSL), rocm-smi, or fallback ---
    function refreshGpu() {
        run("nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1", function(t) {
            var s = t.trim();
            if (s.length === 0) {
                root.gpuAvailable = false;
                return;
            }
            var parts = s.split(",").map(function(x) { return x.trim().replace(/\s*(%|MiB|C)?$/g, ""); });
            if (parts.length >= 4) {
                root.gpuAvailable = true;
                root.gpuPct = parseFloat(parts[0]) || 0;
                root.gpuVramUsedMb = parseInt(parts[1]) || 0;
                root.gpuVramTotalMb = parseInt(parts[2]) || 0;
                root.gpuTempC = parseFloat(parts[3]) || -1;
            } else {
                root.gpuAvailable = false;
            }
        });
    }

    // --- Pending updates: single script detects manager and counts (priority: apt > dnf > pacman > brew) ---
    function refreshUpdates() {
        if (root.updateInProgress) return;
        var script = [
            "out=\"\";",
            "if command -v apt-get >/dev/null 2>&1; then",
            "  n=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0);",
            "  sec=$(apt-get -s upgrade 2>/dev/null | grep -c security || echo 0);",
            "  echo apt:$n:$(echo $sec):$(echo $n);",
            "elif command -v dnf >/dev/null 2>&1; then",
            "  dnf check-update -q 2>/dev/null; r=$?;",
            "  n=$([ $r -eq 100 ] && dnf check-update -q 2>/dev/null | wc -l || echo 0);",
            "  echo dnf:$n:0:$n;",
            "elif command -v pacman >/dev/null 2>&1; then",
            "  n=$(pacman -Qu 2>/dev/null | wc -l);",
            "  echo pacman:$n:0:$n;",
            "elif command -v brew >/dev/null 2>&1; then",
            "  n=$(brew outdated 2>/dev/null | wc -l);",
            "  echo brew:$n:0:$n;",
            "else",
            "  echo \"::0:0:0\";",
            "fi"
        ].join(" ");
        run(script, function(text) {
            var line = text.trim().split("\n")[0] || "";
            var parts = line.split(":");
            if (parts.length >= 4) {
                root.updateManager = parts[0] || "";
                root.updateCount = parseInt(parts[1]) || 0;
                root.updateSecurity = parseInt(parts[2]) || 0;
                root.updateBugfix = Math.max(0, (parseInt(parts[3]) || 0) - root.updateSecurity);
                root.updateFeature = 0;
                if (root.updateCount > 0) {
                    if (root.updateManager === "apt") root.updateEtaLabel = root.updateCount <= 20 ? "~5 min" : root.updateCount <= 100 ? "~15 min" : "~30 min";
                    else if (root.updateManager === "dnf") root.updateEtaLabel = root.updateCount <= 50 ? "~10 min" : "~25 min";
                    else if (root.updateManager === "pacman") root.updateEtaLabel = root.updateCount <= 30 ? "~5 min" : "~15 min";
                    else if (root.updateManager === "brew") root.updateEtaLabel = root.updateCount <= 10 ? "~2 min" : "~10 min";
                    else root.updateEtaLabel = "";
                } else root.updateEtaLabel = "";
            }
        });
    }

    // --- Safe-mode prechecks: free space, battery, snapshot ---
    function refreshPrechecks() {
        run("df / 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}'", function(t) {
            root.freeSpaceGb = parseFloat(t.trim()) || 0;
        });
        run("cat /sys/class/power_supply/*/status 2>/dev/null | head -1", function(t) {
            root.onBattery = (t.trim().toLowerCase().indexOf("discharg") >= 0);
        });
        // snapshotAvailable is set by detectSnapshotProvider / after createSnapshot
    }

    function detectSnapshotProvider() {
        run("which timeshift 2>/dev/null", function(t) {
            if (t.trim().length > 0) {
                root.snapshotProvider = "timeshift";
                root.run("timeshift --list 2>/dev/null | grep -c '>' || true", function(c) {
                    root.snapshotAvailable = (parseInt(c.trim()) || 0) > 0;
                });
                return;
            }
        });
        run("mount | grep ' btrfs ' 2>/dev/null | head -1", function(t) {
            if (t.trim().length > 0 && root.snapshotProvider === "") {
                root.snapshotProvider = "btrfs";
                root.run("btrfs subvolume list / 2>/dev/null | wc -l", function(c) {
                    root.snapshotAvailable = (parseInt(c.trim()) || 0) > 0;
                });
            }
        });
        run("which zfs 2>/dev/null", function(t) {
            if (t.trim().length > 0 && root.snapshotProvider === "") {
                root.snapshotProvider = "zfs";
                root.run("zfs list -t snapshot 2>/dev/null | wc -l", function(c) {
                    root.snapshotAvailable = (parseInt(c.trim()) || 0) > 1;
                });
            }
        });
    }

    // --- Adaptive baseline: push value and return effective threshold (avg + margin or fixed) ---
    function _pushHistory(arr, val, maxLen) {
        var v = root[arr];
        if (!(v instanceof Array)) v = [];
        v.push(val);
        while (v.length > (maxLen || root.adaptiveHistorySize)) v.shift();
        root[arr] = v;
    }
    function _adaptiveThreshold(historyKey, fixedThreshold) {
        if (!root.useAdaptiveThresholds) return fixedThreshold;
        var v = root[historyKey];
        if (!(v instanceof Array) || v.length < 5) return fixedThreshold;
        var sum = 0;
        for (var i = 0; i < v.length; i++) sum += v[i];
        var avg = sum / v.length;
        var margin = 15;
        return Math.min(98, Math.max(50, Math.round(avg) + margin));
    }

    // --- Parsers ---
    function parseCpu(text) {
        var f = text.trim().split(/\s+/);
        if (f.length < 5 || f[0] !== "cpu") return;
        var total = 0;
        for (var i = 1; i < f.length; i++) total += (parseInt(f[i]) || 0);
        var idle = parseInt(f[4]) || 0;
        if (root._prevTotal > 0) {
            var dt = total - root._prevTotal;
            var di = idle - root._prevIdle;
            root.cpuPct = dt > 0 ? Math.max(0, Math.min(100, Math.round((1 - di / dt) * 100))) : 0;
        }
        root._prevTotal = total;
        root._prevIdle = idle;
        root._pushHistory("_cpuHistory", root.cpuPct);
        updateHealth();
    }

    function parseRam(text) {
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("Mem:") === 0) {
                var f = lines[i].trim().split(/\s+/);
                root.ramTotalMb = parseInt(f[1]) || 0;
                root.ramUsedMb = parseInt(f[2]) || 0;
                root.ramPct = root.ramTotalMb > 0
                    ? Math.round(root.ramUsedMb / root.ramTotalMb * 100) : 0;
                break;
            }
        }
        root._pushHistory("_ramHistory", root.ramPct);
        updateHealth();
    }

    function parseDisk(text) {
        var val = parseInt(text.trim());
        if (!isNaN(val)) root.diskPct = val;
        root._pushHistory("_diskHistory", root.diskPct);
        updateHealth();
    }

    function parseTemp(text) {
        var raw = text.trim();
        if (raw.length === 0) {
            root.tempC = -1;
            return;
        }
        var val = parseInt(raw);
        if (!isNaN(val)) root.tempC = val > 1000 ? Math.round(val / 1000) : val;
        updateHealth();
    }

    function parseProcs(text) {
        var lines = text.split("\n");
        var procs = [];
        for (var i = 1; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) continue;
            var f = line.split(/\s+/);
            if (f.length < 11) continue;
            var cmd = f.slice(10).join(" ");
            if (cmd.length > 32) cmd = cmd.substring(0, 30) + "..";
            procs.push({
                user: f[0].length > 10 ? f[0].substring(0, 9) + "." : f[0],
                pid: f[1],
                cpu: parseFloat(f[2]),
                mem: parseFloat(f[3]),
                cmd: cmd
            });
        }
        root.topProcs = procs;
    }

    function parseLogs(text) {
        var lines = text.split("\n").filter(function(l) { return l.trim().length > 0; });
        root.logErrors = lines;
        updateHealth();
    }

    // --- Health scoring (with adaptive thresholds and reason) ---
    function updateHealth() {
        var cpuTh = root._adaptiveThreshold("_cpuHistory", root.cpuThreshold);
        var ramTh = root._adaptiveThreshold("_ramHistory", root.ramThreshold);
        var diskTh = root._adaptiveThreshold("_diskHistory", root.diskThreshold);

        var score = 100;
        var reasons = [];
        if (root.cpuPct > cpuTh) { score -= 20; reasons.push("CPU high"); }
        if (root.ramPct > ramTh) { score -= 20; reasons.push("RAM high"); }
        if (root.diskPct > diskTh) { score -= 15; reasons.push("Disk high"); }
        if (root.tempC > 90) { score -= 30; reasons.push("Temp critical"); }
        else if (root.tempC > 80) { score -= 15; reasons.push("Temp high"); }
        if (root.logErrors.length > 10) { score -= 15; reasons.push("Many log errors"); }
        else if (root.logErrors.length > 0) { score -= 10; reasons.push("Log errors"); }
        if (root.gpuAvailable && root.gpuTempC > 90) { score -= 15; reasons.push("GPU hot"); }
        root.healthScore = Math.max(0, score);
        root.healthReason = reasons.length > 0 ? reasons.join(", ") : "";

        if (root.healthScore >= 80) {
            root.healthLabel = "Healthy";
            root.healthIcon = "monitor_heart";
        } else if (root.healthScore >= 50) {
            root.healthLabel = "Warning";
            root.healthIcon = "warning";
        } else {
            root.healthLabel = "Critical";
            root.healthIcon = "dangerous";
        }
    }

    // --- Update now: run package manager upgrade with progress ---
    signal updateFinished(bool success, string message)
    function runUpdateNow(createSnapshotFirst) {
        if (root.updateInProgress || root.updateCount === 0) return;
        if (createSnapshotFirst) root.createSnapshot(function(ok) { if (ok) root._doRunUpdateNow(); else root.updateFinished(false, "Snapshot failed"); });
        else root._doRunUpdateNow();
    }
    function _doRunUpdateNow() {
        root.updateInProgress = true;
        root.updateProgressPct = 0;
        root.updateProgressLabel = "Starting...";
        var cmd = "";
        if (root.updateManager === "apt") cmd = "DEBIAN_FRONTEND=noninteractive apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade";
        else if (root.updateManager === "dnf") cmd = "dnf -y update";
        else if (root.updateManager === "pacman") cmd = "pacman -Sy --noconfirm -u";
        else if (root.updateManager === "brew") cmd = "brew update && brew upgrade";
        else { root.updateInProgress = false; root.updateFinished(false, "Unsupported manager"); return; }
        var fullCmd = "pkexec bash -c '" + cmd.replace(/'/g, "'\"'\"'") + "' 2>&1";
        run(fullCmd, function(output) {
            root.updateInProgress = false;
            root.updateProgressPct = 100;
            root.updateProgressLabel = "Done";
            root.updateCount = 0;
            root.updateFinished(true, "Updates applied. Reboot if kernel or critical packages were updated.");
            root.refreshUpdates();
        });
        root.updateProgressLabel = "Installing updates...";
        root.updateProgressPct = 50;
    }

    // --- Snapshot create (Timeshift/Btrfs/ZFS); signal when done ---
    signal snapshotCreated(bool success, string idOrMessage)
    function createSnapshot(callback) {
        var cb = callback || function(ok) { root.snapshotCreated(ok, ok ? root.lastSnapshotId : "failed"); };
        if (root.snapshotProvider === "timeshift") {
            run("pkexec timeshift --create --comments 'DankSystemDoctor pre-action' 2>&1", function(out) {
                var ok = (out.indexOf("created") >= 0 || out.indexOf("Created") >= 0);
                if (ok) root.snapshotAvailable = true;
                root.lastSnapshotId = ok ? "timeshift-" + Date.now() : "";
                cb(ok);
            });
        } else if (root.snapshotProvider === "btrfs") {
            var snapPath = "/var/lib/snapshots/dank-" + Date.now();
            run("pkexec bash -c 'mkdir -p /var/lib/snapshots 2>/dev/null; btrfs subvolume snapshot / " + snapPath + " 2>/dev/null || true' 2>&1", function(out) {
                var ok = (out.indexOf("error") < 0 && out.length < 100);
                root.snapshotAvailable = ok;
                root.lastSnapshotId = ok ? snapPath : "";
                cb(ok);
            });
        } else if (root.snapshotProvider === "zfs") {
            run("zfs list -H -o name 2>/dev/null | head -1", function(pool) {
                var p = pool.trim();
                if (!p) { cb(false); return; }
                var snapName = p + "@dank-" + Date.now();
                run("pkexec zfs snapshot " + snapName + " 2>&1", function(out) {
                    var ok = (out.length === 0 || out.indexOf("error") < 0);
                    root.lastSnapshotId = ok ? snapName : "";
                    if (ok) root.snapshotAvailable = true;
                    cb(ok);
                });
            });
        } else {
            cb(false);
        }
    }

    // --- Maintenance actions with prechecks ---
    property var maintenanceActions: [
        { id: "clean_apt", group: "Clean", label: "Clean package caches (apt)", cmd: "apt-get clean", risk: "safe", needsRoot: true },
        { id: "clean_dnf", group: "Clean", label: "Clean DNF cache", cmd: "dnf clean all", risk: "safe", needsRoot: true },
        { id: "clean_pacman", group: "Clean", label: "Clean pacman cache", cmd: "pacman -Sc --noconfirm", risk: "safe", needsRoot: true },
        { id: "rotate_logs", group: "Clean", label: "Rotate logs", cmd: "logrotate -f /etc/logrotate.conf 2>/dev/null || true", risk: "safe", needsRoot: true },
        { id: "clear_tmp", group: "Clean", label: "Clear /tmp (older than 7d)", cmd: "find /tmp -type f -mtime +7 -delete 2>/dev/null; find /tmp -type d -empty -delete 2>/dev/null", risk: "safe", needsRoot: true },
        { id: "trim_ssd", group: "Clean", label: "TRIM SSD (fstrim)", cmd: "fstrim -av 2>/dev/null || true", risk: "safe", needsRoot: true },
        { id: "repair_apt", group: "Repair", label: "Repair broken packages (apt)", cmd: "apt-get -f install -y", risk: "requires_network", needsRoot: true },
        { id: "repair_dnf", group: "Repair", label: "Repair DNF", cmd: "dnf check && dnf -y install --setopt=strict=0", risk: "requires_network", needsRoot: true }
    ]
    signal maintenanceFinished(string actionId, bool success, string message)
    function runMaintenanceAction(actionId, skipPrecheck) {
        var act = null;
        for (var i = 0; i < root.maintenanceActions.length; i++) {
            if (root.maintenanceActions[i].id === actionId) { act = root.maintenanceActions[i]; break; }
        }
        if (!act) {
            root.maintenanceFinished(actionId, false, "Unknown action");
            return;
        }
        if (!skipPrecheck && root.freeSpaceGb < 2) {
            root.maintenanceFinished(actionId, false, "Low disk space (<2 GB). Free space first.");
            return;
        }
        if (!skipPrecheck && act.risk !== "safe" && root.onBattery) {
            root.maintenanceFinished(actionId, false, "On battery. Plug in AC for this action.");
            return;
        }
        var cmd = act.needsRoot ? ("pkexec bash -c '" + act.cmd.replace(/'/g, "'\"'\"'") + "'") : act.cmd;
        run(cmd + " 2>&1", function(output) {
            var success = (output.indexOf("E:") !== 0 && output.indexOf("Error") !== 0);
            root.maintenanceFinished(actionId, success, output.trim().substring(0, 200));
        });
    }

    // --- Public helpers ---
    function formatMb(mb) {
        if (mb >= 1024) return (mb / 1024).toFixed(1) + " GB";
        return mb + " MB";
    }

    function setLogInterval(seconds) {
        logTimer.interval = seconds * 1000;
    }

    // --- Build summarized context for Ollama (cap size, recent anomalies) ---
    function buildSummarizedContext(maxLines) {
        var cap = maxLines || 40;
        var lines = [];
        lines.push("CPU: " + root.cpuPct.toFixed(0) + "% (thr " + root.cpuThreshold + "%)");
        lines.push("RAM: " + root.ramPct.toFixed(0) + "% " + root.formatMb(root.ramUsedMb) + "/" + root.formatMb(root.ramTotalMb));
        lines.push("Disk: " + root.diskPct.toFixed(0) + "%");
        lines.push("Temp: " + (root.tempC > 0 ? root.tempC + "°C" : "N/A"));
        if (root.gpuAvailable) lines.push("GPU: " + root.gpuPct.toFixed(0) + "% " + root.gpuVramUsedMb + "/" + root.gpuVramTotalMb + " MiB " + (root.gpuTempC > 0 ? root.gpuTempC + "°C" : ""));
        lines.push("Health: " + root.healthScore + "/100 " + root.healthLabel + (root.healthReason ? " (" + root.healthReason + ")" : ""));
        if (root.topProcs.length > 0) {
            lines.push("Top processes:");
            for (var i = 0; i < Math.min(5, root.topProcs.length); i++)
                lines.push("  " + root.topProcs[i].cmd + " CPU " + root.topProcs[i].cpu.toFixed(1) + "%");
        }
        if (root.logErrors.length > 0) {
            lines.push("Recent errors: " + root.logErrors.length);
            for (var j = 0; j < Math.min(3, root.logErrors.length); j++)
                lines.push("  " + root.logErrors[j].substring(0, 80));
        }
        return lines.slice(0, cap).join("\n");
    }
}

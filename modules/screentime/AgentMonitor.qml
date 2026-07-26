import QtQuick
import Quickshell.Io

/*
 * AI agent work-time sampler. Every 10s one `sh` scans /proc/[pid]/stat,
 * finds processes whose comm matches the configured regex (default
 * claude|codex), groups them into sessions (a matching process with no
 * matching ancestor is a session root) and sums the CPU ticks of each root's
 * whole subtree — the bash/tool children an agent spawns are its work too.
 *
 * QML keeps the previous sample per root pid; a session is "working" in a
 * window when its subtree burned more CPU than the threshold. Calibrated on
 * this machine: a claude CLI idle at its prompt is exactly 0 ticks/10s, a
 * working one 200+, codex ~30 — the 1% default separates idle from working
 * with a wide margin.
 *
 * This dimension deliberately ignores focus AND the lock screen: an agent
 * grinding away while the user is elsewhere is exactly what it measures.
 * Suspend gaps (elapsed ≫ cadence) re-baseline and credit nothing.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property var store: null
    property var logic: null

    readonly property bool tracking: (store?.aiTracking === true) && (logic?.ready === true)
    readonly property string procRegex: {
        const re = (store?.aiProcessRegex ?? "").trim()
        return re !== "" ? re : "^(claude|codex)$"
    }
    readonly property int activePct: (store?.aiActiveCpuPct ?? 0) > 0 ? store.aiActiveCpuPct : 1

    readonly property int sampleMs: 10000
    property double lastSampleMs: 0
    property var prevCpu: ({})   // root pid -> cumulative subtree ticks

    // No single quotes allowed in the program: the shell line wraps it in them.
    readonly property string awkProg: `
{
  pid=$1
  p=index($0,"(")
  q=0
  for(i=length($0); i>0; i--) if(substr($0,i,1)==")"){q=i;break}
  if(p==0||q<=p) next
  comm=substr($0,p+1,q-p-1)
  split(substr($0,q+2),a," ")
  PPID[pid]=a[2]; CPU[pid]=a[12]+a[13]
  if (comm ~ re) M[pid]=1
}
END {
  for (pid in M) {
    anc=PPID[pid]; isroot=1; steps=0
    while (anc+0>1 && steps<64) { if (anc in M){isroot=0;break}; anc=PPID[anc]; steps++ }
    if (isroot) R[pid]=1
  }
  for (pid in CPU) {
    p2=pid; steps=0
    while (p2+0>1 && steps<64) { if (p2 in R){SUM[p2]+=CPU[pid]; break}; p2=PPID[p2]; steps++ }
  }
  for (r in R) printf "%s %d\\n", r, SUM[r]
}
`

    Timer {
        interval: root.sampleMs
        running: root.tracking
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }

    onTrackingChanged: {
        // Toggled either way: drop baselines so nothing is credited across
        // the gap, and zero the live counters.
        root.prevCpu = ({})
        root.lastSampleMs = 0
        if (root.logic) {
            root.logic.aiActiveNow = 0
            root.logic.aiSessionsNow = 0
        }
    }

    Process {
        id: proc
        // The user-configurable regex travels as an argv element ($1), never
        // interpolated into the shell line.
        command: ["sh", "-c",
            "printf 'clk %s\\n' \"$(getconf CLK_TCK)\"; exec awk -v re=\"$1\" '" + root.awkProg + "' /proc/[0-9]*/stat 2>/dev/null",
            "screentime-agent-scan", root.procRegex]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
    }

    function ingest(text) {
        const nowMs = Date.now()
        let clk = 100
        const cur = ({})
        for (const line of text.split("\n")) {
            const parts = line.trim().split(" ")
            if (parts[0] === "clk") {
                clk = Number(parts[1]) || 100
            } else if (parts.length >= 2 && parts[0] !== "") {
                cur[parts[0]] = Number(parts[1]) || 0
            }
        }
        const prev = root.prevCpu
        const elapsed = root.lastSampleMs > 0 ? (nowMs - root.lastSampleMs) / 1000 : 0
        root.lastSampleMs = nowMs
        root.prevCpu = cur
        if (!root.logic) return

        root.logic.aiSessionsNow = Object.keys(cur).length

        // First sample, or a gap far beyond the cadence (suspend, SIGSTOP):
        // the two samples don't bracket a live window — baseline only.
        if (elapsed <= 0 || elapsed > root.sampleMs / 1000 * 3) {
            root.logic.aiActiveNow = 0
            return
        }

        const threshold = Math.max(1, root.activePct / 100 * clk * elapsed)
        let active = 0
        for (const [pid, ticks] of Object.entries(cur)) {
            // A pid absent from prev is a new session: baseline this round.
            if (pid in prev && ticks - prev[pid] >= threshold) active++
        }
        root.logic.aiActiveNow = active
        if (active > 0) root.logic.accrueAi(elapsed, active)
    }
}

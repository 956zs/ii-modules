import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.mod.androlink_status
import "StatusLogic.js" as Logic

/*
 * Window-slot entry, instantiated exactly once: owns the module config file
 * (writes defaults) and the low-battery reminder, so a multi-monitor bar
 * never notifies twice. The reminder fires once per discharge cycle per
 * phone (StatusLogic.reminderStep) through notify-send with a fixed argv.
 * Its state is in memory only: a shell reload re-arms it.
 */
Scope {
    id: root

    ConfigLoader {
        id: cfg
        owner: true
    }

    PhoneStatus {
        id: status
        heartbeatSecs: cfg.options.heartbeatSecs
        pollSecs: cfg.options.pollSecs
    }

    // phone key -> armed (StatusLogic.reminderStep).
    property var armed: ({})

    function step() {
        if (!cfg.ready)
            return;
        const out = Logic.reminderStep(root.armed, status.record, cfg.options.lowBatteryThreshold, cfg.options.rearmMargin);
        root.armed = out.armed;
        if (!cfg.options.lowBatteryReminder)
            return;
        for (const hit of out.fire)
            root.notify(hit.name, hit.level);
    }

    function notify(name, level) {
        const phone = name !== "" ? name : Translation.tr("Phone");
        Quickshell.execDetached([
            "notify-send",
            "-a", "Shell",
            "-i", "phone",
            Translation.tr("%1 battery low").arg(phone),
            Translation.tr("%1 left. Charge it soon.").arg(`${level}%`)
        ]);
    }

    Connections {
        target: status
        function onRecordChanged() {
            root.step();
        }
    }

    Connections {
        target: cfg
        function onReadyChanged() {
            root.step();
        }
    }
}

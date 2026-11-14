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
 * phone, at most once per reminderMinIntervalMins (StatusLogic.reminderStep),
 * through notify-send with a fixed argv. Its state lives in the module config
 * (reminderState), so a shell reload or restart does not repeat a reminder.
 * PersistentProperties would not do: IIMP creates this entry with
 * createObject after the reload pass, so it never gets its old state back.
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

    function step() {
        // Turned off: the state stays as it was, so turning it back on while
        // the phone is low gives one reminder.
        if (!cfg.ready || !cfg.options.lowBatteryReminder)
            return;
        const before = cfg.options.reminderState;
        const out = Logic.reminderStep(Logic.parseReminderState(before), status.record, {
            threshold: cfg.options.lowBatteryThreshold,
            margin: cfg.options.rearmMargin,
            nowSecs: Date.now() / 1000,
            minIntervalSecs: cfg.options.reminderMinIntervalMins * 60
        });
        const after = Logic.serializeReminderState(out.state);
        if (after !== before)
            cfg.options.reminderState = after;
        for (const hit of out.fire)
            root.notify(hit.name, hit.level);
    }

    // `name` is already cleaned by StatusLogic.cleanName (no markup, no
    // control or bidi characters); reminderArgv ends options with `--`.
    function notify(name, level) {
        const phone = name !== "" ? name : Translation.tr("Phone");
        Quickshell.execDetached(Logic.reminderArgv("Shell", "phone",
            Translation.tr("%1 battery low").arg(phone),
            Translation.tr("%1 left. Charge it soon.").arg(`${level}%`)));
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

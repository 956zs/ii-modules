import Quickshell

/*
 * Intentionally empty: the module's effect is its Tier B patches (see
 * module.json), which turn on inline replies in the stock notification
 * server and insert ReplyField.qml into the stock notification items. IIMP
 * requires one slot, so the window slot hosts this empty Scope.
 */
Scope {}

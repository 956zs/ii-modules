import Quickshell

/*
 * Intentionally empty. This module's entire effect is its two Tier B patches
 * on ClockWidgetPopup.qml; SPEC 1.0 has no patch-only module shape (slots must
 * be non-empty), so it rides the window slot with a zero-footprint Scope —
 * unlike a bar entry, this renders nothing and reserves no bar space.
 */
Scope {}

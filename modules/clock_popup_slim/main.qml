import Quickshell
import qs.mod.clock_popup_slim

/*
 * Single settings owner. The visible clock is inserted into the stock bar by
 * Tier B patches; this zero-footprint window entry only materialises defaults.
 */
Scope {
    ConfigLoader {
        owner: true
    }
}

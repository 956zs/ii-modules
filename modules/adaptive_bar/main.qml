import Quickshell
import qs.mod.adaptive_bar

/*
 * Single settings owner. The fit logic runs inside the stock bar through
 * Tier B patches; this zero-footprint window entry only materialises defaults.
 */
Scope {
    ConfigLoader {
        owner: true
    }
}

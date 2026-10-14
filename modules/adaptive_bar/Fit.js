.pragma library

// Pure fit planning for the horizontal bar. The right section sits between the
// screen-centred middle section and the screen edge, so every pixel taken
// from BOTH centre side groups gives the right section exactly one pixel.
//
// Degradation order (user-chosen): fold pinned tray icons into the overflow
// menu first, then shrink both centre side groups symmetrically down to their
// content minimum. Anything still missing is reported as `overflow` so the
// caller can clip instead of painting over the middle section.

// Settings bounds for the centre side width cap: stock "hella shortened" and
// verbose widths.
var SIDE_SETTING_MIN = 190
var SIDE_SETTING_MAX = 360

// Narrowest width an elastic (fillWidth) centre child is assumed to tolerate;
// stock Media elides its title down to roughly icon + a few characters.
var ELASTIC_MIN = 96

// Extra slack required before undoing a degradation step, so a pill whose
// text width wobbles by a pixel or two cannot make tray icons flicker.
var HYSTERESIS = 8

function finite(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

function clampInt(value, lo, hi, fallback) {
    const n = Number(value);
    if (value === null || value === undefined || value === "" || !Number.isFinite(n))
        return fallback;
    return Math.min(hi, Math.max(lo, Math.round(n)));
}

function clamp(value, lo, hi) {
    return Math.min(hi, Math.max(lo, value));
}

// Width given back by folding `count` icons: each one frees its icon plus one
// grid gap, but the first fold may have to reveal the overflow button.
function foldSavings(count, unit, overhead) {
    if (!(count > 0))
        return 0;
    return count * unit - overhead;
}

// Right-section demand as if nothing were folded. `measured` already reflects
// the `folded` icons currently applied, so their savings are added back.
function unfoldedNeed(measured, folded, unit, overhead) {
    return finite(measured, 0) + foldSavings(folded, finite(unit, 0), finite(overhead, 0));
}

// Content minimum of a centre group: fixed children at their implicit width,
// elastic children squeezed to `elasticMin`, plus grid spacing and padding.
function groupMinWidth(entries, spacing, padding, elasticMin) {
    let total = 0;
    let count = 0;
    for (const entry of entries || []) {
        if (!entry || !entry.visible)
            continue;
        const width = Math.max(0, finite(entry.width, 0));
        total += entry.fill ? Math.min(width, elasticMin) : width;
        count += 1;
    }
    if (count === 0)
        return 0;
    return total + Math.max(0, finite(spacing, 0)) * (count - 1) + Math.max(0, finite(padding, 0)) * 2;
}

function normalize(input) {
    const sideMax = Math.max(0, Math.floor(finite(input.sideMax, 0)));
    return {
        valid: finite(input.barWidth, 0) > 0 && sideMax > 0,
        room: (finite(input.barWidth, 0) - finite(input.coreWidth, 0)) / 2,
        sideMax: sideMax,
        sideMin: clamp(Math.ceil(finite(input.sideMin, 0)), 0, sideMax),
        need: finite(input.rightNeed, 0),
        foldable: Math.max(0, Math.floor(finite(input.foldable, 0))),
        unit: Math.max(0, finite(input.foldUnit, 0)),
        overhead: Math.max(0, finite(input.foldOverhead, 0))
    };
}

// Missing right-section width at the stock side width with `fold` applied.
function deficitAfterFold(n, fold, need) {
    return need - (n.room - n.sideMax) - foldSavings(fold, n.unit, n.overhead);
}

// Fewest folded icons that cover `need`, or every foldable icon if that is
// still not enough. Folding that would cost more than it saves is skipped.
function foldFor(n, need) {
    const deficit = deficitAfterFold(n, 0, need);
    if (deficit <= 0 || n.foldable === 0 || n.unit === 0)
        return 0;
    const count = Math.min(n.foldable, Math.max(1, Math.ceil((deficit + n.overhead) / n.unit)));
    return foldSavings(count, n.unit, n.overhead) > 0 ? count : 0;
}

function shrinkFor(n, fold, need) {
    return clamp(Math.ceil(deficitAfterFold(n, fold, need)), 0, n.sideMax - n.sideMin);
}

function result(n, fold, shrink) {
    return {
        fold: fold,
        side: n.sideMax - shrink,
        overflow: Math.max(0, Math.ceil(deficitAfterFold(n, fold, n.need) - shrink))
    };
}

// Stateless plan: the minimal degradation that fits `rightNeed`.
function plan(input) {
    const n = normalize(input);
    if (!n.valid)
        return { fold: 0, side: n.sideMax, overflow: 0 };
    const fold = foldFor(n, n.need);
    return result(n, fold, shrinkFor(n, fold, n.need));
}

// Plan with hysteresis: each degradation step keeps its previous value while
// that value lies between what is strictly needed and what would still be
// needed with `hysteresis` more pixels of demand.
function settle(input, previous, hysteresis) {
    const n = normalize(input);
    if (!n.valid)
        return { fold: 0, side: n.sideMax, overflow: 0 };
    const margin = Math.max(0, finite(hysteresis, 0));
    const strictFold = foldFor(n, n.need);
    const paddedFold = foldFor(n, n.need + margin);
    const previousFold = previous ? Math.max(0, Math.floor(finite(previous.fold, 0))) : 0;
    let fold = clamp(previousFold, strictFold, paddedFold);
    if (fold > 0 && foldSavings(fold, n.unit, n.overhead) <= 0)
        fold = strictFold;

    const strictShrink = shrinkFor(n, fold, n.need);
    const paddedShrink = shrinkFor(n, fold, n.need + margin);
    const previousShrink = previous ? clamp(n.sideMax - Math.floor(finite(previous.side, n.sideMax)), 0, n.sideMax - n.sideMin) : 0;
    return result(n, fold, clamp(previousShrink, strictShrink, paddedShrink));
}

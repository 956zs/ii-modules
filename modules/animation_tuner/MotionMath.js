function tokenCatalog() {
    return [
        {
            id: "elementMove",
            label: "Element move",
            factory: "number",
            delayCoverage: "preview",
            durationMs: 500,
            velocity: 650,
            bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        },
        {
            id: "elementMoveSmall",
            label: "Small element move",
            factory: "number",
            delayCoverage: "preview",
            durationMs: 350,
            velocity: 650,
            bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1]
        },
        {
            id: "elementMoveEnter",
            label: "Element enter",
            factory: "number",
            delayCoverage: "preview",
            durationMs: 400,
            velocity: 650,
            bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
        },
        {
            id: "elementMoveExit",
            label: "Element exit",
            factory: "number",
            delayCoverage: "preview",
            durationMs: 200,
            velocity: 650,
            bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1]
        },
        {
            id: "elementMoveFast",
            label: "Fast element move",
            factory: "number-color",
            delayCoverage: "preview",
            durationMs: 200,
            velocity: 850,
            bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
        },
        {
            id: "elementResize",
            label: "Element resize",
            factory: "number",
            delayCoverage: "preview",
            durationMs: 300,
            velocity: 650,
            bezierCurve: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        },
        {
            id: "clickBounce",
            label: "Click bounce",
            factory: "number",
            delayCoverage: "preview",
            durationMs: 400,
            velocity: 850,
            bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        },
        {
            id: "scroll",
            label: "Scroll",
            factory: "none",
            delayCoverage: "preview",
            durationMs: 200,
            velocity: 0,
            bezierCurve: [0, 0, 0, 1, 1, 1]
        }
    ]
}

function defaultDocument() {
    return {
        schemaVersion: 1,
        reducedMotion: false,
        overrides: {},
        springLab: {
            mass: 1,
            spring: 2.5,
            damping: 0.3,
            epsilon: 0.01,
            velocity: 0,
            modulus: 0,
            delayMs: 0
        },
        customPresets: []
    }
}

function copy(value) {
    return JSON.parse(JSON.stringify(value))
}

function finiteNumber(value, min, max) {
    return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max
}

function knownTokenIds() {
    return tokenCatalog().map(token => token.id)
}

function migrateDocument(source) {
    if (!source || typeof source !== "object" || Array.isArray(source)) return defaultDocument()
    if (source.schemaVersion !== 0) return copy(source)

    const migrated = copy(source)
    migrated.schemaVersion = 1
    migrated.reducedMotion = source.reduceMotion === true
    const legacyTokens = source.tokens && typeof source.tokens === "object" && !Array.isArray(source.tokens)
        ? copy(source.tokens) : {}
    const catalog = tokenCatalog()
    for (const id in legacyTokens) {
        const token = catalog.find(candidate => candidate.id === id)
        if (!token || !legacyTokens[id] || typeof legacyTokens[id] !== "object") continue
        legacyTokens[id] = Object.assign({
            enabled: true,
            easingKind: "bezier",
            durationMs: token.durationMs,
            delayMs: 0,
            velocity: token.velocity,
            bezierCurve: copy(token.bezierCurve)
        }, legacyTokens[id])
    }
    migrated.overrides = legacyTokens
    if (!migrated.springLab) migrated.springLab = defaultDocument().springLab
    if (!Array.isArray(migrated.customPresets)) migrated.customPresets = []
    delete migrated.reduceMotion
    delete migrated.tokens
    return migrated
}

function validateCurve(curve, path, errors) {
    if (!Array.isArray(curve) || curve.length === 0 || curve.length % 6 !== 0) {
        errors.push(`${path} must contain complete cubic Bezier segments`)
        return
    }

    let startX = 0
    for (let i = 0; i < curve.length; i += 6) {
        const c1x = curve[i]
        const c1y = curve[i + 1]
        const c2x = curve[i + 2]
        const c2y = curve[i + 3]
        const endX = curve[i + 4]
        const endY = curve[i + 5]
        const values = [c1x, c1y, c2x, c2y, endX, endY]
        if (!values.every(value => typeof value === "number" && Number.isFinite(value))) {
            errors.push(`${path} contains a nonfinite value`)
            return
        }
        if (c1y < -2 || c1y > 3 || c2y < -2 || c2y > 3 || endY < -2 || endY > 3) {
            errors.push(`${path} y values must stay between -2 and 3`)
        }
        if (endX <= startX || endX > 1 || c1x < startX || c1x > endX || c2x < startX || c2x > endX) {
            errors.push(`${path} x values must be ordered within each segment`)
        }
        startX = endX
    }

    const last = curve.length - 2
    if (curve[last] !== 1 || curve[last + 1] !== 1) {
        errors.push(`${path} must end at 1,1`)
    }
}

function validateOverride(id, override, errors) {
    const path = `overrides.${id}`
    if (!override || typeof override !== "object" || Array.isArray(override)) {
        errors.push(`${path} must be an object`)
        return
    }
    if (typeof override.enabled !== "boolean") errors.push(`${path}.enabled must be boolean`)
    if (!override.enabled) return
    if (override.easingKind !== "bezier") errors.push(`${path}.easingKind must be bezier`)
    if (!finiteNumber(override.durationMs, 0, 10000)) errors.push(`${path}.durationMs is outside 0..10000`)
    if (!finiteNumber(override.delayMs, 0, 5000)) errors.push(`${path}.delayMs is outside 0..5000`)
    if (!finiteNumber(override.velocity, 0, 10000)) errors.push(`${path}.velocity is outside 0..10000`)
    validateCurve(override.bezierCurve, `${path}.bezierCurve`, errors)
}

function validateSpringLab(springLab, errors) {
    if (!springLab || typeof springLab !== "object" || Array.isArray(springLab)) {
        errors.push("springLab must be an object")
        return
    }
    const ranges = {
        mass: [0.01, 100],
        spring: [0, 5],
        damping: [0, 1],
        epsilon: [0.0001, 1],
        velocity: [0, 10000],
        modulus: [0, 100000],
        delayMs: [0, 5000]
    }
    for (const key in ranges) {
        if (!finiteNumber(springLab[key], ranges[key][0], ranges[key][1])) {
            errors.push(`springLab.${key} is outside ${ranges[key][0]}..${ranges[key][1]}`)
        }
    }
}

function validateDocument(document) {
    const errors = []
    if (!document || typeof document !== "object" || Array.isArray(document)) {
        return { ok: false, errors: ["document must be an object"] }
    }
    if (document.schemaVersion !== 1) errors.push("schemaVersion must be 1")
    if (typeof document.reducedMotion !== "boolean") errors.push("reducedMotion must be boolean")
    if (!document.overrides || typeof document.overrides !== "object" || Array.isArray(document.overrides)) {
        errors.push("overrides must be an object")
    } else {
        const known = knownTokenIds()
        for (const id of known) {
            if (Object.prototype.hasOwnProperty.call(document.overrides, id)) {
                validateOverride(id, document.overrides[id], errors)
            }
        }
    }
    validateSpringLab(document.springLab, errors)
    if (!Array.isArray(document.customPresets)) {
        errors.push("customPresets must be an array")
    } else {
        for (let i = 0; i < document.customPresets.length; ++i) {
            const preset = document.customPresets[i]
            const path = `customPresets.${i}`
            if (!preset || typeof preset !== "object" || Array.isArray(preset)) {
                errors.push(`${path} must be an object`)
                continue
            }
            if (typeof preset.name !== "string" || preset.name.trim() === "" || preset.name.length > 40)
                errors.push(`${path}.name must contain 1..40 characters`)
            validateCurve(preset.bezierCurve, `${path}.bezierCurve`, errors)
        }
    }
    return { ok: errors.length === 0, errors }
}

function parseDocument(serialized) {
    let source = null
    try {
        source = JSON.parse(serialized)
    } catch (error) {
        return { ok: false, document: defaultDocument(), applicableTokens: [], errors: ["configuration is not valid JSON"] }
    }
    if (!source || typeof source !== "object" || Array.isArray(source)) {
        return { ok: false, document: defaultDocument(), applicableTokens: [], errors: ["configuration must be a JSON object"] }
    }
    if (source.schemaVersion !== 0 && source.schemaVersion !== 1) {
        return { ok: false, document: defaultDocument(), applicableTokens: [], errors: ["unsupported configuration schema"] }
    }

    const document = migrateDocument(source)
    const validation = validateDocument(document)
    if (!validation.ok) {
        return { ok: false, document: defaultDocument(), applicableTokens: [], errors: validation.errors }
    }
    const known = knownTokenIds()
    return {
        ok: true,
        document,
        applicableTokens: Object.keys(document.overrides).filter(id => known.includes(id) && document.overrides[id]?.enabled === true),
        errors: []
    }
}

function effectiveToken(document, id) {
    if (!knownTokenIds().includes(id)) return null
    const stored = document?.overrides?.[id]
    let override = stored && stored.enabled === true ? copy(stored) : null
    if (!override && document?.reducedMotion === true) {
        const token = tokenCatalog().find(candidate => candidate.id === id)
        override = {
            enabled: true,
            easingKind: "bezier",
            durationMs: token.durationMs,
            delayMs: 0,
            velocity: token.velocity,
            bezierCurve: copy(token.bezierCurve)
        }
    }
    if (!override) return null
    if (document.reducedMotion === true) {
        override.durationMs = 0
        override.delayMs = 0
    }
    return override
}

function cubic(a, b, c, d, t) {
    const inv = 1 - t
    return inv * inv * inv * a + 3 * inv * inv * t * b + 3 * inv * t * t * c + t * t * t * d
}

function pointAtX(curve, x) {
    let startX = 0
    let startY = 0
    for (let i = 0; i < curve.length; i += 6) {
        const endX = curve[i + 4]
        const endY = curve[i + 5]
        if (x <= endX || i + 6 === curve.length) {
            let low = 0
            let high = 1
            for (let iteration = 0; iteration < 24; ++iteration) {
                const middle = (low + high) / 2
                const currentX = cubic(startX, curve[i], curve[i + 2], endX, middle)
                if (currentX < x) low = middle
                else high = middle
            }
            const t = (low + high) / 2
            return cubic(startY, curve[i + 1], curve[i + 3], endY, t)
        }
        startX = endX
        startY = endY
    }
    return 1
}

function sampleBezier(curve, steps) {
    const errors = []
    validateCurve(curve, "bezierCurve", errors)
    if (errors.length > 0 || !Number.isInteger(steps) || steps < 1 || steps > 1000) return []
    const points = []
    for (let i = 0; i <= steps; ++i) {
        const x = i / steps
        const y = i === 0 ? 0 : i === steps ? 1 : pointAtX(curve, x)
        const stableY = Math.round(y * 1000000) / 1000000
        points.push({ x, y: Math.abs(stableY) < 1e-12 ? 0 : stableY })
    }
    return points
}

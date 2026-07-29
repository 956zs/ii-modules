import Quickshell
import qs.mod.animation_tuner

Scope {
    ConfigLoader {
        id: config
        writable: false
    }

    AnimationController {
        config: config
    }
}

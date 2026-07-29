import QtQuick

QtObject {
    property QtObject animation: QtObject {
        property QtObject elementMove: MotionToken {}
        property QtObject elementMoveSmall: MotionToken {}
        property QtObject elementMoveEnter: MotionToken {}
        property QtObject elementMoveExit: MotionToken {}
        property QtObject elementMoveFast: MotionToken {}
        property QtObject elementResize: MotionToken {}
        property QtObject clickBounce: MotionToken {}
        property QtObject scroll: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: [0, 0, 0, 1, 1, 1]
        }
    }

    component MotionToken: QtObject {
        property int duration: 300
        property int type: Easing.BezierSpline
        property list<real> bezierCurve: [0.2, 0, 0, 1, 1, 1]
        property int velocity: 650
    }
}

options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

require daslib/decs_boost
require daslib/media

let POLY_FACET = 10.0 // max size of polygon interpolation in pixels
let RACKET_WEIGHT = 8.0 // width of racket

var screenCenter : float2


[export]
def initialize
    set_window_title("cirkuloid")
    screenCenter = float2(
        float(get_screen_width()) / 2.0,
        float(get_screen_height()) / 2.0)
    racketCreate(0xFFCC66)


[export]
def act(dt : float)
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    decs_stage("update")


[export]
def draw
    decs_stage("draw")


// RACKET //////////////////////////////////////////////////////////////////////

[decs_template]
struct CompRacket
    color : uint
    radius : float = 300.0
    size : float = 50.0
    pos : float // current position
    posTarget : float // target position
    posSpeed : float
    posSpeedMax : float = 0.75 // speed of changing position per second
    lives : int = 3


def racketCreate(color : uint)
    create_entity <| @ (eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompRacket() color = color ]])


[decs(stage = update)]
def updateRacket(var racket : CompRacket)
    let dt = get_delta_time()
    let keyboardSpeed = dt / racket.posSpeedMax // adjust speed for any FPS
    var posTarget = racket.posTarget

    // keyboard controls
    if get_key(VK_LEFT)
        posTarget -= keyboardSpeed
    if get_key(VK_RIGHT)
        posTarget += keyboardSpeed

    // mouse controls
    let mouseMoved : float2 = get_mouse_position_delta()
    if mouseMoved.x != 0.0 || mouseMoved.y != 0.0
        posTarget = posToAngle(get_mouse_position(), screenCenter)

    // gamepad controls
    let axisMovedX = get_axis(AXIS_PRIMARY_X)
    let axisMovedY = get_axis(AXIS_PRIMARY_Y)
    if axisMovedX * axisMovedX + axisMovedY * axisMovedY > 0.15 // gamepad dead zone
        posTarget = posToAngle(float2(axisMovedX, axisMovedY))
    
    posTarget = posTarget - ceil(posTarget)
    if posTarget < 0.0
        posTarget += 1.0
    racket.posTarget = posTarget


[decs(stage = draw)]
def drawRacket(var racket : CompRacket)
    let halfArc = racket.size / (PI * 4.0 * racket.radius)
    var start = racket.posTarget - halfArc
    start -= floor(start)
    if start < 0.0
        start += 1.0
    var end = racket.posTarget + halfArc
    end -= floor(end)
    if end < start
        end += 1.0
    let angleEnd = PI * 2.0 * end
    var angleIn = PI * 2.0 * start
    var angleOut = angleIn
    let arc = angleEnd - angleIn
    let polys = ceil(arc * racket.radius / POLY_FACET)
    let deltaIn = arc / polys
    let deltaOut = arc / ceil(arc * (racket.radius + RACKET_WEIGHT) / POLY_FACET)
    for i in range(0, int(polys))
        var points : array<float2>
        points |> sectorPoint(screenCenter, racket.radius, angleIn)
        angleIn += deltaIn
        while (angleOut < angleIn)
            points |> sectorPoint(screenCenter, racket.radius + RACKET_WEIGHT, angleOut)
            angleOut += deltaOut
        points |> sectorPoint(screenCenter, racket.radius + RACKET_WEIGHT, min(angleOut, angleEnd))
        points |> sectorPoint(screenCenter, racket.radius, angleIn)
        fill_convex_polygon(points, racket.color)


def posToAngle(position : float2; center : float2 = float2())
    return atan2(position.y - center.y, position.x - center.x) / (PI * 2.0)


def sectorPoint(var points : array<float2>; center : float2; radius : float; angle : float)
    points |> push(float2(center.x + radius * cos(angle), center.y + radius * sin(angle)))

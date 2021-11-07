//options debugger            // uncomment for debug in VS Code
//require daslib/debug        // uncomment for debug in VS Code

require daslib/decs_boost
require daslib/media

let POLY_FACET = 10.0 // max size of polygon interpolation in pixels
let RACKET_WEIGHT = 8.0 // width of racket
let STONE_COLORS <- [{ auto[]
    0x002244; 0x114477; 0x441188; 0x992211;
    0xBB5522; 0xEEAA33; 0xFFDD66; 0xFFFFFF }]

var screenCenter : float2


[export]
def initialize(isHardReload : bool)
    set_window_title("cirkuloid")
    screenCenter = float2(
        float(get_screen_width()) / 2.0,
        float(get_screen_height()) / 2.0)
    if isHardReload
        createRacket(0x66CCFF)
        levelCreate()
        commit()


[export]
def act
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    if get_mouse_button_down(MB_LEFT)
        createBall()
    decs_stage("update")


[export]
def draw
    decs_stage("draw")
    fps()


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


def createRacket(color : uint)
    create_entity <| @(eid, cmp)
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
    
    posTarget -= ceil(posTarget)
    if posTarget < 0.0
        posTarget += 1.0
    racket.posTarget = posTarget

    // slide racket to target position
/*
    var pos = racket.pos
    var diff = posTarget - pos
    var direction = sign(diff)
    diff = abs(diff)
    let diff1 = abs(1.0 + pos - posTarget)
    if diff1 < diff
        diff = diff1
        direction = -direction
    if diff > 0.001
        let speed = 0.01// min(diff, racket.posSpeedMax) / dt
        pos += speed * direction
        racket.pos = pos
*/
    racket.pos = posTarget


[decs(stage = draw)]
def drawRacket(var racket : CompRacket)
    let halfArc = racket.size / (PI * 4.0 * racket.radius)
    var start = racket.pos - halfArc
    start -= floor(start)
    if start < 0.0
        start += 1.0
    var end = racket.pos + halfArc
    end -= floor(end)
    if end < start
        end += 1.0
    let angleEnd = PI * 2.0 * end
    var angleIn = PI * 2.0 * start
    var angleOut = angleIn
    let angleDiff = angleEnd - angleIn
    let polys = ceil(angleDiff * racket.radius / POLY_FACET)
    let deltaIn = angleDiff / polys
    let deltaOut = angleDiff / ceil(angleDiff * (racket.radius + RACKET_WEIGHT) / POLY_FACET)
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


// STONES //////////////////////////////////////////////////////////////////////

[decs_template]
struct CompStone
    pos : float2
    radius : float
    resist : int
    damage : int


def createStone(resist : int; radius : float; pos : float2)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompStone resist = resist, pos = pos, radius = radius ]])


def levelCreate
    let STONE_RADIUS = 16.0
    let STONE_GAP = 6.0
    let STONE_CIRCLES = 7

    var radius = 0.0
    for i in range(0, STONE_CIRCLES)
        let count = max(floor(PI * 2.0 * radius / (2.0 * STONE_RADIUS + STONE_GAP)), 1.0)
        let angleStep = PI * 2.0 / count
        var angle = i % 2 != 0 ? 0.0 : angleStep / 2.0
        for j in range(0, int(count))
            createStone(STONE_CIRCLES - i - 1, STONE_RADIUS, float2(
                radius * cos(angle),
                radius * sin(angle)))
            angle += angleStep
        radius += 2.0 * STONE_RADIUS + STONE_GAP


[decs(stage = draw)]
def drawStone(var stone : CompStone)
    let color = STONE_COLORS[min(max(stone.resist - stone.damage, 0), length(STONE_COLORS))]
    fill_circle(screenCenter.x + stone.pos.x, screenCenter.y + stone.pos.y, stone.radius, color)


// BALLS ///////////////////////////////////////////////////////////////////////

[decs_template]
struct CompBall
    pos : float2
    vel : float2
    radius : float = 6.0


def createBall()
    let radius = random(0.0, 250.0)
    let angle = random(0.0, PI * 2.0)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompBall()
            pos = float2(radius * cos(angle), radius * sin(angle)),
            vel = float2(random(-1.0, 1.0), random(-1.0, 1.0)) ]])


[decs(stage = update)]
def updateBall(var ball : CompBall)
    ball.pos += ball.vel


[decs(stage = draw)]
def drawBall(var ball : CompBall)
    fill_circle(screenCenter.x + ball.pos.x, screenCenter.y + ball.pos.y, ball.radius, 0xFFFFFF)


// UTILITIES ///////////////////////////////////////////////////////////////////

var seed : int4
def random(from, to : auto)
    return from + random_float(seed) * (to - from)


var fpsCooldown : int
var fpsValue : int
var fpsColor : uint
def fps
    set_font_size(12)
    text_out(3, get_screen_height() - 15, "FPS:{fpsValue}", fpsColor)
    if --fpsCooldown > 0
        return
    fpsCooldown = fpsValue
    fpsValue = int(1.0 / get_delta_time())
    fpsColor = (fpsValue > 55 ? 0x113300
        : fpsValue > 40 ? 0x775500
        : 0x550000)

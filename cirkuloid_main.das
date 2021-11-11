require daslib/decs_boost
require daslib/media

options debugger
require daslib/debug

let POLY_FACET = 10.0 // max size of polygon interpolation in pixels
let RACKET_WEIGHT = 8.0 // width of racket
let VOID_RADIUS = 350.0 // distance to remove lost ball
let STONE_COLORS <- mkStoneColors([{ auto[]
    0x002244; 0x004477; 0x440077; 0x770000;
    0xBB5500; 0xEEAA33; 0xFFBB33; 0xFFDDBB }])
let RACKET_COLORS <- [{ auto[]
    0x66CCFF; 0xFF6666; 0x66FF66 }]
let CONTROLS <-[{ auto[]
    mkControlKeyboard(VK_LEFT, VK_RIGHT, VK_SPACE);
    mkControlMouse();
    mkControlGamepad() }]

var screenCenter : float2


[export]
def initialize(isHardReload : bool)
    set_window_title("cirkuloid")
    screenCenter = float2(
        float(get_screen_width()) / 2.0,
        float(get_screen_height()) / 2.0)
    if isHardReload
        for idx, color in range(length(RACKET_COLORS)), RACKET_COLORS
            createRacket(idx, color)
        levelCreate()
        commit()


[export, unused_argument(dt)]
def act(dt : float)
    processControls()
    decs_stage("update")


[export]
def draw
    decs_stage("draw")
    fps()


// CONTROLS ////////////////////////////////////////////////////////////////////

def processControls
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    for idx, control in range(length(CONTROLS)), CONTROLS
        control |> invoke(idx)


def racketSet(racketIdx : int; newPos : float)
    query() <| $(CompRacket_index : int; var CompRacket_posTarget : float&)
        if racketIdx != CompRacket_index
            return
        CompRacket_posTarget = newPos - ceil(newPos)
        if CompRacket_posTarget < 0.0
            CompRacket_posTarget += 1.0


def racketAdd(racketIdx : int; deltaPos : float)
    query() <| $(CompRacket_index : int; var CompRacket_posTarget : float&)
        if racketIdx != CompRacket_index
            return
        CompRacket_posTarget += deltaPos
        CompRacket_posTarget -= ceil(CompRacket_posTarget)
        if CompRacket_posTarget < 0.0
            CompRacket_posTarget += 1.0


def racketAction(racketIdx : int)
    query() <| $(var eid: EntityId; CompRacket_index : int)
        if racketIdx != CompRacket_index
            return
        // dummy action for now; should use current booster
        createBall(eid)


def mkControlKeyboard(kbBack, kbForward, kbAction: int)
    return @ <| (index : int)
        let keyboardSpeed = get_delta_time() / 0.75//racket.posSpeedMax // adjust speed for any FPS
        if get_key(kbBack)
            racketAdd(index, -keyboardSpeed)
        if get_key(kbForward)
            racketAdd(index, keyboardSpeed)
        if get_key_press(kbAction)
            racketAction(index)


def mkControlMouse()
    return @ <| (index : int)
        let mouseDelta = get_mouse_position_delta()
        if mouseDelta.x != 0.0 || mouseDelta.y != 0.0
            racketSet(index, posToArc(get_mouse_position(), screenCenter))
        if get_mouse_button(MB_LEFT)
            racketAction(index)


def mkControlGamepad()
    return @ <| (index : int)
        let axisMovedX = get_axis(AXIS_PRIMARY_X)
        let axisMovedY = get_axis(AXIS_PRIMARY_Y)
        if axisMovedX * axisMovedX + axisMovedY * axisMovedY > 0.15 // gamepad dead zone
            racketSet(index, posToArc(float2(axisMovedX, axisMovedY)))
        if get_key(GP_A)
            racketAction(index)


// RACKET //////////////////////////////////////////////////////////////////////

[decs_template]
struct CompRacket
    index : int
    color : uint
    radius : float
    size : float
    pos : float // current position
    posTarget : float // target position
    posSpeed : float
    posSpeedMax : float // speed of changing position per second
    balls : int // amount of owned balls
    lives : int
    score : int


def createRacket(index : int; color : uint)
    return create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompRacket
            index = index,
            color = color,
            radius = 300.0 + float(index) * 12.0,
            size = 50.0,
            posTarget = float(index) / 3.0,
            posSpeedMax = 0.75,
            lives = 3 ]])


[decs(stage = update)]
def updateRacket(var racket : CompRacket)

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
    racket.pos = racket.posTarget


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

    var x = get_screen_width() - 120 * racket.index - 70
    // score
    set_font_size(22)
    text_out(x, 3, string(racket.score), racket.color)

    // lives
    for i in range(racket.lives)
        x -= 8
        fill_rect(x, 10, 3, 14, racket.color)


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
            createStone(STONE_CIRCLES - i, STONE_RADIUS, float2(
                radius * cos(angle),
                radius * sin(angle)))
            angle += angleStep
        radius += 2.0 * STONE_RADIUS + STONE_GAP


[decs(stage = update)]
def updateStone(eid : EntityId; var stone : CompStone)
    if stone.damage >= stone.resist
        delete_entity(eid)


[decs(stage = draw)]
def drawStone(var stone : CompStone)
    let color = STONE_COLORS[stone.resist][min(stone.damage, stone.resist)]
    fill_circle(screenCenter.x + stone.pos.x, screenCenter.y + stone.pos.y, stone.radius, color)


// BALLS ///////////////////////////////////////////////////////////////////////

[decs_template]
struct CompBall
    pos : float2
    vel : float2
    radius : float
    owner : EntityId


def createBall(var ownerId : EntityId)
    let radius = random(0.0, 250.0)
    let angle = random(0.0, PI * 2.0)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompBall
            owner := ownerId,
            pos = float2(radius * cos(angle), radius * sin(angle)),
            vel = float2(random(-5.0, 5.0), random(-5.0, 5.0)),
            radius = 6.0 ]])
    query(ownerId) <| $(var CompRacket_balls : int&)
        ++CompRacket_balls


[decs(stage = update)]
def updateBall(eid : EntityId; var ball : CompBall)
    ball.pos += ball.vel
    if !isCollide(float2(), ball.pos, VOID_RADIUS)
        // ball is lost
        query(ball.owner) <| $(var CompRacket_balls : int&; var CompRacket_lives : int&)
            --CompRacket_balls
            if CompRacket_balls <= 0
                --CompRacket_lives
                if CompRacket_lives <= 0
                    delete_entity(ball.owner)
        delete_entity(eid)
        return

    query() <| $(eid : EntityId; CompRacket_pos : float; CompRacket_size : float; CompRacket_radius : float; var CompRacket_balls : int&)
        if !isCollide(float2(), ball.pos, CompRacket_radius)
            let pos = posToArc(ball.pos)
            let halfArc = CompRacket_size / (PI * 4.0 * CompRacket_radius)
            var posMin = CompRacket_pos - halfArc
            posMin -= floor(posMin)
            if posMin < 0.0
                posMin += 1.0
            var posMax = CompRacket_pos + halfArc
            posMax -= floor(posMax)
            if (posMin <= pos) == (pos <= posMax)
                let norm = normalize(-ball.pos)
                ball.vel -= 2.0 * norm * dot(ball.vel, norm)
                if ball.owner != eid
                    // take possession of another's ball on bounce
                    ball.owner = eid
                    ++CompRacket_balls
                    

    query() <| $(CompStone_pos : float2; CompStone_radius : float; CompStone_resist : int; var CompStone_damage : int&)
        if isCollide(ball.pos, CompStone_pos, ball.radius + CompStone_radius)
            let norm = normalize(CompStone_pos - ball.pos)
            ball.vel -= 2.0 * norm * dot(ball.vel, norm)
            CompStone_damage += 1
            if CompStone_damage == CompStone_resist
                query(ball.owner) <| $(var CompRacket_score : int&)
                    let bonus = CompStone_resist * 5
                    CompRacket_score += bonus
                    createInfo(CompStone_pos, norm, "+{bonus}")


[decs(stage = draw)]
def drawBall(var ball : CompBall)
    var color = 0x666666
    query(ball.owner) <| $(CompRacket_color : uint)
        color = CompRacket_color
    fill_circle(screenCenter.x + ball.pos.x, screenCenter.y + ball.pos.y, ball.radius, color)


def isCollide(pos1, pos2 : float2; dist : float)
    let diff = abs(pos1 - pos2)
    if diff.x > dist || diff.y > dist
        return false
    return diff.x * diff.x + diff.y * diff.y <= dist * dist


// INFOS ///////////////////////////////////////////////////////////////////////

[decs_template]
struct CompInfo
    pos : float2
    vel : float2
    msg : string
    lifetime : float


def createInfo(pos, vel : float2; msg : string)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompInfo pos = pos, vel = vel, msg = msg, lifetime = 1.0 ]])


[decs(stage = update)]
def updateInfo(eid : EntityId; var info : CompInfo)
    info.pos += info.vel
    info.vel *= 0.97
    info.lifetime -= get_delta_time()
    if info.lifetime <= 0.0
        delete_entity(eid)


[decs(stage = draw)]
def drawInfo(var info : CompInfo)
    set_font_size(12)
    text_out(screenCenter.x + info.pos.x, screenCenter.y + info.pos.y, info.msg, 0xFFFFFF)


// UTILITIES ///////////////////////////////////////////////////////////////////

def posToArc(position : float2; center : float2 = float2())
    var arc = atan2(position.y - center.y, position.x - center.x) / (PI * 2.0)
    return arc < 0.0 ? arc + 1.0 : arc


var seed : int4
def random(from, to : auto)
    return from + random_float(seed) * (to - from)


def colorCompFade(color : uint; ratio : float; bits : uint = 0u)
    return uint(float((color >> bits) & 0xFF) * ratio) << bits


def mkStoneColors(basic : array<uint>)
    var faded : array<array<uint>>
    let count = length(basic)
    faded |> resize(count)
    for resist, color in range(count), basic
        faded[resist] |> resize(resist + 1)
        for damage in range(resist)
            let ratio = float(resist - damage) / float(resist)
            faded[resist][damage] = (colorCompFade(color, ratio, 16u)
                | colorCompFade(color, ratio, 8u)
                | colorCompFade(color, ratio))
    return <- faded


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

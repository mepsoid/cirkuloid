require daslib/decs_boost
require daslib/media

options debugger
require daslib/debug

let POLY_FACET = 10.0 // max size of polygon interpolation in pixels
let RACKET_WEIGHT = 8.0 // width of racket
let VOID_RADIUS = 350.0 // distance to remove lost ball
let STONE_COLORS <- mkStoneColors([{ auto[]
    0x003366; 0x006699; 0x6600AA; 0xAA0000;
    0xBB5500; 0xEE9933; 0xFFCC66; 0xFFEEDD }])
let RACKET_COLORS <- [{ auto[]
    0xFF66CCFF; 0xFFFF6666; 0xFF66FF66 }]
let CONTROLS <-[{ auto[]
    mkControlKeyboard(VK_LEFT, VK_RIGHT, VK_SPACE);
    mkControlMouse();
    mkControlGamepad() }]
var BALL_RADIUS : float

var imgStone <- create_image("assets/stone.png")
var imgStoneTile : float4
var imgBackground <- create_image("assets/back.png")
var imgBackgroundSize : float2
var imgBackgroundTile : float4
var imgBall <- create_image("assets/ball.png")
var imgBallSize : float2
var imgBooster <- create_image("assets/star.png")
var imgBoosterSize : float2
var imgBoosterTile : float4
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
    imgStone |> premultiply_alpha()
    imgStone |> set_image_smooth(true)
    imgStoneTile = float4(0.0, 0.0, float(imgStone.width), float(imgStone.height))
    imgBackground |> set_image_clamp(false)
    imgBackgroundSize = float2(get_screen_width(), get_screen_height())
    imgBackgroundTile = float4(0.0, 0.0, float(get_screen_width()), float(get_screen_height()))
    imgBallSize = float2(imgBall.width, imgBall.height)
    BALL_RADIUS = max(imgBallSize.x, imgBallSize.y) / 2.0
    imgBooster |> premultiply_alpha()
    imgBooster |> set_image_smooth(true)
    imgBoosterSize = float2(imgBooster.width, imgBooster.height)
    imgBoosterTile = float4(0.0, 0.0, float(imgBooster.width), float(imgBooster.height))


[export, unused_argument(dt)]
def act(dt : float)
    processControls()
    decs_stage("update")


[export]
def draw
    drawBack()
    enable_alpha_blend()
    decs_stage("draw_collidable")
    decs_stage("draw_floating")
    disable_alpha_blend()
    decs_stage("draw")
    drawHud()
    fps()


// CONTROLS ////////////////////////////////////////////////////////////////////

def processControls
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    for idx, control in range(length(CONTROLS)), CONTROLS
        control |> invoke(idx)


def racketSet(racketIdx : int; newPos : float)
    query() <| $(var racket : CompRacket)
        if racketIdx != racket.index
            return
        var posTarget = newPos - ceil(newPos)
        if posTarget < 0.0
            posTarget += 1.0
        racket.posTarget = posTarget


def racketAdd(racketIdx : int; deltaPos : float)
    query() <| $(var racket : CompRacket)
        if racketIdx != racket.index
            return
        var posTarget = racket.posTarget + deltaPos
        posTarget -= ceil(posTarget)
        if posTarget < 0.0
            posTarget += 1.0
        racket.posTarget = posTarget


def racketAction(racketIdx : int)
    query() <| $(var eid : EntityId; var racket : CompRacket)
        if racketIdx != racket.index
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


// BOOSTER /////////////////////////////////////////////////////////////////////

// mostly as to do list
enum BoosterType
    None
    Life        // immediate: +1 to racket lives
    Points      // immediate: +50 / +100 / +250 points to score
    Slower      // immediate: slow down own balls
    Faster      // immediate: accelerate own balls
    Multiplier  // immediate: add 2 balls more to every own ball
    Attractor   // immediate: direct own balls straight to racket position
    Braking     // continuous: lower maximum speed of racket
    Afterburner // continuous: higher speed of racket
    Absorber    // continuous: slow down any ball on bounce
    Shortener   // continuous: decrease size of racket
    Enlarger    // continuous: increase size of racket
    Shield      // continuous: inpenetrable circular shield for own balls
    Crusher     // continuous: own balls are breaking through without bounce
    Sticky      // continuous: catch ball instead of bouncing
    Autoaimer   // continuous: moves racket to nearest own ball
    Blaster     // continuous: laser beam to shoot stones
    Launcher    // once: rocket launcher with splash damage
    Spawner     // once: throw ball from racket


struct BoosterDesc
    typ : BoosterType
    prob : float
    icon : string
    lifetime : float
    onStart : function<(index:int):void>
    onAction : function<(index:int):void>
    onFinish : function<(index:int):void>


let boosters <- mkMoveBoosters([{ auto[]
    [[BoosterDesc
        typ = BoosterType Life,
        prob = 1.0,
        icon = "*",
        lifetime = 0.0 ]]
}])


def mkMoveBoosters(var list : array<BoosterDesc>)
    var res : table<BoosterType; BoosterDesc>
    for boost in list
        res[boost.typ] <- boost
    return <- res


[decs_template]
struct CompBooster
    pos : float2
    vel : float2
    rot : float
    rotv : float
    typ : BoosterType


def createBooster(pos, vel : float2; typ : BoosterType)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompBooster
            pos = pos,
            vel = vel,
            rot = random(0.0, PI * 2.0),
            rotv = random(-0.2, 0.2),
            typ = typ ]])


[decs(stage = update)]
def updateBooster(var eid : EntityId; var boost : CompBooster)
    boost.pos += boost.vel
    boost.rot += boost.rotv
    boost.rotv *= 0.993
    if !isCollide(float2(), boost.pos, VOID_RADIUS)
        delete_entity(eid)


[decs(stage = draw_floating)]
def drawBooster(var boost : CompBooster)
    imgBooster |> draw_image_transformed(
        screenCenter.x + boost.pos.x, screenCenter.y + boost.pos.y,
        imgBoosterTile, 0xFFFFCC66, imgBoosterSize, boost.rot)  


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
    booster : BoosterType


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
def updateStone(var eid : EntityId; var stone : CompStone)
    if stone.damage >= stone.resist
        delete_entity(eid)
        genParticleBlast(stone.pos, stone.radius, 3.0, STONE_COLORS[stone.resist][0])


[decs(stage = draw_collidable)]
def drawStone(var stone : CompStone)
    let color = STONE_COLORS[stone.resist][min(stone.damage, stone.resist)]
    let radius = stone.radius * 2.0
    imgStone |> draw_image_transformed(screenCenter.x + stone.pos.x, screenCenter.y + stone.pos.y, imgStoneTile, color, float2(radius, radius), 0.0)  


// BALLS ///////////////////////////////////////////////////////////////////////

[decs_template]
struct CompBall
    pos : float2
    vel : float2
    owner : EntityId


def createBall(var ownerId : EntityId)
    let radius = random(0.0, 250.0)
    let angle = random(0.0, PI * 2.0)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompBall
            owner = ownerId,
            pos = float2(radius * cos(angle), radius * sin(angle)),
            vel = float2(random(-5.0, 5.0), random(-5.0, 5.0)) ]])
    query(ownerId) <| $(var racket : CompRacket)
        ++racket.balls


[decs(stage = update)]
def updateBall(var eid : EntityId; var ball : CompBall)
    ball.pos += ball.vel
    if !isCollide(float2(), ball.pos, VOID_RADIUS)
        // ball is lost
        query() <| $(var eid : EntityId; var racket : CompRacket)
            if ball.owner != eid
                return
            --racket.balls
            if racket.balls <= 0
                --racket.lives
                if racket.lives <= 0
                    delete_entity(ball.owner)
        delete_entity(eid)
        return

    query() <| $(var eid : EntityId; var racket : CompRacket)
        if !isCollide(float2(), ball.pos, racket.radius)
            let pos = posToArc(ball.pos)
            let halfArc = racket.size / (PI * 4.0 * racket.radius)
            var posMin = racket.pos - halfArc
            posMin -= floor(posMin)
            if posMin < 0.0
                posMin += 1.0
            var posMax = racket.pos + halfArc
            posMax -= floor(posMax)
            if (posMin <= pos) == (pos <= posMax)
                let norm = normalize(-ball.pos)
                ball.vel -= 2.0 * norm * dot(ball.vel, norm)
                if ball.owner != eid
                    // take possession of another's ball on bounce
                    ball.owner = eid
                    ++racket.balls

    query() <| $(var stone : CompStone)
        if isCollide(ball.pos, stone.pos, BALL_RADIUS + stone.radius)
            let norm = normalize(stone.pos - ball.pos)
            ball.vel -= 2.0 * norm * dot(ball.vel, norm)
            ++stone.damage
            if stone.damage == stone.resist
                query() <| $(var eid : EntityId; var racket : CompRacket)
                    if ball.owner != eid
                        return
                    let bonus = stone.resist * 5
                    createInfo(stone.pos, norm, bonus, racket.color)
                    racket.score += bonus
                    let outAngle = posToArc(stone.pos) * PI * 2.0
                    let outDir = float2(cos(outAngle), sin(outAngle))
                    createBooster(stone.pos, outDir, BoosterType None)


[decs(stage = draw_collidable)]
def drawBall(var ball : CompBall)
    var color = 0x666666
    query() <| $(var eid : EntityId; var racket : CompRacket)
        if ball.owner == eid
            color = racket.color
    imgBall |> draw_image(screenCenter.x + ball.pos.x - BALL_RADIUS,
        screenCenter.y + ball.pos.y - BALL_RADIUS, color)


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
    bonus : int
    color : uint
    lifetime : float


def createInfo(pos, vel : float2; bonus : int; color : uint)
    create_entity <| @(eid, cmp)
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[CompInfo pos = pos, vel = vel, bonus = bonus, color = color, lifetime = 0.8 ]])


[decs(stage = update)]
def updateInfo(var eid : EntityId; var info : CompInfo)
    info.pos += info.vel
    info.vel *= 0.97
    info.lifetime -= get_delta_time()
    if info.lifetime <= 0.0
        delete_entity(eid)


[decs(stage = draw)]
def drawInfo(var info : CompInfo)
    set_font_size(12)
    text_out(screenCenter.x + info.pos.x, screenCenter.y + info.pos.y, "+{info.bonus}", info.color)


// PARTICLES ///////////////////////////////////////////////////////////////////

[decs_template]
struct CompParticle
    pos : float2
    vel : float2
    acc : float2
    color : uint
    lifetime : float


[decs(stage = update)]
def updateParticle(var eid : EntityId; var part : CompParticle)
    part.pos += part.vel
    part.vel += part.acc
    part.lifetime -= get_delta_time()
    if part.lifetime <= 0.0
        delete_entity(eid)


[decs(stage = draw)]
def drawParticle(var part : CompParticle)
    let x = screenCenter.x + part.pos.x
    let y = screenCenter.y + part.pos.y
    line(x, y, x - part.vel.x, y - part.vel.y, part.color)


def genParticleBlast(pos : float2; radius, intensity : float; color : uint)
    for i in range(int(intensity * 50.0))
        let dist = random(0.0, radius)
        let angle = random(0.0, PI * 2.0)
        let speed = random(0.5, intensity * 1.7)
        let vel = float2(speed * cos(angle), speed * sin(angle))
        create_entity <| @(eid, cmp)
            cmp |> set("eid", eid)
            apply_decs_template(cmp, [[CompParticle
                pos = pos + float2(dist * cos(angle), dist * sin(angle)),
                vel = vel,
                acc = -vel * 0.07 + float2(random(-0.06, 0.06), random(-0.06, 0.06)),
                color = color,
                lifetime = intensity / 20.0 ]])


// HUD /////////////////////////////////////////////////////////////////////////

def drawBack
    imgBackground |> draw_image_transformed(0.0, 0.0,
        imgBackgroundTile, 0xFFFFFFFF, imgBackgroundSize, 0.0, 0.0, 0.0)  


def drawHud
    query() <| $(var racket : CompRacket)
        var x = get_screen_width() - 120 * racket.index

        // score
        x -= 70
        set_font_size(22)
        text_out(x, 3, string(racket.score), racket.color)

        // booster
        find(boosters, racket.booster) <| $(booster : BoosterDesc?)
            if booster == null
                return
            x -= 26
            fill_rect(x, 7, 20, 20, racket.color)
            text_out(x + 3, 3, booster.icon, 0x000000)

        // lives
        for i in range(racket.lives)
            x -= 8
            fill_rect(x, 10, 3, 14, racket.color)


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
            let alpha = ratio * 0.5 + 0.5
            let fade = ratio * 0.75 + 0.25
            faded[resist][damage] = (colorCompFade(0xFF000000, alpha, 24u)
                | colorCompFade(color, fade, 16u)
                | colorCompFade(color, fade, 8u)
                | colorCompFade(color, fade))
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

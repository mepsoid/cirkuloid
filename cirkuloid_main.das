require daslib/media
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

require cirkuloid_ds
require cirkuloid_graph

var center : float2
var game : Game
var keyboardSpeed : float


def updateControls()
    var posTarget = game.racket.posTarget

    // keyboard controls
    if get_key(VK_LEFT)
        posTarget -= keyboardSpeed
    if get_key(VK_RIGHT)
        posTarget += keyboardSpeed

    // mouse controls
    let mouseMoved : float2 = get_mouse_position_delta()
    if mouseMoved.x != 0.0 || mouseMoved.y != 0.0
        posTarget = posToAngle(get_mouse_position(), center)

    // gamepad controls
    let axisMovedX = get_axis(AXIS_PRIMARY_X)
    let axisMovedY = get_axis(AXIS_PRIMARY_Y)
    if axisMovedX * axisMovedX + axisMovedY * axisMovedY > 0.15 // gamepad dead zone
        posTarget = posToAngle(float2(axisMovedX, axisMovedY))
    
    posTarget = posTarget - ceil(posTarget)
    if posTarget < 0.0
        posTarget += 1.0
    game.racket.posTarget = posTarget


[export]
def initialize
    set_window_title("cirkuloid")
    center = float2(
        float(get_screen_width()) / 2.0,
        float(get_screen_height()) / 2.0)
    game.racket = Racket()


[export]
def act(dt: float)
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    keyboardSpeed = dt / game.racket.posSpeed // adjust speed for any FPS
    updateControls()


[export]
def draw
    let halfArc = game.racket.size / (PI * 4.0 * game.racket.radius)
    let elem = [[Drawable
        x = center.x,
        y = center.y,
        color = game.racket.color,
        radius = game.racket.radius,
        weight = 8.0,
        start = game.racket.posTarget - halfArc,
        end = game.racket.posTarget + halfArc
    ]]
    render(elem)

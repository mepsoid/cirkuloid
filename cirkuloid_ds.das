
struct Racket
    color : uint = 0xFFCC33
    radius : float = 300.0
    size : float = 40.0
    pos : float // current position
    posTarget : float // target position
    posSpeed : float = 0.75 // speed of changing position per second

struct Game
    racket : Racket

struct Drawable
    x, y: float
    color : uint
    width : float
    height : float
    radius : float
    weight : float // width of the sector
    start, end : float // values in range 0.0..1.0

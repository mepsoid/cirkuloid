require daslib/media
require cirkuloid_ds

let
    POLY_FACET = 10.0 // max size of polygon interpolation in pixels

def render(elem : Drawable)
    if elem.radius <= 0.0
        // box
        fill_rect(elem.x, elem.y, elem.width, elem.height, elem.color)
    elif elem.start == elem.end
        // circle
        fill_circle(elem.x, elem.y, elem.radius, elem.color)
    else
        // sector
        var points : array<float2>
        var start = elem.start - floor(elem.start)
        if start < 0.0
            start += 1.0
        var end = elem.end - floor(elem.end)
        if end < start
            end += 1.0
        // inner arc
        var arc = PI * 2.0 * (end - start)
        var steps = abs(ceil(arc * elem.radius / POLY_FACET))
        var delta = arc / steps
        var angle = PI * 2.0 * start
        for i in range(0, int(steps) + 1)
            points |> push(float2(
                elem.x + elem.radius * cos(angle),
                elem.y + elem.radius * sin(angle)))
            angle += delta
        // outer arc
        steps = abs(ceil(arc * (elem.radius + elem.weight) / POLY_FACET))
        delta = arc / steps
        angle = PI * 2.0 * end
        for i in range(0, int(steps) + 1)
            points |> push(float2(
                elem.x + (elem.radius + elem.weight) * cos(angle),
                elem.y + (elem.radius + elem.weight) * sin(angle)))
            angle -= delta
        polygon(points, elem.color)


def posToAngle(position : float2; center : float2 = float2())
    return atan2(position.y - center.y, position.x - center.x) / (PI * 2.0)

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
        var start = elem.start - floor(elem.start)
        if start < 0.0
            start += 1.0
        var end = elem.end - floor(elem.end)
        if end < start
            end += 1.0
        let angleEnd = PI * 2.0 * end
        var angleIn = PI * 2.0 * start
        var angleOut = angleIn
        let arc = angleEnd - angleIn
        let polys = ceil(arc * elem.radius / POLY_FACET)
        let deltaIn = arc / polys
        let deltaOut = arc / ceil(arc * (elem.radius + elem.weight) / POLY_FACET)
        for i in range(0, int(polys))
            var points : array<float2>
            points |> sectorPoint(elem, elem.radius, angleIn)
            angleIn += deltaIn
            while (angleOut < angleIn)
                points |> sectorPoint(elem, elem.radius + elem.weight, angleOut)
                angleOut += deltaOut
            points |> sectorPoint(elem, elem.radius + elem.weight, min(angleOut, angleEnd))
            points |> sectorPoint(elem, elem.radius, angleIn)
            fill_convex_polygon(points, elem.color)

def sectorPoint(var points : array<float2>; elem : Drawable; radius: float; angle : float)
    points |> push(float2(elem.x + radius * cos(angle), elem.y + radius * sin(angle)))

def posToAngle(position : float2; center : float2 = float2())
    return atan2(position.y - center.y, position.x - center.x) / (PI * 2.0)

// Theme “Fluent”: the background is a radial gradient made of the Windows accent color, no border or separators.
// Changes color together with the Windows accent (Settings > Personalization > Colors).
// A theme by someone else (Simple, Fluent Minimalistic Menu, from the Nilesoft community): only theme.nss is taken, image.align = 200000 fixed to 2
$preset_theme = 'fluent'

theme
{
    $antiaccent = color.lighten(color.lighten(color.invert(color.accent_light1)))
    $mild_accent = color.lighten(color.lighten(color.lighten(color.accent_light1)))

    name = "modern"
    dark = true

    background
    {
        // radial = [cx, cy, r, fx, fy]; stop = [position 0..1, color, opacity]
        gradient
        {
            enabled = true
            radial = [0, 0, 600, 50, 80]
            stop = [
                [0.0, color.accent, 45],
                [0.15, color.accent_light2, 30],
                [0.25, color.accent, 25],
                [0.5, color.accent_dark3, 19],
                [0.7, color.accent_light1, 35],
                [0.85, color.accent_light2, 25],
                [1.0, color.accent, 31]
            ]
        }
    }

    border
    {
        enabled = true
        size = 1
        color = antiaccent
        opacity = 0
        radius = 4
    }

    separator
    {
        size = 0
        color = antiaccent
        opacity = 0
        margin = 0
    }

    image
    {
        enabled = true
        color = [mild_accent, antiaccent, color.accent_light1]
        scale = true
        align = 2
    }

    layout
    {
        popup = 0
    }
}

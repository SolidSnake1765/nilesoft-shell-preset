// Theme “Turquoise glass”: black glass, turquoise text and border.
// A theme by someone else (Neon Blue Tinted Glass, from the Nilesoft community) for Nilesoft 1.8 - only its theme block is taken,
// state names are converted to the 1.9 syntax (normal-disabled -> normal.disabled)
$preset_theme = 'glass'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #000000
        opacity = 95
        effect = 1 // 0 = off, 1 = transparent, 2 = blur, 3 = acrylic
    }

    border
    {
        enabled = true
        size = 1
        color = #0BEBFA
        opacity = 100
        radius = 2
    }

    shadow
    {
        enabled = true
        size = 5
        color = #11111B
        opacity = 5
    }

    item
    {
        opacity = 100
        prefix = 1
        text.normal = #8AEAEF
        text.select = #8AEAEF
        text.normal.disabled = #6DC2C6
        text.select.disabled = #6DC2C6
        back.select = #22585C
        back.select.disabled = #334D4F
    }

    symbol
    {
        normal = #86CCD0
        select = #86CCD0
        normal.disabled = #62ABAF
        select.disabled = #62ABAF
    }

    image
    {
        enabled = true
        color = [#B4DCE6, #5FC8CE, #B4DCE6]
        align = 2
    }

    separator
    {
        size = 0
        color = #928B6A
    }

    layout
    {
        popup = 0
    }
}

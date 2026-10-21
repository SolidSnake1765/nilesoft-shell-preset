// Theme “Neon”: almost black background, cyan border glow, magenta item highlight
$preset_theme = 'neon'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #0B0B14
        opacity = 85
        effect = 3 // 0 = off, 1 = transparent, 2 = blur, 3 = acrylic
    }

    border
    {
        enabled = true
        size = 1
        color = #00E5FF
        opacity = 90
        radius = 3
    }

    // A shadow of the border color without offset gives a glow
    shadow
    {
        enabled = true
        size = 12
        color = #00E5FF
        opacity = 30
        offset = 0
    }

    item
    {
        radius = 3
        padding = [10, 4]
        text.normal = #E6F7FF
        text.select = #FFFFFF
        text.normal.disabled = #4A5A66
        text.select.disabled = #4A5A66
        back.select = #FF2E88
    }

    symbol
    {
        chevron.normal = #00E5FF
        chevron.select = #FFFFFF
        checkmark.normal = #00E5FF
        checkmark.select = #FFFFFF
    }

    // Colors of the glyph icons
    image.color = [#00E5FF, #FF2E88, #E6F7FF]

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        color = #00E5FF
        opacity = 35
        margin = [8, 4]
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

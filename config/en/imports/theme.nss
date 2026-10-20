theme
{
    name = "modern"
    dark = auto

    // Background: denser than the default (opacity = 5) and acrylic instead of plain blur. Lower opacity = more transparent
    background
    {
        color = #202020
        opacity = 40
        effect = 3 // 0 = off, 1 = transparent, 2 = blur, 3 = acrylic
    }

    // Menu border and rounded corners
    border
    {
        enabled = true
        size = 1
        color = #3A3B3C
        opacity = 100
        radius = 3
    }

    // Soft shadow under the menu
    shadow
    {
        enabled = true
        size = 5
        color = #000000
        opacity = 20
        offset = 2
    }

    // Items: rounded highlight in the Windows accent color, slightly bigger padding
    item
    {
        radius = 3
        padding = [10, 4] // left/right, top/bottom
        back.select = color.accent_dark2
        text.select = #FFFFFF
    }

    // Submenu arrows and checkmarks - also in the accent color
    symbol
    {
        chevron.normal = color.accent_light2
        chevron.select = #FFFFFF
        checkmark.normal = color.accent_light2
        checkmark.select = #FFFFFF
    }

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        margin = [8, 4] // left/right, top/bottom
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

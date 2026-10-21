// Theme “Light”: like the Windows 11 menu in light mode - light acrylic, dark text, Windows accent color
$preset_theme = 'light'

theme
{
    name = "modern"
    dark = false

    background
    {
        color = #F9F9F9
        opacity = 75
        effect = 3 // 0 = off, 1 = transparent, 2 = blur, 3 = acrylic
    }

    border
    {
        enabled = true
        size = 1
        color = #D9D9D9
        opacity = 100
        radius = 3
    }

    shadow
    {
        enabled = true
        size = 8
        color = #000000
        opacity = 12
        offset = 2
    }

    item
    {
        radius = 3
        padding = [10, 4]
        text.normal = #1B1B1B
        text.select = #1B1B1B
        text.normal.disabled = #A0A0A0
        text.select.disabled = #A0A0A0
        back.select = #E5E5E5
    }

    symbol
    {
        chevron.normal = color.accent
        chevron.select = color.accent
        checkmark.normal = color.accent
        checkmark.select = color.accent
    }

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        color = #E0E0E0
        margin = [8, 4]
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

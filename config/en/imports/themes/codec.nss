// Theme “Codec”: the green radio screen from Metal Gear Solid - monospace font, square corners, green glow
$preset_theme = 'codec'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #001A0E
        opacity = 90
        effect = 3 // 0 = off, 1 = transparent, 2 = blur, 3 = acrylic
    }

    border
    {
        enabled = true
        size = 1
        color = #3CFF7A
        opacity = 70
        radius = 0
    }

    shadow
    {
        enabled = true
        size = 10
        color = #3CFF7A
        opacity = 22
        offset = 0
    }

    item
    {
        radius = 0
        padding = [10, 4]
        text.normal = #7CFFA4
        text.select = #EFFFF3
        text.normal.disabled = #2E6B45
        text.select.disabled = #2E6B45
        back.select = #1F7A42
    }

    symbol
    {
        chevron.normal = #3CFF7A
        chevron.select = #EFFFF3
        checkmark.normal = #3CFF7A
        checkmark.select = #EFFFF3
    }

    image.color = [#3CFF7A, #1F7A42, #EFFFF3]

    font
    {
        name = "Consolas"
    }

    separator
    {
        color = #3CFF7A
        opacity = 40
        margin = [8, 4]
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

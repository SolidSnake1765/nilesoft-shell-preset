// Тема «Dracula»: известная тёмная палитра редакторов кода (draculatheme.com) — фиолетовый, розовый, зелёный
$preset_theme = 'dracula'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #282A36
        opacity = 92
        effect = 3 // 0 = выкл, 1 = прозрачный, 2 = размытие, 3 = акрил
    }

    border
    {
        enabled = true
        size = 1
        color = #44475A
        opacity = 100
        radius = 3
    }

    shadow
    {
        enabled = true
        size = 8
        color = #000000
        opacity = 30
        offset = 2
    }

    item
    {
        radius = 3
        padding = [10, 4]
        text.normal = #F8F8F2
        text.select = #FFFFFF
        text.normal.disabled = #6272A4
        text.select.disabled = #6272A4
        back.select = #44475A
        border.select = #BD93F9
    }

    symbol
    {
        chevron.normal = #FF79C6
        chevron.select = #FF79C6
        checkmark.normal = #50FA7B
        checkmark.select = #50FA7B
    }

    image.color = [#BD93F9, #FF79C6, #F8F8F2]

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        color = #44475A
        margin = [8, 4]
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

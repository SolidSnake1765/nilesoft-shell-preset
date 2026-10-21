// Тема «Nord»: спокойная северная палитра (nordtheme.com) — серо-синий фон, ледяные голубые акценты
$preset_theme = 'nord'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #2E3440
        opacity = 92
        effect = 3 // 0 = выкл, 1 = прозрачный, 2 = размытие, 3 = акрил
    }

    border
    {
        enabled = true
        size = 1
        color = #434C5E
        opacity = 100
        radius = 3
    }

    shadow
    {
        enabled = true
        size = 8
        color = #000000
        opacity = 25
        offset = 2
    }

    item
    {
        radius = 3
        padding = [10, 4]
        text.normal = #ECEFF4
        text.select = #ECEFF4
        text.normal.disabled = #616E88
        text.select.disabled = #616E88
        back.select = #5E81AC
    }

    symbol
    {
        chevron.normal = #88C0D0
        chevron.select = #ECEFF4
        checkmark.normal = #88C0D0
        checkmark.select = #ECEFF4
    }

    image.color = [#88C0D0, #81A1C1, #ECEFF4]

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        color = #434C5E
        margin = [8, 4]
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

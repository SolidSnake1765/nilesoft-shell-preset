// Тема «Бирюзовое стекло»: чёрное стекло, бирюзовый текст и рамка.
// Чужая тема (Neon Blue Tinted Glass, из сообщества Nilesoft) для Nilesoft 1.8 — из неё взят только блок theme,
// названия состояний переведены на синтаксис 1.9 (normal-disabled -> normal.disabled)
$preset_theme = 'glass'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #000000
        opacity = 95
        effect = 1 // 0 = выкл, 1 = прозрачный, 2 = размытие, 3 = акрил
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

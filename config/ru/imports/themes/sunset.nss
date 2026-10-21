// Тема «Закат»: градиент сверху вниз — от тёмно-фиолетового к кирпично-оранжевому, тёплые акценты
$preset_theme = 'sunset'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #24123F
        opacity = 95
        effect = 3 // 0 = выкл, 1 = прозрачный, 2 = размытие, 3 = акрил
        // linear = [x1, x2, y1, y2] в процентах: [0, 0, 0, 100] — сверху вниз; stop = [место 0..1, цвет, непрозрачность]
        gradient
        {
            enabled = true
            linear = [0, 0, 0, 100]
            stop = [ [0, #24123F, 95], [0.6, #5B1F6B, 95], [1, #9A3B2A, 95] ]
        }
    }

    border
    {
        enabled = true
        size = 1
        color = #FF9E6D
        opacity = 60
        radius = 3
    }

    shadow
    {
        enabled = true
        size = 10
        color = #000000
        opacity = 30
        offset = 2
    }

    item
    {
        radius = 3
        padding = [10, 4]
        text.normal = #FFF1E6
        text.select = #FFFFFF
        text.normal.disabled = #9C7F94
        text.select.disabled = #9C7F94
        back.select = #E2583E
    }

    symbol
    {
        chevron.normal = #FFB38A
        chevron.select = #FFFFFF
        checkmark.normal = #FFB38A
        checkmark.select = #FFFFFF
    }

    image.color = [#FFB38A, #E2583E, #FFF1E6]

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        color = #FFB38A
        opacity = 30
        margin = [8, 4]
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

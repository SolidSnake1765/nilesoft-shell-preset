// Тема «Неон»: почти чёрный фон, бирюзовое свечение рамки, малиновая подсветка пунктов
$preset_theme = 'neon'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #0B0B14
        opacity = 85
        effect = 3 // 0 = выкл, 1 = прозрачный, 2 = размытие, 3 = акрил
    }

    border
    {
        enabled = true
        size = 1
        color = #00E5FF
        opacity = 90
        radius = 3
    }

    // Тень того же цвета, что рамка, и без сдвига — получается свечение
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

    // Цвета значков-глифов
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

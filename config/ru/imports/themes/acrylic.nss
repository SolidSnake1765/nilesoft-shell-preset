// Тема «Акрил» (по умолчанию): modern, доработанная — плотный акриловый фон, тень, цвет акцента Windows
$preset_theme = 'acrylic'

theme
{
    name = "modern"
    dark = true

    // Меньше opacity — прозрачнее
    background
    {
        color = #202020
        opacity = 40
        effect = 3 // 0 = выкл, 1 = прозрачный, 2 = размытие, 3 = акрил
    }

    // Рамка и скругление углов меню
    border
    {
        enabled = true
        size = 1
        color = #3A3B3C
        opacity = 100
        radius = 3
    }

    // Мягкая тень под меню
    shadow
    {
        enabled = true
        size = 5
        color = #000000
        opacity = 20
        offset = 2
    }

    // Пункты: скруглённая подсветка цветом акцента Windows, чуть больше отступы
    item
    {
        radius = 3
        padding = [10, 4] // слева/справа, сверху/снизу
        back.select = color.accent_dark2
        text.select = #FFFFFF
    }

    // Стрелки подменю и галочки — тоже цветом акцента
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
        margin = [8, 4] // слева/справа, сверху/снизу
    }

    image.align = 2

    layout
    {
        popup = 0
    }
}

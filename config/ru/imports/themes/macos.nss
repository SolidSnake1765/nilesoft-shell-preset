// Тема «macOS»: сильно скруглённое меню без значков, тонкая светлая рамка — в духе меню macOS.
// Чужая тема (Mac os Styled Context menu, из сообщества Nilesoft), подогнана под пресет: шрифт SF Pro заменён на Segoe UI Variable
// (SF Pro есть только на Mac)
$preset_theme = 'macos'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #2A2B2B
        opacity = 3
        effect = [3, #2A2B2B, 30] // акрил: [3, оттенок, непрозрачность оттенка]
    }

    // Тень в 1 пиксель без сдвига — тёмная обводка вокруг светлой рамки
    shadow
    {
        enabled = true
        size = 1
        color = #000000
        opacity = 100
        offset = 0
    }

    border
    {
        enabled = true
        size = 1
        color = #D3D3D3
        opacity = 26
        radius = 20
        padding
        {
            top = 4
            bottom = 4
        }
    }

    item
    {
        padding
        {
            top = 2
            bottom = 2
        }
        back.select = color.accent_dark3
    }

    // Как в macOS — без значков
    image.enabled = false

    font
    {
        name = "Segoe UI Variable Text"
    }

    separator
    {
        size = 1
        opacity = 17
        margin
        {
            left = 12
            right = 12
        }
    }

    layout
    {
        popup = 0
    }
}

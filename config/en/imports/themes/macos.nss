// Theme “macOS”: a strongly rounded menu without icons, thin light border - in the spirit of macOS menus.
// A theme by someone else (Mac os Styled Context menu, from the Nilesoft community), adapted to the preset: the SF Pro font is replaced with Segoe UI Variable
// (SF Pro is only on a Mac)
$preset_theme = 'macos'

theme
{
    name = "modern"
    dark = true

    background
    {
        color = #2A2B2B
        opacity = 3
        effect = [3, #2A2B2B, 30] // acrylic: [3, tint, tint opacity]
    }

    // A 1 pixel shadow without offset - a dark outline around the light border
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

    // Like in macOS - no icons
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

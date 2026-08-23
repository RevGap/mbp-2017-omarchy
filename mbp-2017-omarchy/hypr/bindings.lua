-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- MacBookPro14,3 (2017 Touch Bar): this machine has no physical F-row, so no key
-- ever emits XF86KbdBrightnessUp/Down and Omarchy's default media.lua bindings for
-- the keyboard backlight are unreachable. Bind them to keys that physically exist.
o.bind("SUPER + CTRL + UP", "Keyboard brightness up", "omarchy-brightness-keyboard up", { locked = true, repeating = true })
o.bind("SUPER + CTRL + DOWN", "Keyboard brightness down", "omarchy-brightness-keyboard down", { locked = true, repeating = true })
o.bind("SUPER + CTRL + BACKSLASH", "Keyboard backlight cycle", "omarchy-brightness-keyboard cycle", { locked = true })

-- Display brightness: XF86MonBrightnessUp/Down are equally unreachable on this
-- chassis (no F-row), so mirror them onto the arrow cluster alongside the
-- keyboard backlight binds above.
o.bind("SUPER + SHIFT + CTRL + UP", "Brightness up", "omarchy-brightness-display +5%", { locked = true, repeating = true })
o.bind("SUPER + SHIFT + CTRL + DOWN", "Brightness down", "omarchy-brightness-display 5%-", { locked = true, repeating = true })

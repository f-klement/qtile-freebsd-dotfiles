# Copyright (c) 2010 Aldo Cortesi
# Copyright (c) 2010, 2014 dequis
# Copyright (c) 2012 Randall Ma
# Copyright (c) 2012-2014 Tycho Andersen
# Copyright (c) 2012 Craig Barnes
# Copyright (c) 2013 horsik
# Copyright (c) 2013 Tao Sauvage
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import os
import colors
import subprocess
from zoneinfo import ZoneInfo 
from libqtile import bar, layout, qtile, widget, hook
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal
from qtile_extras import widget as xwidget 

mod = "mod4"
terminal = "kitty"
browser = "flatpak run com.brave.Browser"
editor  = "flatpak run com.vscodium.codium"
files = "nautilus"

keys = [
    # A list of available commands that can be bound to keys can be found
    # at https://docs.qtile.org/en/latest/manual/config/lazy.html
    # Switch between windows
    Key([mod], "Left",  lazy.layout.left(),  desc="Focus left"),
    Key([mod], "Right", lazy.layout.right(), desc="Focus right"),
    Key([mod], "Up",    lazy.layout.up(),    desc="Focus up"),
    Key([mod], "Down",  lazy.layout.down(),  desc="Focus down"),
    Key([mod], "t", lazy.layout.next(), desc="Move window focus to other window"),
    # Move windows between left/right columns or move up/down in current stack.
    # Moving out of range in Columns layout will create new column.
    Key([mod, "shift"], "Left", lazy.layout.shuffle_left(), desc="Move window to the left"),
    Key([mod, "shift"], "Right", lazy.layout.shuffle_right(), desc="Move window to the right"),
    Key([mod, "shift"], "Down", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "Up", lazy.layout.shuffle_up(), desc="Move window up"),
    # Grow windows. If current window is on the edge of screen and direction
    # will be to screen edge - window would shrink.
    Key([mod, "control"], "Left", lazy.layout.grow_left(), desc="Grow window to the left"),
    Key([mod, "control"], "Right", lazy.layout.grow_right(), desc="Grow window to the right"),
    Key([mod, "control"], "Down", lazy.layout.grow_down(), desc="Grow window down"),
    Key([mod, "control"], "Up", lazy.layout.grow_up(), desc="Grow window up"),
    # --- Move *floating* window 40 px at a time (no conflict with mod-shift keys) ---
    Key([mod, "mod1"], "Left",  lazy.window.move_floating(-40, 0),  desc="Nudge floating window left"),
    Key([mod, "mod1"], "Right", lazy.window.move_floating( 40, 0),  desc="Nudge floating window right"),
    Key([mod, "mod1"], "Up",    lazy.window.move_floating( 0, -40), desc="Nudge floating window up"),
    Key([mod, "mod1"], "Down",  lazy.window.move_floating( 0, 40),  desc="Nudge floating window down"),    
    Key([mod], "n", lazy.layout.normalize(), desc="Reset all window sizes"),
    # new launch shortcuts
    Key([mod], "b", lazy.spawn(browser), desc="Launch browser"),
    Key([mod], "d", lazy.spawn(files),   desc="Launch file manager"),
    Key([mod, "mod1"], "space", lazy.spawn("/usr/local/bin/rofi -show drun"), desc="Launch rofi"), 
    Key([mod], "e", lazy.spawn(editor), desc="Launch VSCodium"),
    # Toggle between split and unsplit sides of stack.
    # Split = all windows displayed
    # Unsplit = 1 window displayed, like Max layout, but still with
    # multiple stack panes
    Key(
        [mod, "shift"],
        "Return",
        lazy.layout.toggle_split(),
        desc="Toggle between split and unsplit sides of stack",
    ),
    Key([mod], "q", lazy.spawn(terminal), desc="Launch terminal"),
    # Toggle between different layouts as defined below
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),
    Key([mod,"mod1"], "x", lazy.window.kill(), desc="Kill focused window"),
    Key(
        [mod],
        "f",
        lazy.window.toggle_fullscreen(),
        desc="Toggle fullscreen on the focused window",
    ),
    Key([mod], "space", lazy.window.toggle_floating(), desc="Toggle floating on the focused window"),
    Key([mod, "control"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([mod, "control"], "q", lazy.shutdown(), desc="Shutdown Qtile"),
    Key([mod], "r", lazy.spawncmd(prompt="Run: "), desc="Spawn a command"),
]

# Add key bindings to switch VTs in Wayland.
# We can't check qtile.core.name in default config as it is loaded before qtile is started
# We therefore defer the check until the key binding is run by using .when(func=...)
for vt in range(1, 8):
    keys.append(
        Key(
            ["control", "mod1"],
            f"f{vt}",
            lazy.core.change_vt(vt).when(func=lambda: qtile.core.name == "wayland"),
            desc=f"Switch to VT{vt}",
        )
    )


groups = [Group(i) for i in "123456789"]

for i in groups:
    keys.extend(
        [
            # mod + group number = switch to group
            Key(
                [mod],
                i.name,
                lazy.group[i.name].toscreen(),
                desc=f"Switch to group {i.name}",
            ),
            # mod + shift + group number = switch to & move focused window to group
            Key(
                [mod, "shift"],
                i.name,
                lazy.window.togroup(i.name, switch_group=True),
                desc=f"Switch to & move focused window to group {i.name}",
            ),
            # Or, use below if you prefer not to switch to that group.
            # # mod + shift + group number = move focused window to group
            # Key([mod, "shift"], i.name, lazy.window.togroup(i.name),
            #     desc="move focused window to group {}".format(i.name)),
        ]
    )

colors = colors.DoomOne

layout_theme = {"border_width": 1,
                "margin": 0,
                "border_focus": colors[7],
                "border_normal": colors[0]
                }


layouts = [
    layout.Columns(border_focus_stack=["#d75f5f", "#8f3d3d"], **layout_theme),
    layout.Spiral(main_pane="left", clockwise=True, **layout_theme),
    layout.Max(**layout_theme),
    # Try more layouts by unleashing below layouts.
    # layout.Stack(num_stacks=2),
    # layout.Bsp(),
    # layout.Matrix(),
    # layout.MonadTall(),
    # layout.MonadWide(),
    # layout.RatioTile(),
    # layout.Tile(),
    # layout.TreeTab(),
    # layout.VerticalTile(),
    # layout.Zoomy(),
]

widget_defaults = dict(
    font="JetBrainsMono Nerd Font",
    fontsize=12,
    padding=2,
    background=colors[0]
)

extension_defaults = widget_defaults.copy()

# ── helpers ───────────────────────────────────────────────────────────────
@lazy.function
def toggle_vol_text(qtile):
    w = qtile.widgets_map["pulsevolume"]
    w.fmt = "" if w.fmt.endswith("{}") else " {}"   # no percent sign
    w.bar.draw()
    
@lazy.function
def power_menu(qtile):
    qtile.cmd_spawn(
        "bash -c '"
        "choice=$(GTK_THEME=Adwaita:dark yad --width=200 --height=50 "
        "--title=\"Power Menu\" "
        "--button=\"Shutdown:0\" --button=\"Reboot:1\" "
        "--center --on-top --no-markup --undecorated); "
        "code=$?; "
        "if [ \"$code\" -eq 0 ]; then systemctl poweroff; "
        "elif [ \"$code\" -eq 1 ]; then systemctl reboot; fi'"
    )

# ──────────────────────────────────────────────────────────────────────────

def init_widgets():
    return [
        # ---- LEFT cluster ---------------------------------------------------
        widget.Spacer(length=4),  # tiny padding
        widget.GroupBox(
            padding_x=0,
            margin_x=1,
            active = colors[8],
            inactive = colors[9],
            rounded = True,
            highlight_color = colors[0],
            highlight_method = "line",
            this_current_screen_border = colors[7],
            this_screen_border = colors [4],
            other_current_screen_border = colors[7],
            other_screen_border = colors[4],
            disable_drag=True,
        ),
        widget.Prompt(name="prompt", prompt="Run: ", padding=5, foreground = colors[1]),
        widget.Spacer(length=6),
        # ---- centre ---------------------------------------------------------
        widget.Spacer(length=bar.STRETCH),
        widget.Clock(
            format="%H:%M   %d-%m-%Y",
            timezone=ZoneInfo("Europe/Vienna"),
            foreground = colors[1],
        ),
        widget.Spacer(length=bar.STRETCH),

        # ---- RIGHT cluster --------------------------------------------------
        widget.Net(
            # ▾/▴ are 1-char arrows from the Nerd-Font set
            format="{down:.0f}{down_suffix}▾{up:.0f}{up_suffix}▴",
            update_interval=3,
            mouse_callbacks={
                "Button3": lazy.spawn("nm-connection-editor"),  # right-click → open NetworkManager GUI
            },
            foreground = colors[5],
        ),
        #xwidget.Bluetooth(),                 # from qtile-extras
        #widget.Battery(format="  {percent:2.0%}", low_percentage=0.15),
        widget.PulseVolume(
            name="pulsevolume",
            foreground = colors[7],
            fmt=" {}",                       # single value, no % sign
            mouse_callbacks={
                "Button1": toggle_vol_text,                                           # show/hide value
                "Button2": lazy.spawn("pavucontrol"),                                 # open mixer
                "Button3": lazy.spawn("pactl set-sink-mute @DEFAULT_SINK@ toggle"),   # mute/unmute
                "Button4": lazy.spawn("pactl set-sink-volume @DEFAULT_SINK@ +5%"),    # vol +5 %
                "Button5": lazy.spawn("pactl set-sink-volume @DEFAULT_SINK@ -5%"),    # vol –5 %
            },
        ),
        widget.Memory(
            foreground = colors[8],
            format="{MemUsed:4.1f}G",   # e.g. “  7.6 G”
            measure_mem="G",               # tell the widget we want GiB/GB
            update_interval=2,
        ),
        widget.CPU(foreground = colors[4],format=" {load_percent:>3}%", update_interval=2),
        widget.Systray(icon_size=12, padding=2),
        widget.TextBox(
            text="⏻",
            padding=6,
            fontsize=16,
            mouse_callbacks={
                 "Button1": power_menu
            }
        ),
        widget.Spacer(length=4),
    ]

# For adding transparency to your bar, add (background="#00000000") to the "Screen" line(s)
# For ex: Screen(top=bar.Bar(widgets=init_widgets_screen2(), background="#00000000", size=24)),

screens = [
    Screen(top=bar.Bar(init_widgets(), 28, opacity=0.70, margin=[0, 0, 0, 0])),
]

# drag floating window with Mod + left-click
Drag([mod], "Button1", lazy.window.set_position_floating(),
     start=lazy.window.get_position()),


# Drag floating layouts.
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
floats_kept_above = True
cursor_warp = False
floating_layout = layout.Floating(
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),   # gitk
        Match(wm_class="dialog"),         # dialog boxes
        Match(wm_class="download"),       # downloads
        Match(wm_class="error"),          # error msgs
        Match(wm_class="file_progress"),  # file progress boxes
        Match(wm_class='kdenlive'),       # kdenlive
        Match(wm_class="makebranch"),     # gitk
        Match(wm_class="maketag"),        # gitk
        Match(wm_class="notification"),   # notifications
        Match(wm_class='pinentry-gtk-2'), # GPG key password entry
        Match(wm_class="ssh-askpass"),    # ssh-askpass
        Match(wm_class="toolbar"),        # toolbars
        Match(wm_class="Yad"),            # yad boxes
        Match(title="branchdialog"),      # gitk
        Match(title='Confirmation'),      # tastyworks exit box
        Match(title='Qalculate!'),        # qalculate-gtk
        Match(title="pinentry"),          # GPG key password entry
        Match(wm_class="rofi"),           # Rofi Launcher
    ]
)
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True

# If things like steam games want to auto-minimize themselves when losing
# focus, should we respect this or not?
auto_minimize = True

# When using the Wayland backend, this can be used to configure input devices.
wl_input_rules = None

# xcursor theme (string or None) and size (integer) for Wayland backend
wl_xcursor_theme = "Dracula"
wl_xcursor_size = 24

# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"

@hook.subscribe.startup_once
def start_once():
    home = os.path.expanduser('~')
    if qtile.core.name == "wayland":
        autostart_script = os.path.join(home, '.config/qtile/autostart_wayland.sh')
    else:
        autostart_script = os.path.join(home, '.config/qtile/autostart_x11.sh')
    subprocess.call([autostart_script])


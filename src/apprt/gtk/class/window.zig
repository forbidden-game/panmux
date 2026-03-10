const std = @import("std");
const build_config = @import("../../../build_config.zig");
const assert = @import("../../../quirks.zig").inlineAssert;
const adw = @import("adw");
const gdk = @import("gdk");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const i18n = @import("../../../os/main.zig").i18n;
const homedir = @import("../../../os/homedir.zig");
const apprt = @import("../../../apprt.zig");
const configpkg = @import("../../../config.zig");
const TitlebarStyle = configpkg.Config.GtkTitlebarStyle;
const input = @import("../../../input.zig");
const CoreSurface = @import("../../../Surface.zig");
const ext = @import("../ext.zig");
const gtk_version = @import("../gtk_version.zig");
const adw_version = @import("../adw_version.zig");
const gresource = @import("../build/gresource.zig");
const winprotopkg = @import("../winproto.zig");
const Common = @import("../class.zig").Common;
const Config = @import("config.zig").Config;
const Application = @import("application.zig").Application;
const CloseConfirmationDialog = @import("close_confirmation_dialog.zig").CloseConfirmationDialog;
const SplitTree = @import("split_tree.zig").SplitTree;
const Surface = @import("surface.zig").Surface;
const Tab = @import("tab.zig").Tab;
const DebugWarning = @import("debug_warning.zig").DebugWarning;
const CommandPalette = @import("command_palette.zig").CommandPalette;
const panmux_state = @import("../panmux_state.zig");
const panmux_ipc = @import("../../../panmux_ipc.zig");
const WeakRef = @import("../weak_ref.zig").WeakRef;

const log = std.log.scoped(.gtk_ghostty_window);

pub const Window = extern struct {
    const Self = @This();
    parent_instance: Parent,
    pub const Parent = adw.ApplicationWindow;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyWindow",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub const properties = struct {
        /// The active surface is the focus that should be receiving all
        /// surface-targeted actions. This is usually the focused surface,
        /// but may also not be focused if the user has selected a non-surface
        /// widget.
        pub const @"active-surface" = struct {
            pub const name = "active-surface";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?*Surface,
                .{
                    .accessor = gobject.ext.typedAccessor(
                        Self,
                        ?*Surface,
                        .{
                            .getter = Self.getActiveSurface,
                        },
                    ),
                },
            );
        };

        pub const config = struct {
            pub const name = "config";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                ?*Config,
                .{
                    .accessor = C.privateObjFieldAccessor("config"),
                },
            );
        };

        pub const debug = struct {
            pub const name = "debug";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .default = build_config.is_debug,
                    .accessor = gobject.ext.typedAccessor(Self, bool, .{
                        .getter = struct {
                            pub fn getter(_: *Self) bool {
                                return build_config.is_debug;
                            }
                        }.getter,
                    }),
                },
            );
        };

        pub const @"titlebar-style" = struct {
            pub const name = "titlebar-style";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                TitlebarStyle,
                .{
                    .default = .native,
                    .accessor = gobject.ext.typedAccessor(
                        Self,
                        TitlebarStyle,
                        .{
                            .getter = Self.getTitlebarStyle,
                        },
                    ),
                },
            );
        };

        pub const @"headerbar-visible" = struct {
            pub const name = "headerbar-visible";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .default = true,
                    .accessor = gobject.ext.typedAccessor(Self, bool, .{
                        .getter = Self.getHeaderbarVisible,
                    }),
                },
            );
        };

        pub const @"quick-terminal" = struct {
            pub const name = "quick-terminal";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .default = true,
                    .accessor = gobject.ext.privateFieldAccessor(
                        Self,
                        Private,
                        &Private.offset,
                        "quick_terminal",
                    ),
                },
            );
        };

        pub const @"tabs-autohide" = struct {
            pub const name = "tabs-autohide";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .default = true,
                    .accessor = gobject.ext.typedAccessor(Self, bool, .{
                        .getter = Self.getTabsAutohide,
                    }),
                },
            );
        };

        pub const @"tabs-wide" = struct {
            pub const name = "tabs-wide";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .default = true,
                    .accessor = gobject.ext.typedAccessor(Self, bool, .{
                        .getter = Self.getTabsWide,
                    }),
                },
            );
        };

        pub const @"tabs-visible" = struct {
            pub const name = "tabs-visible";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                bool,
                .{
                    .default = true,
                    .accessor = gobject.ext.typedAccessor(Self, bool, .{
                        .getter = Self.getTabsVisible,
                    }),
                },
            );
        };

        pub const @"toolbar-style" = struct {
            pub const name = "toolbar-style";
            const impl = gobject.ext.defineProperty(
                name,
                Self,
                adw.ToolbarStyle,
                .{
                    .default = .raised,
                    .accessor = gobject.ext.typedAccessor(
                        Self,
                        adw.ToolbarStyle,
                        .{
                            .getter = Self.getToolbarStyle,
                        },
                    ),
                },
            );
        };
    };

    const Private = struct {
        /// Whether this window is a quick terminal. If it is then it
        /// behaves slightly differently under certain scenarios.
        quick_terminal: bool = false,

        /// The window decoration override. If this is not set then we'll
        /// inherit whatever the config has. This allows overriding the
        /// config on a per-window basis.
        window_decoration: ?configpkg.WindowDecoration = null,

        /// Binding group for our active tab.
        tab_bindings: *gobject.BindingGroup,

        /// The configuration that this surface is using.
        config: ?*Config = null,

        /// State and logic for windowing protocol for a window.
        winproto: winprotopkg.Window,

        /// Kind of hacky to have this but this lets us know if we've
        /// initialized any single surface yet. We need this because we
        /// gate default size on this so that we don't resize the window
        /// after surfaces already exist.
        ///
        /// I think long term we can probably get rid of this by implementing
        /// a property or method that gets us all the surfaces in all the
        /// tabs and checking if we have zero or one that isn't initialized.
        ///
        /// For now, this logic is more similar to our legacy GTK side.
        surface_init: bool = false,

        /// See tabOverviewOpen for why we have this.
        tab_overview_focus_timer: ?c_uint = null,

        /// A weak reference to a command palette.
        command_palette: WeakRef(CommandPalette) = .empty,

        /// Tab page that the context menu was opened for.
        /// setup by `setup-menu`.
        context_menu_page: ?*adw.TabPage = null,

        /// The selected page when the user presses on the tab bar.
        tab_bar_pressed_page: ?*adw.TabPage = null,

        // Template bindings
        tab_overview: *adw.TabOverview,
        sidebar: *gtk.ListView,
        panmux_detail_title: *gtk.Label,
        panmux_detail_summary: *gtk.Label,
        panmux_ack_button: *gtk.Button,
        panmux_session_source: *gtk.StringList,
        panmux_attention_source: *gtk.StringList,
        tab_bar: *adw.TabBar,
        tab_view: *adw.TabView,
        toolbar: *adw.ToolbarView,
        toast_overlay: *adw.ToastOverlay,

        pub var offset: c_int = 0;
    };

    pub fn new(
        app: *Application,
        overrides: struct {
            title: ?[:0]const u8 = null,

            pub const none: @This() = .{};
        },
    ) *Self {
        const win = gobject.ext.newInstance(Self, .{
            .application = app,
        });

        if (overrides.title) |title| {
            // If the overrides have a title set, we set that immediately
            // so that any applications inspecting the window states see an
            // immediate title set when the window appears, rather than waiting
            // possibly a few event loop ticks for it to sync from the surface.
            win.as(gtk.Window).setTitle(title);
        }

        return win;
    }

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));

        // If our configuration is null then we get the configuration
        // from the application.
        const priv = self.private();

        const config = config: {
            if (priv.config) |config| break :config config.get();
            const app = Application.default();
            const config = app.getConfig();
            priv.config = config;
            break :config config.get();
        };

        // We initialize our windowing protocol to none because we can't
        // actually initialize this until we get realized.
        priv.winproto = .none;

        // Add our dev CSS class if we're in debug mode.
        if (comptime build_config.is_debug) {
            self.as(gtk.Widget).addCssClass("devel");
        }

        // Setup our tab binding group. This ensures certain properties
        // are only synced from the currently active tab.
        priv.tab_bindings = gobject.BindingGroup.new();
        priv.tab_bindings.bind("title", self.as(gobject.Object), "title", .{});

        // Set our window icon. We can't set this in the blueprint file
        // because its dependent on the build config.
        self.as(gtk.Window).setIconName(build_config.bundle_id);

        // Initialize our actions
        self.initActionMap();

        // Start states based on config.
        if (config.maximize) self.as(gtk.Window).maximize();
        if (config.fullscreen != .false) self.as(gtk.Window).fullscreen();

        // If we have an explicit title set, we set that immediately
        // so that any applications inspecting the window states see
        // an immediate title set when the window appears, rather than
        // waiting possibly a few event loop ticks for it to sync from
        // the surface.
        if (config.title) |title| {
            self.as(gtk.Window).setTitle(title);
        }

        // We always sync our appearance at the end because loading our
        // config and such can affect our bindings which are setup initially
        // in initTemplate.
        self.syncAppearance();

        // We need to do this so that the title initializes properly,
        // I think because its a dynamic getter.
        self.as(gobject.Object).notifyByPspec(properties.@"active-surface".impl.param_spec);

        const tab_bar_click = gtk.GestureClick.new();
        _ = gtk.GestureClick.signals.pressed.connect(
            tab_bar_click,
            *Self,
            tabBarPressed,
            self,
            .{},
        );
        _ = gtk.GestureClick.signals.released.connect(
            tab_bar_click,
            *Self,
            tabBarReleased,
            self,
            .{},
        );
        priv.tab_bar.as(gtk.Widget).addController(tab_bar_click.as(gtk.EventController));
    }

    /// Setup our action map.
    fn initActionMap(self: *Self) void {
        const s_variant_type = glib.ext.VariantType.newFor([:0]const u8);
        defer s_variant_type.free();

        const actions = [_]ext.actions.Action(Self){
            .init("about", actionAbout, null),
            .init("close", actionClose, null),
            .init("close-tab", actionCloseTab, s_variant_type),
            .init("new-tab", actionNewTab, null),
            .init("new-window", actionNewWindow, null),
            .init("prompt-surface-title", actionPromptSurfaceTitle, null),
            .init("prompt-tab-title", actionPromptTabTitle, null),
            .init("prompt-context-tab-title", actionPromptContextTabTitle, null),
            .init("ring-bell", actionRingBell, null),
            .init("split-right", actionSplitRight, null),
            .init("split-left", actionSplitLeft, null),
            .init("split-up", actionSplitUp, null),
            .init("split-down", actionSplitDown, null),
            .init("copy", actionCopy, null),
            .init("paste", actionPaste, null),
            .init("reset", actionReset, null),
            .init("clear", actionClear, null),
            // TODO: accept the surface that toggled the command palette
            .init("toggle-command-palette", actionToggleCommandPalette, null),
            .init("toggle-inspector", actionToggleInspector, null),
        };

        ext.actions.add(Self, self, &actions);
    }

    /// Winproto backend for this window.
    pub fn winproto(self: *Self) *winprotopkg.Window {
        return &self.private().winproto;
    }

    /// Create a new tab with the given parent. The tab will be inserted
    /// at the position dictated by the `window-new-tab-position` config.
    /// The new tab will be selected.
    pub fn newTab(self: *Self, parent_: ?*CoreSurface) void {
        _ = self.newTabPage(parent_, .tab, .none);
    }

    pub fn newTabForWindow(
        self: *Self,
        parent_: ?*CoreSurface,
        overrides: struct {
            command: ?configpkg.Command = null,
            working_directory: ?[:0]const u8 = null,
            title: ?[:0]const u8 = null,

            pub const none: @This() = .{};
        },
    ) void {
        _ = self.newTabPage(
            parent_,
            .window,
            .{
                .command = overrides.command,
                .working_directory = overrides.working_directory,
                .title = overrides.title,
            },
        );
    }

    fn newTabPage(
        self: *Self,
        parent_: ?*CoreSurface,
        context: apprt.surface.NewSurfaceContext,
        overrides: struct {
            command: ?configpkg.Command = null,
            working_directory: ?[:0]const u8 = null,
            title: ?[:0]const u8 = null,

            pub const none: @This() = .{};
        },
    ) *adw.TabPage {
        const priv: *Private = self.private();
        const tab_view = priv.tab_view;

        // Create our new tab object
        const tab = Tab.new(
            priv.config,
            .{
                .command = overrides.command,
                .working_directory = overrides.working_directory,
                .title = overrides.title,
            },
        );

        if (parent_) |p| {
            // For a new window's first tab, inherit the parent's initial size hints.
            if (context == .window) {
                surfaceInit(p.rt_surface.gobj(), self);
            }
            tab.setParentWithContext(p, context);
        }

        // Get the position that we should insert the new tab at.
        const config = if (priv.config) |v| v.get() else {
            // If we don't have a config we just append it at the end.
            // This should never happen.
            return tab_view.append(tab.as(gtk.Widget));
        };
        const position = switch (config.@"window-new-tab-position") {
            .current => current: {
                const selected = tab_view.getSelectedPage() orelse
                    break :current tab_view.getNPages();
                const current = tab_view.getPagePosition(selected);
                break :current current + 1;
            },

            .end => tab_view.getNPages(),
        };

        // Add the page and select it
        const page = tab_view.insert(tab.as(gtk.Widget), position);
        tab_view.setSelectedPage(page);

        // Create some property bindings
        _ = tab.as(gobject.Object).bindProperty(
            "title",
            page.as(gobject.Object),
            "title",
            .{ .sync_create = true },
        );
        _ = tab.as(gobject.Object).bindProperty(
            "tooltip",
            page.as(gobject.Object),
            "tooltip",
            .{ .sync_create = true },
        );

        // Bind signals
        const split_tree = tab.getSplitTree();
        _ = SplitTree.signals.changed.connect(
            split_tree,
            *Self,
            tabSplitTreeChanged,
            self,
            .{},
        );

        // Run an initial notification for the surface tree so we can setup
        // initial state.
        tabSplitTreeChanged(
            split_tree,
            null,
            split_tree.getTree(),
            self,
        );

        return page;
    }

    pub const SelectTab = union(enum) {
        previous,
        next,
        last,
        n: usize,
    };

    /// Select the tab as requested. Returns true if the tab selection
    /// changed.
    pub fn selectTab(self: *Self, n: SelectTab) bool {
        const priv = self.private();
        const tab_view = priv.tab_view;

        // Get our current tab numeric position
        const selected = tab_view.getSelectedPage() orelse return false;
        const current = tab_view.getPagePosition(selected);

        // Get our total
        const total = tab_view.getNPages();

        const goto: c_int = switch (n) {
            .previous => if (current > 0)
                current - 1
            else
                total - 1,

            .next => if (current < total - 1)
                current + 1
            else
                0,

            .last => total - 1,

            .n => |v| n: {
                // 1-indexed
                if (v == 0) return false;

                const n_int = std.math.cast(
                    c_int,
                    v,
                ) orelse return false;
                break :n @min(n_int - 1, total - 1);
            },
        };
        assert(goto >= 0);
        assert(goto < total);

        // If our target is the same as our current then we do nothing.
        if (goto == current) return false;

        // Add the page and select it
        const page = tab_view.getNthPage(goto);
        tab_view.setSelectedPage(page);

        return true;
    }

    /// Move the tab containing the given surface by the given amount.
    /// Returns if this affected any tab positioning.
    pub fn moveTab(
        self: *Self,
        surface: *Surface,
        amount: isize,
    ) bool {
        const priv = self.private();
        const tab_view = priv.tab_view;

        // If we have one tab we never move.
        const total = tab_view.getNPages();
        if (total == 1) return false;

        // Get the tab that contains the given surface.
        const tab = ext.getAncestor(
            Tab,
            surface.as(gtk.Widget),
        ) orelse return false;

        // Get the page position that contains the tab.
        const page = tab_view.getPage(tab.as(gtk.Widget));
        const pos = tab_view.getPagePosition(page);

        // Move it
        const desired_pos: c_int = desired: {
            const initial: c_int = @intCast(pos + amount);
            const max = total - 1;
            break :desired if (initial < 0)
                max + initial + 1
            else if (initial > max)
                initial - max - 1
            else
                initial;
        };
        assert(desired_pos >= 0);
        assert(desired_pos < total);

        return tab_view.reorderPage(page, desired_pos) != 0;
    }

    pub fn toggleTabOverview(self: *Self) void {
        const priv = self.private();
        const tab_overview = priv.tab_overview;
        const is_open = tab_overview.getOpen() != 0;
        tab_overview.setOpen(@intFromBool(!is_open));
    }

    /// Toggle the visible property.
    pub fn toggleVisibility(self: *Self) void {
        const widget = self.as(gtk.Widget);
        widget.setVisible(@intFromBool(widget.isVisible() == 0));
    }

    /// Updates various appearance properties. This should always be safe
    /// to call multiple times. This should be called whenever a change
    /// happens that might affect how the window appears (config change,
    /// fullscreen, etc.).
    fn syncAppearance(self: *Self) void {
        const priv = self.private();
        const widget = self.as(gtk.Widget);

        // Toggle style classes based on whether we're using CSDs or SSDs.
        //
        // These classes are defined in the gtk.Window documentation:
        // https://docs.gtk.org/gtk4/class.Window.html#css-nodes.
        {
            // Reset all style classes first
            inline for (&.{
                "ssd",
                "csd",
                "solid-csd",
                "no-border-radius",
            }) |class|
                widget.removeCssClass(class);

            const csd_enabled = priv.winproto.clientSideDecorationEnabled();
            self.as(gtk.Window).setDecorated(@intFromBool(csd_enabled));

            if (csd_enabled) {
                const display = widget.getDisplay();

                // We do the exact same check GTK is doing internally and toggle
                // either the `csd` or `solid-csd` style, based on whether the user's
                // window manager is deemed _non-compositing_.
                //
                // In practice this only impacts users of traditional X11 window
                // managers (e.g. i3, dwm, awesomewm, etc.) and not X11 desktop
                // environments or Wayland compositors/DEs.
                if (display.isRgba() != 0 and display.isComposited() != 0) {
                    widget.addCssClass("csd");
                } else {
                    widget.addCssClass("solid-csd");
                }
            } else {
                widget.addCssClass("ssd");
                // Fix any artifacting that may occur in window corners.
                widget.addCssClass("no-border-radius");
            }
        }

        // Trigger all our dynamic properties that depend on the config.
        inline for (&.{
            "headerbar-visible",
            "tabs-autohide",
            "tabs-visible",
            "tabs-wide",
            "toolbar-style",
            "titlebar-style",
        }) |key| {
            self.as(gobject.Object).notifyByPspec(
                @field(properties, key).impl.param_spec,
            );
        }

        // Remainder uses the config
        const config = if (priv.config) |v| v.get() else return;

        // Only add a solid background if we're opaque.
        self.toggleCssClass(
            "background",
            config.@"background-opacity" >= 1,
        );

        // Apply class to color headerbar if window-theme is set to `ghostty` and
        // GTK version is before 4.16. The conditional is because above 4.16
        // we use GTK CSS color variables.
        self.toggleCssClass(
            "window-theme-ghostty",
            !gtk_version.atLeast(4, 16, 0) and
                config.@"window-theme" == .ghostty,
        );

        // Move the tab bar to the proper location.
        priv.toolbar.remove(priv.tab_bar.as(gtk.Widget));
        switch (config.@"gtk-tabs-location") {
            .top => priv.toolbar.addTopBar(priv.tab_bar.as(gtk.Widget)),
            .bottom => priv.toolbar.addBottomBar(priv.tab_bar.as(gtk.Widget)),
        }

        // Do our window-protocol specific appearance sync.
        priv.winproto.syncAppearance() catch |err| {
            log.warn("failed to sync winproto appearance error={}", .{err});
        };
    }

    /// Sync the state of any actions on this window.
    fn syncActions(self: *Self) void {
        const has_selection = selection: {
            const surface = self.getActiveSurface() orelse
                break :selection false;
            const core_surface = surface.core() orelse
                break :selection false;
            break :selection core_surface.hasSelection();
        };

        const action_map: *gio.ActionMap = gobject.ext.cast(
            gio.ActionMap,
            self,
        ) orelse return;
        const action: *gio.SimpleAction = gobject.ext.cast(
            gio.SimpleAction,
            action_map.lookupAction("copy") orelse return,
        ) orelse return;
        action.setEnabled(@intFromBool(has_selection));
    }

    pub fn panmuxHasTarget(self: *Self, params: panmux_ipc.Params) bool {
        return self.resolvePanmuxPage(params) != null;
    }

    pub fn panmuxNotify(self: *Self, params: panmux_ipc.Params) bool {
        const page = self.resolvePanmuxPage(params) orelse return false;
        self.applyPanmuxNotification(page, params);

        const foreground = page.getSelected() != 0 and self.as(gtk.Window).isActive() != 0;
        const state = normalizedPanmuxState(params.state);
        if (!foreground and panmuxShouldMarkNeedsAttention(state)) {
            page.setNeedsAttention(@intFromBool(true));
        }

        if (foreground) {
            var toast_buf: [512]u8 = undefined;
            self.addToast(panmuxToastMessage(params, &toast_buf));
        }

        return true;
    }

    pub fn panmuxDesktopNotification(
        self: *Self,
        surface: *Surface,
        title: []const u8,
        body: []const u8,
    ) bool {
        const tab = ext.getAncestor(Tab, surface.as(gtk.Widget)) orelse return false;
        const page = self.private().tab_view.getPage(tab.as(gtk.Widget));
        const params = desktopNotificationPanmuxParams(title, body);
        self.applyPanmuxNotification(page, params);

        const foreground = page.getSelected() != 0 and self.as(gtk.Window).isActive() != 0;
        const state = normalizedPanmuxState(params.state);
        if (!foreground and panmuxShouldMarkNeedsAttention(state)) {
            page.setNeedsAttention(@intFromBool(true));
        }

        if (foreground) {
            var toast_buf: [512]u8 = undefined;
            self.addToast(panmuxToastMessage(params, &toast_buf));
        }

        return true;
    }

    pub fn panmuxSetStatus(self: *Self, params: panmux_ipc.Params) bool {
        const page = self.resolvePanmuxPage(params) orelse return false;
        self.applyPanmuxStatus(page, params);
        return true;
    }

    pub fn panmuxClearStatus(self: *Self, params: panmux_ipc.Params) bool {
        const page = self.resolvePanmuxPage(params) orelse return false;
        self.clearPanmuxStatus(page, params);
        return true;
    }

    pub fn panmuxFocusTab(self: *Self, params: panmux_ipc.Params) bool {
        const page = self.resolvePanmuxPage(params) orelse return false;
        self.private().tab_view.setSelectedPage(page);
        self.focusActiveSurface();
        self.as(gtk.Window).present();
        return true;
    }

    pub fn panmuxListTabs(self: *Self, alloc: std.mem.Allocator) ![]panmux_ipc.OwnedTabInfo {
        const n_pages = self.private().tab_view.getNPages();
        const n: usize = @intCast(@max(n_pages, 0));
        const tabs = try alloc.alloc(panmux_ipc.OwnedTabInfo, n);
        errdefer alloc.free(tabs);

        var built: usize = 0;
        errdefer {
            for (tabs[0..built]) |*tab| tab.deinit(alloc);
        }

        while (built < n) : (built += 1) {
            tabs[built] = try self.snapshotPanmuxTab(alloc, self.private().tab_view.getNthPage(@intCast(built)), @intCast(built + 1));
        }

        return tabs;
    }

    pub fn panmuxStateForSurface(self: *Self, surface: *Surface) ?[]const u8 {
        const tab = ext.getAncestor(Tab, surface.as(gtk.Widget)) orelse return null;
        const page = self.private().tab_view.getPage(tab.as(gtk.Widget));
        return self.panmuxStateForPage(page);
    }

    pub fn panmuxClearStatusSurface(self: *Self, surface: *Surface) bool {
        const tab = ext.getAncestor(Tab, surface.as(gtk.Widget)) orelse return false;
        const page = self.private().tab_view.getPage(tab.as(gtk.Widget));
        var surface_buf: [32]u8 = undefined;
        const surface_id = std.fmt.bufPrint(&surface_buf, "{x}", .{@intFromPtr(surface)}) catch null;
        self.clearPanmuxStatus(page, .{ .surface_id = surface_id });
        return true;
    }

    pub fn panmuxFinishRunningSurface(self: *Self, surface: *Surface) bool {
        const tab = ext.getAncestor(Tab, surface.as(gtk.Widget)) orelse return false;
        const page = self.private().tab_view.getPage(tab.as(gtk.Widget));
        var tab_buf: [32]u8 = undefined;
        const workspace_id = std.fmt.bufPrint(&tab_buf, "{x}", .{@intFromPtr(tab)}) catch return false;
        var surface_buf: [32]u8 = undefined;
        const surface_id = std.fmt.bufPrint(&surface_buf, "{x}", .{@intFromPtr(surface)}) catch return false;
        self.panmuxStore().finishLegacySurfaceSession(workspace_id, surface_id);
        self.refreshPanmuxPage(page);
        return true;
    }

    pub fn panmuxConsumeNeedsInputSurface(self: *Self, surface: *Surface) bool {
        const tab = ext.getAncestor(Tab, surface.as(gtk.Widget)) orelse return false;
        const page = self.private().tab_view.getPage(tab.as(gtk.Widget));
        self.consumePanmuxNeedsInputForPage(page);
        self.refreshPanmuxPage(page);
        return true;
    }

    pub fn panmuxListSessions(self: *Self, alloc: std.mem.Allocator, params: panmux_ipc.Params) ![]panmux_ipc.OwnedSessionInfo {
        const page = self.resolvePanmuxPage(params) orelse return alloc.alloc(panmux_ipc.OwnedSessionInfo, 0);
        var tab_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return alloc.alloc(panmux_ipc.OwnedSessionInfo, 0);

        var count: usize = 0;
        for (self.panmuxStore().sessions()) |session| {
            if (std.mem.eql(u8, session.workspace_id, workspace_id)) count += 1;
        }

        const sessions = try alloc.alloc(panmux_ipc.OwnedSessionInfo, count);
        errdefer alloc.free(sessions);
        var built: usize = 0;
        errdefer {
            for (sessions[0..built]) |*session| session.deinit(alloc);
        }

        for (self.panmuxStore().sessions()) |session| {
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            sessions[built] = try panmuxSessionInfoFromState(alloc, session);
            built += 1;
        }

        return sessions;
    }

    pub fn panmuxListAttention(self: *Self, alloc: std.mem.Allocator, params: panmux_ipc.Params) ![]panmux_ipc.OwnedAttentionInfo {
        const page = self.resolvePanmuxPage(params) orelse return alloc.alloc(panmux_ipc.OwnedAttentionInfo, 0);
        var tab_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return alloc.alloc(panmux_ipc.OwnedAttentionInfo, 0);

        var count: usize = 0;
        for (self.panmuxStore().attentions()) |attention| {
            if (std.mem.eql(u8, attention.workspace_id, workspace_id)) count += 1;
        }

        const attentions = try alloc.alloc(panmux_ipc.OwnedAttentionInfo, count);
        errdefer alloc.free(attentions);
        var built: usize = 0;
        errdefer {
            for (attentions[0..built]) |*attention| attention.deinit(alloc);
        }

        for (self.panmuxStore().attentions()) |attention| {
            if (!std.mem.eql(u8, attention.workspace_id, workspace_id)) continue;
            attentions[built] = try panmuxAttentionInfoFromState(alloc, attention);
            built += 1;
        }

        return attentions;
    }

    pub fn panmuxAckAttention(self: *Self, params: panmux_ipc.Params) bool {
        const attention_id = params.attention_id orelse return false;
        if (!self.panmuxStore().ackAttention(attention_id)) return false;

        const page = self.resolvePanmuxPage(params) orelse return true;
        self.refreshPanmuxPage(page);
        return true;
    }

    fn resolvePanmuxPage(self: *Self, params: panmux_ipc.Params) ?*adw.TabPage {
        const priv = self.private();

        if (params.tab_index) |tab_index| {
            if (tab_index == 0) return null;
            const idx: c_int = @intCast(tab_index - 1);
            if (idx < 0 or idx >= priv.tab_view.getNPages()) return null;
            const page = priv.tab_view.getNthPage(idx);
            if ((params.tab_id != null or params.surface_id != null) and !pageMatchesPanmuxTarget(page, params)) {
                return null;
            }
            return page;
        }

        if (params.tab_id != null or params.surface_id != null) {
            const n_pages = priv.tab_view.getNPages();
            var i: c_int = 0;
            while (i < n_pages) : (i += 1) {
                const page = priv.tab_view.getNthPage(i);
                if (pageMatchesPanmuxTarget(page, params)) return page;
            }
            return null;
        }

        return priv.tab_view.getSelectedPage();
    }

    fn snapshotPanmuxTab(
        self: *Self,
        alloc: std.mem.Allocator,
        page: *adw.TabPage,
        index: u32,
    ) !panmux_ipc.OwnedTabInfo {
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return error.InvalidTabPage;
        const surface = tab.getActiveSurface();
        const pwd = if (surface) |v| v.getPwd() else null;
        const state = self.panmuxStateForPage(page);
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page);

        var info = panmux_ipc.OwnedTabInfo{
            .index = index,
            .title = try alloc.dupeZ(u8, std.mem.span(page.getTitle())),
            .cwd = if (pwd) |value| try alloc.dupeZ(u8, value) else null,
            .state = if (state) |value| try alloc.dupeZ(u8, value) else null,
            .tab_id = try ptrIdAlloc(alloc, tab),
            .surface_id = if (surface) |value| try ptrIdAlloc(alloc, value) else null,
            .selected = page.getSelected() != 0,
            .needs_attention = page.getNeedsAttention() != 0,
            .loading = page.getLoading() != 0,
            .running_count = if (snapshot) |value| value.running_count else 0,
            .unread_count = if (snapshot) |value| value.unread_count else 0,
        };
        errdefer info.deinit(alloc);
        return info;
    }

    fn keywordOrNull(keyword_: ?[*:0]const u8) ?[]const u8 {
        const keyword = keyword_ orelse return null;
        const value = std.mem.span(keyword);
        if (value.len == 0) return null;
        return value;
    }

    fn normalizedPanmuxState(state: ?[]const u8) []const u8 {
        const value = state orelse return "";
        return value;
    }

    fn publicPanmuxState(state: ?[]const u8) ?[]const u8 {
        const value = state orelse return null;
        return normalizedPanmuxState(value);
    }

    fn trimAsciiWhitespace(value: []const u8) []const u8 {
        var start_idx: usize = 0;
        var end_idx: usize = value.len;

        while (start_idx < end_idx and std.ascii.isWhitespace(value[start_idx])) : (start_idx += 1) {}
        while (end_idx > start_idx and std.ascii.isWhitespace(value[end_idx - 1])) : (end_idx -= 1) {}

        return value[start_idx..end_idx];
    }

    fn desktopNotificationPanmuxParams(title: []const u8, body: []const u8) panmux_ipc.Params {
        const clean_title = trimAsciiWhitespace(title);
        const clean_body = trimAsciiWhitespace(body);

        if (std.mem.eql(u8, clean_body, "pong")) {
            return .{
                .title = "Codex",
                .body = "turn complete",
                .state = "info",
            };
        }

        return .{
            .title = if (clean_title.len > 0) clean_title else "Ghostty",
            .body = if (clean_body.len > 0) clean_body else null,
            .state = "info",
        };
    }

    fn pageMatchesPanmuxTarget(page: *adw.TabPage, params: panmux_ipc.Params) bool {
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return false;

        if (params.tab_id) |tab_id| {
            if (!ptrIdMatches(tab, tab_id)) return false;
        }

        if (params.surface_id) |surface_id| {
            const tree = tab.getSurfaceTree() orelse return false;
            if (!treeHasSurfaceId(tree, surface_id)) return false;
        }

        return true;
    }

    fn treeHasSurfaceId(tree: *const Surface.Tree, expected: []const u8) bool {
        var it = tree.iterator();
        while (it.next()) |entry| {
            if (ptrIdMatches(entry.view, expected)) return true;
        }

        return false;
    }

    fn ptrIdMatches(ptr: anytype, expected: []const u8) bool {
        var buf: [32]u8 = undefined;
        const actual = std.fmt.bufPrint(&buf, "{x}", .{@intFromPtr(ptr)}) catch return false;
        return std.mem.eql(u8, actual, expected);
    }

    fn ptrIdAlloc(alloc: std.mem.Allocator, ptr: anytype) ![:0]u8 {
        const value = try std.fmt.allocPrint(alloc, "{x}", .{@intFromPtr(ptr)});
        defer alloc.free(value);
        return try alloc.dupeZ(u8, value);
    }

    fn applyPanmuxStatus(self: *Self, page: *adw.TabPage, params: panmux_ipc.Params) void {
        const state = normalizedPanmuxState(params.state);
        var tab_buf: [32]u8 = undefined;
        var surface_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return;
        const surface_id = panmuxSurfaceIdForPage(page, &surface_buf);
        var session_buf: [96]u8 = undefined;
        const session_id = panmuxSessionId(params, surface_id, &session_buf) orelse return;
        const status_text = if (state.len > 0 and !std.mem.eql(u8, state, "running")) state else null;
        const summary = params.body orelse params.title;

        self.panmuxStore().updateSession(.{
            .workspace_id = workspace_id,
            .tab_id = workspace_id,
            .surface_id = surface_id,
            .session_id = session_id,
            .agent_type = panmuxAgentType(params),
            .agent_label = panmuxAgentLabel(params),
            .phase = panmux_state.phaseFromState(state),
            .severity = panmux_state.severityFromState(state),
            .status_text = status_text,
            .turn_id = params.turn_id,
            .summary = summary,
        }) catch |err| {
            log.warn("failed to update panmux store status err={}", .{err});
            return;
        };
        self.refreshPanmuxPage(page);
    }

    fn applyPanmuxNotification(self: *Self, page: *adw.TabPage, params: panmux_ipc.Params) void {
        var tab_buf: [32]u8 = undefined;
        var surface_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return;
        const surface_id = panmuxSurfaceIdForPage(page, &surface_buf);
        var session_buf: [96]u8 = undefined;
        const session_id = panmuxSessionId(params, surface_id, &session_buf);
        const state = normalizedPanmuxState(params.state);

        if (session_id) |resolved_session_id| {
            self.panmuxStore().touchSession(.{
                .workspace_id = workspace_id,
                .tab_id = workspace_id,
                .surface_id = surface_id,
                .session_id = resolved_session_id,
                .agent_type = panmuxAgentType(params),
                .agent_label = panmuxAgentLabel(params),
                .phase = .running,
                .severity = panmux_state.severityFromState(state),
                .status_text = if (state.len > 0 and !std.mem.eql(u8, state, "running")) state else null,
                .turn_id = params.turn_id,
                .summary = params.body orelse params.title,
            }) catch |err| {
                log.warn("failed to touch panmux session err={}", .{err});
            };
        }

        const attention_title = params.title orelse panmuxAgentLabel(params);
        const attention_body = params.body orelse if (state.len > 0) state else null;
        const should_raise_attention = (params.ack_required orelse true) and
            (attention_title.len > 0 or attention_body != null);

        if (should_raise_attention) {
            _ = self.panmuxStore().raiseAttention(.{
                .workspace_id = workspace_id,
                .session_id = session_id,
                .kind = panmuxAttentionKind(params),
                .severity = panmux_state.severityFromState(state),
                .title = attention_title,
                .body = attention_body,
                .ack_required = params.ack_required orelse true,
            }) catch |err| {
                log.warn("failed to raise panmux attention err={}", .{err});
            };
        }

        self.refreshPanmuxPage(page);
    }

    fn clearPanmuxStatus(self: *Self, page: *adw.TabPage, params: panmux_ipc.Params) void {
        var tab_buf: [32]u8 = undefined;
        var surface_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return;
        const fallback_surface_id = panmuxSurfaceIdForPage(page, &surface_buf);
        self.panmuxStore().clearStatus(
            workspace_id,
            params.session_id,
            params.surface_id orelse fallback_surface_id,
        );
        self.refreshPanmuxPage(page);
    }

    fn syncPanmuxIndicator(page: *adw.TabPage) void {
        if (page.getLoading() != 0) {
            page.setIndicatorIcon(null);
            return;
        }

        const state = publicPanmuxState(keywordOrNull(page.getKeyword())) orelse {
            page.setIndicatorIcon(null);
            return;
        };

        const icon_name = panmuxIndicatorIconName(state) orelse {
            page.setIndicatorIcon(null);
            return;
        };
        const icon = gio.ThemedIcon.new(icon_name);
        defer icon.unref();
        page.setIndicatorIcon(icon.as(gio.Icon));
    }

    fn panmuxIndicatorIconName(state: []const u8) ?[*:0]const u8 {
        if (state.len == 0) return null;
        if (std.mem.eql(u8, state, "info")) return "mail-unread-symbolic";
        if (std.mem.eql(u8, state, "error")) return "dialog-error-symbolic";
        if (std.mem.eql(u8, state, "warn")) return "dialog-warning-symbolic";
        if (std.mem.eql(u8, state, "warning")) return "dialog-warning-symbolic";
        return "emblem-system-symbolic";
    }

    fn panmuxStatusKeyword(state: []const u8, buf: []u8) [*:0]const u8 {
        if (std.mem.eql(u8, state, "running")) return "";
        const stored = storedPanmuxState(state);
        if (stored.len == 0) return "";
        return std.fmt.bufPrintZ(buf, "{s}", .{stored}) catch "";
    }

    fn storedPanmuxState(state: []const u8) []const u8 {
        if (std.mem.eql(u8, state, "running")) return "";
        if (state.len == 0) return "";
        return state;
    }

    fn panmuxShouldPreserveRunningStatus(running: bool, state: []const u8) bool {
        if (!running) return false;
        return state.len == 0 or !std.mem.eql(u8, state, "running");
    }

    fn panmuxShouldMarkNeedsAttention(state: []const u8) bool {
        // `needs-attention` is a secondary generic signal in libadwaita and
        // visually overrides the primary tab status. Structured panmux states
        // already have a spinner/icon, so only state-less notifications should
        // escalate through attention.
        return state.len == 0;
    }

    fn panmuxStateForPage(self: *Self, page: *adw.TabPage) ?[]const u8 {
        if (self.panmuxWorkspaceSnapshotForPage(page)) |snapshot| {
            return switch (snapshot.badge_kind) {
                .empty => null,
                .running => "running",
                .info => "info",
                .warning => "warning",
                .@"error" => "error",
                .other => snapshot.badge_label orelse "custom",
            };
        }
        if (page.getLoading() != 0) return "running";
        return publicPanmuxState(keywordOrNull(page.getKeyword()));
    }

    fn sidebarStatusKind(loading: bool, keyword: ?[]const u8) []const u8 {
        if (loading) return "running";
        const state = publicPanmuxState(keyword) orelse return "empty";
        if (state.len == 0) return "empty";
        if (std.mem.eql(u8, state, "info")) return "info";
        if (std.mem.eql(u8, state, "warn") or std.mem.eql(u8, state, "warning")) return "warning";
        if (std.mem.eql(u8, state, "error")) return "error";
        return "other";
    }

    fn sidebarOverlayKindForOverlay(kind: panmux_state.OverlayKind) []const u8 {
        return switch (kind) {
            .none => "",
            .info => "info",
            .warning => "warning",
            .@"error" => "error",
            .other => "other",
        };
    }

    fn sidebarOverlayKind(self: *Self, page: ?*adw.TabPage) []const u8 {
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page orelse return "") orelse return "";
        return sidebarOverlayKindForOverlay(snapshot.overlay_kind);
    }

    fn sidebarStatusIs(loading: bool, keyword: ?[]const u8, expected: []const u8) bool {
        return std.mem.eql(u8, sidebarStatusKind(loading, keyword), expected);
    }

    fn panmuxStore(self: *Self) *panmux_state.Store {
        _ = self;
        return Application.default().panmuxStore();
    }

    fn panmuxWorkspaceSnapshotForPage(self: *Self, page: *adw.TabPage) ?panmux_state.WorkspaceSnapshot {
        var tab_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return null;
        return self.panmuxStore().snapshotWorkspace(workspace_id);
    }

    const PanmuxWorkflowSnapshot = struct {
        active_count: u32 = 0,
        running_count: u32 = 0,
        needs_input_count: u32 = 0,
    };

    fn refreshPanmuxPage(self: *Self, page: *adw.TabPage) void {
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page) orelse {
            page.setLoading(@intFromBool(false));
            page.setKeyword("");
            page.setIndicatorIcon(null);
            page.setIndicatorTooltip("");
            self.refreshPanmuxInspector();
            return;
        };
        self.applyPanmuxSnapshot(page, snapshot);
        self.refreshPanmuxInspector();
    }

    fn applyPanmuxSnapshot(_: *Self, page: *adw.TabPage, snapshot: panmux_state.WorkspaceSnapshot) void {
        var keyword_buf: [64]u8 = undefined;
        var tooltip_buf: [512]u8 = undefined;
        page.setLoading(@intFromBool(snapshot.badge_kind == .running));

        const keyword_state = switch (snapshot.badge_kind) {
            .empty, .running => "",
            .info => "info",
            .warning => "warning",
            .@"error" => "error",
            .other => snapshot.badge_label orelse "custom",
        };
        page.setKeyword(panmuxStatusKeyword(keyword_state, &keyword_buf));
        const tooltip = if (snapshot.tooltip) |value|
            std.fmt.bufPrintZ(&tooltip_buf, "{s}", .{value}) catch ""
        else
            "";
        page.setIndicatorTooltip(tooltip);
        syncPanmuxIndicator(page);
    }

    fn refreshPanmuxInspector(self: *Self) void {
        const priv = self.private();
        priv.panmux_detail_title.setLabel("Agent Workflow");

        const workflow = self.panmuxWindowWorkflowSnapshot();
        if (workflow.active_count == 0) {
            priv.panmux_detail_summary.setLabel("No active Codex agents in this window.");
            self.clearStringList(priv.panmux_session_source);
            self.clearStringList(priv.panmux_attention_source);
            priv.panmux_session_source.append("No active agents.");
            priv.panmux_attention_source.append("Nothing needs input.");
            priv.panmux_ack_button.as(gtk.Widget).setSensitive(0);
            return;
        }

        {
            var summary_buf: [256]u8 = undefined;
            const summary = if (workflow.needs_input_count > 0)
                std.fmt.bufPrintZ(
                    &summary_buf,
                    "{} needs input, {} agents active",
                    .{ workflow.needs_input_count, workflow.active_count },
                ) catch "Codex workflow"
            else
                std.fmt.bufPrintZ(
                    &summary_buf,
                    "{} agents running",
                    .{workflow.running_count},
                ) catch "Codex workflow";
            priv.panmux_detail_summary.setLabel(summary);
        }

        self.populatePanmuxSessionStrings(priv.panmux_session_source);
        self.populatePanmuxNeedsInputStrings(priv.panmux_attention_source);
        priv.panmux_ack_button.as(gtk.Widget).setSensitive(@intFromBool(workflow.needs_input_count > 0));
    }

    fn populatePanmuxSessionStrings(self: *Self, source: *gtk.StringList) void {
        self.clearStringList(source);

        var count: usize = 0;
        for (self.panmuxStore().sessions()) |session| {
            if (session.agent_type != .codex) continue;
            if (!panmux_state.isSessionActive(session.phase)) continue;
            if (!self.panmuxWindowHasWorkspace(session.workspace_id)) continue;
            var buf: [512]u8 = undefined;
            const line = std.fmt.bufPrintZ(
                &buf,
                "{s} | {s} | {s}",
                .{
                    self.panmuxWorkspaceTitle(session.workspace_id),
                    self.panmuxCodexWorkflowState(session),
                    session.last_summary orelse session.status_text orelse "-",
                },
            ) catch continue;
            source.append(line);
            count += 1;
        }

        if (count == 0) source.append("No active agents.");
    }

    fn populatePanmuxNeedsInputStrings(self: *Self, source: *gtk.StringList) void {
        self.clearStringList(source);

        var count: usize = 0;
        for (self.panmuxStore().sessions()) |session| {
            if (session.agent_type != .codex) continue;
            if (!panmux_state.isSessionActive(session.phase)) continue;
            if (!self.panmuxWindowHasWorkspace(session.workspace_id)) continue;
            const attention = self.panmuxStore().latestUnreadAttentionForSession(session.session_id) orelse continue;
            var buf: [512]u8 = undefined;
            const line = std.fmt.bufPrintZ(
                &buf,
                "{s} | {s}",
                .{
                    self.panmuxWorkspaceTitle(session.workspace_id),
                    attention.body orelse attention.title,
                },
            ) catch continue;
            source.append(line);
            count += 1;
        }

        if (count == 0) source.append("Nothing needs input.");
    }

    fn panmuxWindowWorkflowSnapshot(self: *Self) PanmuxWorkflowSnapshot {
        var snapshot: PanmuxWorkflowSnapshot = .{};
        for (self.panmuxStore().sessions()) |session| {
            if (session.agent_type != .codex) continue;
            if (!panmux_state.isSessionActive(session.phase)) continue;
            if (!self.panmuxWindowHasWorkspace(session.workspace_id)) continue;

            snapshot.active_count += 1;
            if (self.panmuxStore().sessionNeedsInput(session.session_id)) {
                snapshot.needs_input_count += 1;
            } else {
                snapshot.running_count += 1;
            }
        }

        return snapshot;
    }

    fn panmuxWindowHasWorkspace(self: *Self, workspace_id: []const u8) bool {
        const n_pages = self.private().tab_view.getNPages();
        var i: c_int = 0;
        while (i < n_pages) : (i += 1) {
            const page = self.private().tab_view.getNthPage(i);
            var tab_buf: [32]u8 = undefined;
            const page_workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse continue;
            if (std.mem.eql(u8, page_workspace_id, workspace_id)) return true;
        }

        return false;
    }

    fn panmuxWorkspaceTitle(self: *Self, workspace_id: []const u8) []const u8 {
        const n_pages = self.private().tab_view.getNPages();
        var i: c_int = 0;
        while (i < n_pages) : (i += 1) {
            const page = self.private().tab_view.getNthPage(i);
            var tab_buf: [32]u8 = undefined;
            const page_workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse continue;
            if (!std.mem.eql(u8, page_workspace_id, workspace_id)) continue;
            return std.mem.span(page.getTitle());
        }

        return "Codex";
    }

    fn panmuxCodexWorkflowState(self: *Self, session: panmux_state.AgentSessionState) []const u8 {
        if (self.panmuxStore().sessionNeedsInput(session.session_id)) return "Needs input";
        if (session.phase == .starting) return "Starting";
        return "Running";
    }

    fn consumePanmuxNeedsInputForPage(self: *Self, page: *adw.TabPage) void {
        var tab_buf: [32]u8 = undefined;
        const workspace_id = panmuxWorkspaceIdForPage(page, &tab_buf) orelse return;
        const store = self.panmuxStore();
        for (store.sessions()) |session| {
            if (!std.mem.eql(u8, session.workspace_id, workspace_id)) continue;
            if (session.agent_type != .codex) continue;
            if (!panmux_state.isSessionActive(session.phase)) continue;
            _ = store.ackSessionAttention(session.session_id);
        }
    }

    fn clearStringList(self: *Self, source: *gtk.StringList) void {
        _ = self;
        const model = source.as(gio.ListModel);
        const count = model.getNItems();
        if (count == 0) return;
        source.splice(0, count, null);
    }

    fn panmuxAgentType(params: panmux_ipc.Params) panmux_state.AgentType {
        if (params.agent_type) |value| return panmux_state.agentTypeFromText(value);
        if (params.title) |title| {
            if (std.mem.eql(u8, title, "Codex")) return .codex;
        }
        return .other;
    }

    fn panmuxAgentLabel(params: panmux_ipc.Params) []const u8 {
        return params.agent_label orelse params.title orelse "Panmux";
    }

    fn panmuxAttentionKind(params: panmux_ipc.Params) panmux_state.AttentionKind {
        if (params.title) |title| {
            if (std.mem.eql(u8, title, "Codex")) return .turn_complete;
        }
        return .legacy_notify;
    }

    fn panmuxWorkspaceIdForPage(page: *adw.TabPage, buf: *[32]u8) ?[]const u8 {
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return null;
        return std.fmt.bufPrint(buf, "{x}", .{@intFromPtr(tab)}) catch null;
    }

    fn panmuxSurfaceIdForPage(page: *adw.TabPage, buf: *[32]u8) ?[]const u8 {
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return null;
        const surface = tab.getActiveSurface() orelse return null;
        return std.fmt.bufPrint(buf, "{x}", .{@intFromPtr(surface)}) catch null;
    }

    fn panmuxSessionId(params: panmux_ipc.Params, surface_id: ?[]const u8, buf: *[96]u8) ?[]const u8 {
        if (params.session_id) |session_id| return session_id;
        const value = surface_id orelse return null;
        return std.fmt.bufPrint(buf, "legacy:{s}", .{value}) catch null;
    }

    fn panmuxSessionInfoFromState(alloc: std.mem.Allocator, session: panmux_state.AgentSessionState) !panmux_ipc.OwnedSessionInfo {
        var info = panmux_ipc.OwnedSessionInfo{
            .workspace_id = try alloc.dupeZ(u8, session.workspace_id),
            .session_id = try alloc.dupeZ(u8, session.session_id),
            .agent_type = try alloc.dupeZ(u8, panmux_state.agentTypeText(session.agent_type)),
            .agent_label = try alloc.dupeZ(u8, session.agent_label),
            .phase = try alloc.dupeZ(u8, panmux_state.phaseText(session.phase)),
            .severity = try alloc.dupeZ(u8, panmux_state.severityText(session.severity)),
            .surface_id = if (session.surface_id) |value| try alloc.dupeZ(u8, value) else null,
            .status_text = if (session.status_text) |value| try alloc.dupeZ(u8, value) else null,
            .turn_id = if (session.turn_id) |value| try alloc.dupeZ(u8, value) else null,
            .summary = if (session.last_summary) |value| try alloc.dupeZ(u8, value) else null,
            .updated_at_ms = session.updated_at_ms,
        };
        errdefer info.deinit(alloc);
        return info;
    }

    fn panmuxAttentionInfoFromState(alloc: std.mem.Allocator, attention: panmux_state.AttentionItem) !panmux_ipc.OwnedAttentionInfo {
        var info = panmux_ipc.OwnedAttentionInfo{
            .attention_id = try alloc.dupeZ(u8, attention.attention_id),
            .workspace_id = try alloc.dupeZ(u8, attention.workspace_id),
            .session_id = if (attention.session_id) |value| try alloc.dupeZ(u8, value) else null,
            .severity = try alloc.dupeZ(u8, panmux_state.severityText(attention.severity)),
            .title = try alloc.dupeZ(u8, attention.title),
            .body = if (attention.body) |value| try alloc.dupeZ(u8, value) else null,
            .ack_required = attention.ack_required,
            .acked = attention.acked_at_ms != null,
            .created_at_ms = attention.created_at_ms,
        };
        errdefer info.deinit(alloc);
        return info;
    }

    fn panmuxStatusTooltip(params: panmux_ipc.Params, buf: []u8) [*:0]const u8 {
        const state = normalizedPanmuxState(params.state);
        const title = params.title orelse "";
        const body = params.body orelse "";
        if (state.len > 0 and title.len > 0 and body.len > 0) {
            return std.fmt.bufPrintZ(buf, "{s}: {s} — {s}", .{ state, title, body }) catch "";
        }
        if (state.len > 0 and title.len > 0) {
            return std.fmt.bufPrintZ(buf, "{s}: {s}", .{ state, title }) catch "";
        }
        if (title.len > 0 and body.len > 0) {
            return std.fmt.bufPrintZ(buf, "{s}: {s}", .{ title, body }) catch "";
        }
        if (body.len > 0) {
            return std.fmt.bufPrintZ(buf, "{s}", .{body}) catch "";
        }
        if (title.len > 0) {
            return std.fmt.bufPrintZ(buf, "{s}", .{title}) catch "";
        }
        if (state.len > 0) {
            return std.fmt.bufPrintZ(buf, "{s}", .{state}) catch "";
        }
        return "";
    }

    fn panmuxToastMessage(params: panmux_ipc.Params, buf: []u8) [*:0]const u8 {
        const state = normalizedPanmuxState(params.state);
        const title = params.title orelse if (state.len > 0) state else "Panmux";
        const body = params.body orelse "";
        if (body.len > 0) {
            const msg = std.fmt.bufPrintZ(buf, "{s}: {s}", .{ title, body }) catch return "Panmux";
            return msg;
        }

        const msg = std.fmt.bufPrintZ(buf, "{s}", .{title}) catch return "Panmux";
        return msg;
    }

    fn toggleCssClass(self: *Self, class: [:0]const u8, value: bool) void {
        const widget = self.as(gtk.Widget);
        if (value)
            widget.addCssClass(class.ptr)
        else
            widget.removeCssClass(class.ptr);
    }

    /// Perform a binding action on the window's active surface.
    fn performBindingAction(
        self: *Self,
        action: input.Binding.Action,
    ) void {
        const surface = self.getActiveSurface() orelse return;
        const core_surface = surface.core() orelse return;
        _ = core_surface.performBindingAction(action) catch |err| {
            log.warn("error performing binding action error={}", .{err});
            return;
        };
    }

    /// Queue a simple text-based toast. All text-based toasts share the
    /// same timeout for consistency.
    ///
    // This is not `pub` because we should be using signals emitted by
    // other widgets to trigger our toasts. Other objects should not
    // trigger toasts directly.
    fn addToast(self: *Self, title: [*:0]const u8) void {
        const toast = adw.Toast.new(title);
        toast.setTimeout(3);
        self.private().toast_overlay.addToast(toast);
    }

    fn connectSurfaceHandlers(
        self: *Self,
        tree: *const Surface.Tree,
    ) void {
        const priv = self.private();
        var it = tree.iterator();
        while (it.next()) |entry| {
            const surface = entry.view;
            // Before adding any new signal handlers, disconnect any that we may
            // have added before. Otherwise we may get multiple handlers for the
            // same signal.
            _ = gobject.signalHandlersDisconnectMatched(
                surface.as(gobject.Object),
                .{ .data = true },
                0,
                0,
                null,
                null,
                self,
            );

            _ = Surface.signals.@"present-request".connect(
                surface,
                *Self,
                surfacePresentRequest,
                self,
                .{},
            );
            _ = Surface.signals.@"clipboard-write".connect(
                surface,
                *Self,
                surfaceClipboardWrite,
                self,
                .{},
            );
            _ = Surface.signals.menu.connect(
                surface,
                *Self,
                surfaceMenu,
                self,
                .{},
            );
            _ = Surface.signals.@"toggle-fullscreen".connect(
                surface,
                *Self,
                surfaceToggleFullscreen,
                self,
                .{},
            );
            _ = Surface.signals.@"toggle-maximize".connect(
                surface,
                *Self,
                surfaceToggleMaximize,
                self,
                .{},
            );

            // If we've never had a surface initialize yet, then we register
            // this signal. Its theoretically possible to launch multiple surfaces
            // before init so we could register this on multiple and that is not
            // a problem because we'll check the flag again in each handler.
            if (!priv.surface_init) {
                _ = Surface.signals.init.connect(
                    surface,
                    *Self,
                    surfaceInit,
                    self,
                    .{},
                );
            }
        }
    }

    /// Disconnect all the surface handlers for the given tree. This should
    /// be called whenever a tree is no longer present in the window, e.g.
    /// when a tab is detached or the tree changes.
    fn disconnectSurfaceHandlers(
        self: *Self,
        tree: *const Surface.Tree,
    ) void {
        var it = tree.iterator();
        while (it.next()) |entry| {
            const surface = entry.view;
            _ = gobject.signalHandlersDisconnectMatched(
                surface.as(gobject.Object),
                .{ .data = true },
                0,
                0,
                null,
                null,
                self,
            );
        }
    }

    //---------------------------------------------------------------
    // Properties

    /// Whether this terminal is a quick terminal or not.
    pub fn isQuickTerminal(self: *Self) bool {
        return self.private().quick_terminal;
    }

    /// Get the currently active surface. See the "active-surface" property.
    /// This does not ref the value.
    pub fn getActiveSurface(self: *Self) ?*Surface {
        const tab = self.getSelectedTab() orelse return null;
        return tab.getActiveSurface();
    }

    fn focusActiveSurface(self: *Self) void {
        const surface = self.getActiveSurface() orelse return;
        surface.grabFocus();
    }

    /// Returns the configuration for this window. The reference count
    /// is not increased.
    pub fn getConfig(self: *Self) ?*Config {
        return self.private().config;
    }

    /// Get the tab view for this window.
    pub fn getTabView(self: *Self) *adw.TabView {
        return self.private().tab_view;
    }

    /// Get the current window decoration value for this window.
    pub fn getWindowDecoration(self: *Self) configpkg.WindowDecoration {
        const priv = self.private();
        if (priv.window_decoration) |v| return v;
        if (priv.config) |v| return v.get().@"window-decoration";
        return .auto;
    }

    /// Toggle the window decorations for this window.
    pub fn toggleWindowDecorations(self: *Self) void {
        const priv = self.private();

        if (priv.window_decoration) |_| {
            // Unset any previously set window decoration settings
            self.setWindowDecoration(null);
            return;
        }

        const config = if (priv.config) |v| v.get() else return;
        self.setWindowDecoration(switch (config.@"window-decoration") {
            // Use auto when the decoration is initially none
            .none => .auto,

            // Anything non-none to none
            .auto, .client, .server => .none,
        });
    }

    /// Set the window decoration override for this window. If this is null,
    /// then we'll revert back to the configuration's default.
    fn setWindowDecoration(
        self: *Self,
        new_: ?configpkg.WindowDecoration,
    ) void {
        const priv = self.private();
        priv.window_decoration = new_;
        self.syncAppearance();
    }

    /// Get the currently selected tab as a Tab object.
    fn getSelectedTab(self: *Self) ?*Tab {
        const priv = self.private();
        const page = priv.tab_view.getSelectedPage() orelse return null;
        const child = page.getChild();
        assert(gobject.ext.isA(child, Tab));
        return gobject.ext.cast(Tab, child);
    }

    /// Returns true if this window needs confirmation before quitting.
    fn getNeedsConfirmQuit(self: *Self) bool {
        const priv = self.private();
        const n = priv.tab_view.getNPages();
        assert(n >= 0);

        for (0..@intCast(n)) |i| {
            const page = priv.tab_view.getNthPage(@intCast(i));
            const child = page.getChild();
            const tab = gobject.ext.cast(Tab, child) orelse {
                log.warn("unexpected non-Tab child in tab view", .{});
                continue;
            };
            if (tab.getNeedsConfirmQuit()) return true;
        }

        return false;
    }

    fn isFullscreen(self: *Window) bool {
        return self.as(gtk.Window).isFullscreen() != 0;
    }

    fn isMaximized(self: *Window) bool {
        return self.as(gtk.Window).isMaximized() != 0;
    }

    fn getHeaderbarVisible(self: *Self) bool {
        const priv = self.private();

        // Never display the header bar when CSDs are disabled.
        const csd_enabled = priv.winproto.clientSideDecorationEnabled();
        if (!csd_enabled) return false;

        // Never display the header bar as a quick terminal.
        if (priv.quick_terminal) return false;

        // If we're fullscreen we never show the header bar.
        if (self.isFullscreen()) return false;

        // The remainder needs a config
        const config_obj = self.private().config orelse return true;
        const config = config_obj.get();

        // *Conditionally* disable the header bar when maximized, and
        // gtk-titlebar-hide-when-maximized is set
        if (self.isMaximized() and config.@"gtk-titlebar-hide-when-maximized") {
            return false;
        }

        return switch (config.@"gtk-titlebar-style") {
            // If the titlebar style is tabs never show the titlebar.
            .tabs => false,

            // If the titlebar style is native show the titlebar if configured
            // to do so.
            .native => config.@"gtk-titlebar",
        };
    }

    fn getTabsAutohide(self: *Self) bool {
        const priv = self.private();
        const config = if (priv.config) |v| v.get() else return true;

        return switch (config.@"gtk-titlebar-style") {
            // If the titlebar style is tabs we cannot autohide.
            .tabs => false,

            .native => switch (config.@"window-show-tab-bar") {
                // Auto we always autohide... obviously.
                .auto => true,

                // Always we never autohide because we always show the tab bar.
                .always => false,

                // Never we autohide because it doesn't actually matter,
                // since getTabsVisible will return false.
                .never => true,
            },
        };
    }

    fn getTabsVisible(self: *Self) bool {
        const priv = self.private();
        const config = if (priv.config) |v| v.get() else return true;

        switch (config.@"gtk-titlebar-style") {
            .tabs => {
                // *Conditionally* disable the tab bar when maximized, the titlebar
                // style is tabs, and gtk-titlebar-hide-when-maximized is set.
                if (self.isMaximized() and config.@"gtk-titlebar-hide-when-maximized") return false;

                // If the titlebar style is tabs the tab bar must always be visible.
                return true;
            },
            .native => {
                return switch (config.@"window-show-tab-bar") {
                    .always, .auto => true,
                    .never => false,
                };
            },
        }
    }

    fn getTabsWide(self: *Self) bool {
        const priv = self.private();
        const config = if (priv.config) |v| v.get() else return true;
        return config.@"gtk-wide-tabs";
    }

    fn getToolbarStyle(self: *Self) adw.ToolbarStyle {
        const priv = self.private();
        const config = if (priv.config) |v| v.get() else return .raised;
        return switch (config.@"gtk-toolbar-style") {
            .flat => .flat,
            .raised => .raised,
            .@"raised-border" => .raised_border,
        };
    }

    fn getTitlebarStyle(self: *Self) TitlebarStyle {
        const priv = self.private();
        const config = if (priv.config) |v| v.get() else return .native;
        return config.@"gtk-titlebar-style";
    }

    fn propConfig(
        _: *adw.ApplicationWindow,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        if (priv.config) |config_obj| {
            const config = config_obj.get();
            if (config.@"app-notifications".@"config-reload") {
                self.addToast(i18n._("Reloaded the configuration"));
            }
        }

        self.syncAppearance();
    }

    fn propGdkSurfaceHeight(
        _: *gdk.Surface,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        // X11 needs to fix blurring on resize, but winproto implementations
        // could do anything.
        self.private().winproto.resizeEvent() catch |err| {
            log.warn(
                "winproto resize event failed error={}",
                .{err},
            );
        };
    }

    fn propIsActive(
        _: *gtk.Window,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        // Hide quick-terminal if set to autohide
        if (self.isQuickTerminal()) {
            if (self.getConfig()) |cfg| {
                if (cfg.get().@"quick-terminal-autohide" and self.as(gtk.Window).isActive() == 0) {
                    self.toggleVisibility();
                }
            }
        }

        // Don't change urgency if we're not the active window.
        if (self.as(gtk.Window).isActive() == 0) return;

        self.winproto().setUrgent(false) catch |err| {
            log.warn(
                "winproto failed to reset urgency={}",
                .{err},
            );
        };
    }

    fn propGdkSurfaceWidth(
        _: *gdk.Surface,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        // X11 needs to fix blurring on resize, but winproto implementations
        // could do anything.
        self.private().winproto.resizeEvent() catch |err| {
            log.warn(
                "winproto resize event failed error={}",
                .{err},
            );
        };
    }

    fn propFullscreened(
        _: *adw.ApplicationWindow,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        self.syncAppearance();
    }

    fn propMaximized(
        _: *adw.ApplicationWindow,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        self.syncAppearance();
    }

    fn propMenuActive(
        button: *gtk.MenuButton,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        // Debian 12 is stuck on GTK 4.8
        if (!gtk_version.atLeast(4, 10, 0)) return;

        // We only care if we're activating. If we're activating then
        // we need to check the validity of our menu items.
        const active = button.getActive() != 0;
        if (!active) return;

        self.syncActions();
    }

    fn propQuickTerminal(
        _: *adw.ApplicationWindow,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        if (priv.surface_init) {
            log.warn("quick terminal property can't be changed after surfaces have been initialized", .{});
            return;
        }

        if (priv.quick_terminal) {
            // Initialize the quick terminal at the app-layer
            Application.default().winproto().initQuickTerminal(self) catch |err| {
                log.warn("failed to initialize quick terminal error={}", .{err});
                return;
            };
        }
    }

    fn propScaleFactor(
        _: *adw.ApplicationWindow,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        // On some platforms (namely X11) we need to refresh our appearance when
        // the scale factor changes. In theory this could be more fine-grained as
        // a full refresh could be expensive, but a) this *should* be rare, and
        // b) quite noticeable visual bugs would occur if this is not present.
        self.private().winproto.syncAppearance() catch |err| {
            log.warn(
                "failed to sync appearance after scale factor has been updated={}",
                .{err},
            );
            return;
        };
    }

    fn closureTitlebarStyleIsTab(
        _: *Self,
        value: TitlebarStyle,
    ) callconv(.c) c_int {
        return @intFromBool(switch (value) {
            .native => false,
            .tabs => true,
        });
    }

    fn closureSubtitle(
        _: *Self,
        config_: ?*Config,
        pwd_: ?[*:0]const u8,
    ) callconv(.c) ?[*:0]const u8 {
        const config = if (config_) |v| v.get() else return null;
        return switch (config.@"window-subtitle") {
            .false => null,
            .@"working-directory" => pwd: {
                const pwd = pwd_ orelse return null;
                break :pwd glib.ext.dupeZ(u8, std.mem.span(pwd));
            },
        };
    }

    fn closureSidebarCwd(
        _: *Self,
        pwd_: ?[*:0]const u8,
    ) callconv(.c) [*:0]const u8 {
        const pwd = pwd_ orelse return glib.ext.dupeZ(u8, "");
        const path = std.mem.trimRight(u8, std.mem.span(pwd), "/");
        if (path.len == 0) return glib.ext.dupeZ(u8, "/");

        var home_buf: [std.fs.max_path_bytes]u8 = undefined;
        const home = homedir.home(&home_buf) catch null;
        if (home) |home_path| {
            if (std.mem.eql(u8, path, home_path)) {
                return glib.ext.dupeZ(u8, "~");
            }
        }

        return glib.ext.dupeZ(u8, std.fs.path.basename(path));
    }

    fn closureSidebarHint(
        _: *Self,
        pos: c_uint,
    ) callconv(.c) [*:0]const u8 {
        if (pos >= 9) return glib.ext.dupeZ(u8, "");

        var buf: [16]u8 = undefined;
        const hint = std.fmt.bufPrintZ(&buf, "Alt+{}", .{pos + 1}) catch
            return glib.ext.dupeZ(u8, "");
        return glib.ext.dupeZ(u8, hint);
    }

    fn closureSidebarHintVisible(
        _: *Self,
        pos: c_uint,
    ) callconv(.c) c_int {
        return @intFromBool(pos < 9);
    }

    fn closureSidebarRunningLabel(
        self: *Self,
        page: ?*adw.TabPage,
    ) callconv(.c) [*:0]const u8 {
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page orelse return glib.ext.dupeZ(u8, "Run")) orelse
            return glib.ext.dupeZ(u8, "Run");
        if (snapshot.running_count <= 1) return glib.ext.dupeZ(u8, "Run");

        var buf: [32]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{} Run", .{snapshot.running_count}) catch
            return glib.ext.dupeZ(u8, "Run");
        return glib.ext.dupeZ(u8, label);
    }

    fn closureSidebarOtherLabel(
        self: *Self,
        page: ?*adw.TabPage,
    ) callconv(.c) [*:0]const u8 {
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page orelse return glib.ext.dupeZ(u8, "State")) orelse
            return glib.ext.dupeZ(u8, "State");
        return glib.ext.dupeZ(u8, snapshot.badge_label orelse "State");
    }

    fn closureSidebarUnreadCount(
        self: *Self,
        page: ?*adw.TabPage,
    ) callconv(.c) [*:0]const u8 {
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page orelse return glib.ext.dupeZ(u8, "")) orelse
            return glib.ext.dupeZ(u8, "");
        if (snapshot.unread_count == 0) return glib.ext.dupeZ(u8, "");

        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{}", .{snapshot.unread_count}) catch
            return glib.ext.dupeZ(u8, "");
        return glib.ext.dupeZ(u8, label);
    }

    fn closureSidebarUnreadVisible(
        self: *Self,
        page: ?*adw.TabPage,
    ) callconv(.c) c_int {
        const snapshot = self.panmuxWorkspaceSnapshotForPage(page orelse return 0) orelse return 0;
        return @intFromBool(snapshot.unread_count > 0);
    }

    fn closureSidebarStatusIsRunning(
        _: *Self,
        loading: c_int,
        keyword_: ?[*:0]const u8,
    ) callconv(.c) c_int {
        return @intFromBool(sidebarStatusIs(loading != 0, keywordOrNull(keyword_), "running"));
    }

    fn closureSidebarStatusIsInfo(
        _: *Self,
        loading: c_int,
        keyword_: ?[*:0]const u8,
    ) callconv(.c) c_int {
        return @intFromBool(sidebarStatusIs(loading != 0, keywordOrNull(keyword_), "info"));
    }

    fn closureSidebarStatusIsWarning(
        _: *Self,
        loading: c_int,
        keyword_: ?[*:0]const u8,
    ) callconv(.c) c_int {
        return @intFromBool(sidebarStatusIs(loading != 0, keywordOrNull(keyword_), "warning"));
    }

    fn closureSidebarStatusIsError(
        _: *Self,
        loading: c_int,
        keyword_: ?[*:0]const u8,
    ) callconv(.c) c_int {
        return @intFromBool(sidebarStatusIs(loading != 0, keywordOrNull(keyword_), "error"));
    }

    fn closureSidebarStatusIsOther(
        _: *Self,
        loading: c_int,
        keyword_: ?[*:0]const u8,
    ) callconv(.c) c_int {
        return @intFromBool(sidebarStatusIs(loading != 0, keywordOrNull(keyword_), "other"));
    }

    fn closureSidebarOverlayIsInfo(
        self: *Self,
        _: c_int,
        _: ?[*:0]const u8,
        page: ?*adw.TabPage,
    ) callconv(.c) c_int {
        return @intFromBool(std.mem.eql(u8, self.sidebarOverlayKind(page), "info"));
    }

    fn closureSidebarOverlayIsWarning(
        self: *Self,
        _: c_int,
        _: ?[*:0]const u8,
        page: ?*adw.TabPage,
    ) callconv(.c) c_int {
        return @intFromBool(std.mem.eql(u8, self.sidebarOverlayKind(page), "warning"));
    }

    fn closureSidebarOverlayIsError(
        self: *Self,
        _: c_int,
        _: ?[*:0]const u8,
        page: ?*adw.TabPage,
    ) callconv(.c) c_int {
        return @intFromBool(std.mem.eql(u8, self.sidebarOverlayKind(page), "error"));
    }

    fn panmuxAckAllAttention(_: *gtk.Button, self: *Self) callconv(.c) void {
        const store = self.panmuxStore();
        for (store.sessions()) |session| {
            if (session.agent_type != .codex) continue;
            if (!panmux_state.isSessionActive(session.phase)) continue;
            if (!self.panmuxWindowHasWorkspace(session.workspace_id)) continue;
            _ = store.ackSessionAttention(session.session_id);
        }

        const n_pages = self.private().tab_view.getNPages();
        var i: c_int = 0;
        while (i < n_pages) : (i += 1) {
            self.refreshPanmuxPage(self.private().tab_view.getNthPage(i));
        }
    }

    //---------------------------------------------------------------
    // Virtual methods

    fn dispose(self: *Self) callconv(.c) void {
        const priv = self.private();

        priv.command_palette.set(null);

        if (priv.config) |v| {
            v.unref();
            priv.config = null;
        }

        priv.tab_bindings.setSource(null);

        gtk.Widget.disposeTemplate(
            self.as(gtk.Widget),
            getGObjectType(),
        );

        gobject.Object.virtual_methods.dispose.call(
            Class.parent,
            self.as(Parent),
        );
    }

    fn finalize(self: *Self) callconv(.c) void {
        const priv = self.private();
        priv.tab_bindings.unref();
        priv.winproto.deinit(Application.default().allocator());

        gobject.Object.virtual_methods.finalize.call(
            Class.parent,
            self.as(Parent),
        );
    }

    //---------------------------------------------------------------
    // Signal handlers

    fn windowRealize(_: *gtk.Widget, self: *Window) callconv(.c) void {
        const app = Application.default();

        // Initialize our window protocol logic
        if (winprotopkg.Window.init(
            app.allocator(),
            app.winproto(),
            self,
        )) |wp| {
            self.private().winproto = wp;
        } else |err| {
            log.warn("failed to initialize window protocol error={}", .{err});
            return;
        }

        // We need to setup resize notifications on our surface,
        // which is only available after the window had been realized.
        if (self.as(gtk.Native).getSurface()) |gdk_surface| {
            _ = gobject.Object.signals.notify.connect(
                gdk_surface,
                *Self,
                propGdkSurfaceWidth,
                self,
                .{ .detail = "width" },
            );
            _ = gobject.Object.signals.notify.connect(
                gdk_surface,
                *Self,
                propGdkSurfaceHeight,
                self,
                .{ .detail = "height" },
            );
        }

        // When we are realized we always setup our appearance since this
        // calls some winproto functions.
        self.syncAppearance();
    }

    fn btnNewTab(_: *adw.SplitButton, self: *Self) callconv(.c) void {
        self.performBindingAction(.new_tab);
    }

    fn tabOverviewCreateTab(
        _: *adw.TabOverview,
        self: *Self,
    ) callconv(.c) *adw.TabPage {
        return self.newTabPage(if (self.getActiveSurface()) |v| v.core() else null, .tab, .none);
    }

    fn tabOverviewOpen(
        tab_overview: *adw.TabOverview,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        // We only care about when the tab overview is closed.
        if (tab_overview.getOpen() != 0) return;

        // On tab overview close, focus is sometimes lost. This is an
        // upstream issue in libadwaita[1]. When this is resolved we
        // can put a runtime version check here to avoid this workaround.
        //
        // Our workaround is to start a timer after 500ms to refocus
        // the currently selected tab. We choose 500ms because the adw
        // animation is 400ms.
        //
        // [1]: https://gitlab.gnome.org/GNOME/libadwaita/-/issues/670

        // If we have an old timer remove it
        const priv = self.private();
        if (priv.tab_overview_focus_timer) |timer| {
            _ = glib.Source.remove(timer);
        }

        // Restart our timer
        priv.tab_overview_focus_timer = glib.timeoutAdd(
            500,
            tabOverviewFocusTimer,
            self,
        );
    }

    fn tabOverviewFocusTimer(
        ud: ?*anyopaque,
    ) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(ud orelse return 0));

        // Always note our timer is removed
        self.private().tab_overview_focus_timer = null;

        // Get our currently active surface which should respect the newly
        // selected tab. Grab focus.
        const surface = self.getActiveSurface() orelse return 0;
        surface.grabFocus();

        // Remove the timer
        return 0;
    }

    fn windowCloseRequest(
        _: *gtk.Window,
        self: *Self,
    ) callconv(.c) c_int {
        if (self.getNeedsConfirmQuit()) {
            // Show a confirmation dialog
            const dialog: *CloseConfirmationDialog = .new(.window);
            _ = CloseConfirmationDialog.signals.@"close-request".connect(
                dialog,
                *Self,
                closeConfirmationClose,
                self,
                .{},
            );

            // Show it
            dialog.present(self.as(gtk.Widget));
            return @intFromBool(true);
        }

        self.as(gtk.Window).destroy();
        return @intFromBool(false);
    }

    fn closeConfirmationClose(
        _: *CloseConfirmationDialog,
        self: *Self,
    ) callconv(.c) void {
        self.as(gtk.Window).destroy();
    }

    fn closeConfirmationCloseTab(
        _: *CloseConfirmationDialog,
        page: *adw.TabPage,
    ) callconv(.c) void {
        const tab_view = ext.getAncestor(
            adw.TabView,
            page.getChild().as(gtk.Widget),
        ) orelse {
            log.warn("close confirmation called for non-existent page", .{});
            return;
        };
        tab_view.closePageFinish(page, @intFromBool(true));
    }

    fn closeConfirmationCancelTab(
        _: *CloseConfirmationDialog,
        page: *adw.TabPage,
    ) callconv(.c) void {
        const tab_view = ext.getAncestor(
            adw.TabView,
            page.getChild().as(gtk.Widget),
        ) orelse {
            log.warn("close confirmation called for non-existent page", .{});
            return;
        };
        tab_view.closePageFinish(page, @intFromBool(false));
    }

    fn tabViewClosePage(
        _: *adw.TabView,
        page: *adw.TabPage,
        self: *Self,
    ) callconv(.c) c_int {
        const priv = self.private();
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse
            return @intFromBool(false);

        // If the tab says it doesn't need confirmation then we go ahead
        // and close immediately.
        if (!tab.getNeedsConfirmQuit()) {
            priv.tab_view.closePageFinish(page, @intFromBool(true));
            return @intFromBool(true);
        }

        // Show a confirmation dialog
        const dialog: *CloseConfirmationDialog = .new(.tab);
        _ = CloseConfirmationDialog.signals.@"close-request".connect(
            dialog,
            *adw.TabPage,
            closeConfirmationCloseTab,
            page,
            .{},
        );
        _ = CloseConfirmationDialog.signals.cancel.connect(
            dialog,
            *adw.TabPage,
            closeConfirmationCancelTab,
            page,
            .{},
        );

        // Show it
        dialog.present(child);
        return @intFromBool(true);
    }

    fn tabViewSelectedPage(
        _: *adw.TabView,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();

        // Always reset our binding source in case we have no pages.
        priv.tab_bindings.setSource(null);

        // Get our current page which MUST be a Tab object.
        const page = priv.tab_view.getSelectedPage() orelse return;
        const child = page.getChild();
        assert(gobject.ext.isA(child, Tab));

        // Setup our binding group. This ensures things like the title
        // are synced from the active tab.
        priv.tab_bindings.setSource(child.as(gobject.Object));

        // If the tab was previously marked as needing attention
        // (e.g. due to a bell character), we now unmark that
        page.setNeedsAttention(@intFromBool(false));
        self.consumePanmuxNeedsInputForPage(page);
        self.refreshPanmuxPage(page);
        self.focusActiveSurface();
    }

    fn tabViewPageAttached(
        _: *adw.TabView,
        page: *adw.TabPage,
        _: c_int,
        self: *Self,
    ) callconv(.c) void {
        // Get the attached page which must be a Tab object.
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return;

        // Attach listeners for the tab.
        _ = Tab.signals.@"close-request".connect(
            tab,
            *Self,
            tabCloseRequest,
            self,
            .{},
        );

        var tab_buf: [32]u8 = undefined;
        const workspace_id = std.fmt.bufPrint(&tab_buf, "{x}", .{@intFromPtr(tab)}) catch null;
        if (workspace_id) |id| {
            self.panmuxStore().ensureWorkspace(id, id) catch |err| {
                log.warn("failed to register panmux workspace err={}", .{err});
            };
            self.refreshPanmuxPage(page);
        }

        // Attach listeners for the surface.
        //
        // Interesting behavior here that was previously undocumented but
        // I'm going to make it explicit here: we accept all the signals here
        // (like toggle-fullscreen) regardless of whether the surface or tab
        // is focused. At the time of writing this we have no API that could
        // really trigger these that way but its theoretically possible.
        //
        // What is DEFINITELY possible is something like OSC52 triggering
        // a clipboard-write signal on an unfocused tab/surface. We definitely
        // want to show the user a notification about that but our notification
        // right now is a toast that doesn't make it clear WHO used the
        // clipboard. We probably want to change that in the future.
        //
        // I'm not sure how desirable all the above is, and we probably
        // should be thoughtful about future signals here. But all of this
        // behavior is consistent with macOS and the previous GTK apprt,
        // but that behavior was all implicit and not documented, so here
        // I am.
        if (tab.getSurfaceTree()) |tree| {
            self.connectSurfaceHandlers(tree);
        }
    }

    fn tabViewPageDetached(
        _: *adw.TabView,
        page: *adw.TabPage,
        _: c_int,
        self: *Self,
    ) callconv(.c) void {
        // We need to get the tab to disconnect the signals.
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return;
        _ = gobject.signalHandlersDisconnectMatched(
            tab.as(gobject.Object),
            .{ .data = true },
            0,
            0,
            null,
            null,
            self,
        );

        // Remove the tree handlers
        if (tab.getSurfaceTree()) |tree| {
            self.disconnectSurfaceHandlers(tree);
        }

        var tab_buf: [32]u8 = undefined;
        const workspace_id = std.fmt.bufPrint(&tab_buf, "{x}", .{@intFromPtr(tab)}) catch return;
        self.panmuxStore().forgetWorkspace(workspace_id);
        self.refreshPanmuxInspector();
    }

    fn tabViewCreateWindow(
        _: *adw.TabView,
        _: *Self,
    ) callconv(.c) *adw.TabView {
        // Create a new window without creating a new tab.
        const win = gobject.ext.newInstance(
            Self,
            .{
                .application = Application.default(),
            },
        );

        // We have to show it otherwise it'll just be hidden.
        gtk.Window.present(win.as(gtk.Window));

        // Get our tab view
        return win.private().tab_view;
    }

    fn tabCloseRequest(
        tab: *Tab,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const page = priv.tab_view.getPage(tab.as(gtk.Widget));
        // TODO: connect close page handler to tab to check for confirmation
        priv.tab_view.closePage(page);
    }

    fn tabViewNPages(
        _: *adw.TabView,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        if (priv.tab_view.getNPages() == 0) {
            // If we have no pages left then we want to close window.

            // If the tab overview is open, then we don't close the window
            // because its a rather abrupt experience. This also fixes an
            // issue where dragging out the last tab in the tab overview
            // won't cause Ghostty to exit.
            if (priv.tab_overview.getOpen() != 0) return;

            self.as(gtk.Window).close();
        }
    }
    fn setupTabMenu(
        _: *adw.TabView,
        page: ?*adw.TabPage,
        self: *Self,
    ) callconv(.c) void {
        self.private().context_menu_page = page;
    }

    fn sidebarActivate(
        _: *gtk.ListView,
        pos: c_uint,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const n_pages = priv.tab_view.getNPages();
        if (pos >= @as(c_uint, @intCast(@max(n_pages, 0)))) return;

        const page = priv.tab_view.getNthPage(@intCast(pos));
        priv.tab_view.setSelectedPage(page);
        self.focusActiveSurface();
    }

    fn tabBarPressed(
        _: *gtk.GestureClick,
        _: c_int,
        _: f64,
        _: f64,
        self: *Self,
    ) callconv(.c) void {
        self.private().tab_bar_pressed_page = self.private().tab_view.getSelectedPage();
    }

    fn tabBarReleased(
        _: *gtk.GestureClick,
        _: c_int,
        _: f64,
        _: f64,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const pressed_page = priv.tab_bar_pressed_page orelse return;
        defer priv.tab_bar_pressed_page = null;

        const selected_page = priv.tab_view.getSelectedPage() orelse return;
        if (selected_page != pressed_page) return;
    }

    fn surfaceClipboardWrite(
        _: *Surface,
        clipboard_type: apprt.Clipboard,
        text: [*:0]const u8,
        self: *Self,
    ) callconv(.c) void {
        // We only toast for the standard clipboard.
        if (clipboard_type != .standard) return;

        // We only toast if configured to
        const priv = self.private();
        const config_obj = priv.config orelse return;
        const config = config_obj.get();
        if (!config.@"app-notifications".@"clipboard-copy") {
            return;
        }

        if (text[0] != 0)
            self.addToast(i18n._("Copied to clipboard"))
        else
            self.addToast(i18n._("Cleared clipboard"));
    }

    fn surfaceMenu(
        _: *Surface,
        self: *Self,
    ) callconv(.c) void {
        self.syncActions();
    }

    fn surfacePresentRequest(
        surface: *Surface,
        self: *Self,
    ) callconv(.c) void {
        // Verify that this surface is actually in this window.
        {
            const surface_window = ext.getAncestor(
                Self,
                surface.as(gtk.Widget),
            ) orelse {
                log.warn(
                    "present request called for non-existent surface",
                    .{},
                );
                return;
            };
            if (surface_window != self) {
                log.warn(
                    "present request called for surface in different window",
                    .{},
                );
                return;
            }
        }

        // Get the tab for this surface.
        const tab = ext.getAncestor(
            Tab,
            surface.as(gtk.Widget),
        ) orelse {
            log.warn("present request surface not found", .{});
            return;
        };

        // Get the page that contains this tab
        const priv = self.private();
        const tab_view = priv.tab_view;
        const page = tab_view.getPage(tab.as(gtk.Widget));
        tab_view.setSelectedPage(page);

        // Grab focus
        surface.grabFocus();

        // Bring the window to the front.
        self.as(gtk.Window).present();
    }

    fn surfaceToggleFullscreen(
        surface: *Surface,
        self: *Self,
    ) callconv(.c) void {
        _ = surface;
        if (self.as(gtk.Window).isFullscreen() != 0) {
            self.as(gtk.Window).unfullscreen();
        } else {
            self.as(gtk.Window).fullscreen();
        }

        // We react to the changes in the propFullscreen callback
    }

    fn surfaceToggleMaximize(
        surface: *Surface,
        self: *Self,
    ) callconv(.c) void {
        _ = surface;
        if (self.as(gtk.Window).isMaximized() != 0) {
            self.as(gtk.Window).unmaximize();
        } else {
            self.as(gtk.Window).maximize();
        }

        // We react to the changes in the propMaximized callback
    }

    fn surfaceInit(
        surface: *Surface,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();

        // Make sure we init only once
        if (priv.surface_init) return;
        priv.surface_init = true;

        // Setup our default and minimum size.
        if (surface.getDefaultSize()) |size| {
            self.as(gtk.Window).setDefaultSize(
                @intCast(size.width),
                @intCast(size.height),
            );
        }
        if (surface.getMinSize()) |size| {
            self.as(gtk.Widget).setSizeRequest(
                @intCast(size.width),
                @intCast(size.height),
            );
        }
    }

    fn tabSplitTreeChanged(
        _: *SplitTree,
        old_tree: ?*const Surface.Tree,
        new_tree: ?*const Surface.Tree,
        self: *Self,
    ) callconv(.c) void {
        if (old_tree) |tree| {
            self.disconnectSurfaceHandlers(tree);
        }

        if (new_tree) |tree| {
            self.connectSurfaceHandlers(tree);
        }
    }

    fn actionAbout(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Self,
    ) callconv(.c) void {
        const name = "panmux";
        const icon = gresource.app_id;
        const website = "https://github.com/forbidden-game/panmux";

        if (adw_version.supportsDialogs()) {
            adw.showAboutDialog(
                self.as(gtk.Widget),
                "application-name",
                name,
                "developer-name",
                i18n._("panmux Developers"),
                "application-icon",
                icon,
                "version",
                build_config.version_string.ptr,
                "issue-url",
                "https://github.com/forbidden-game/panmux/issues",
                "website",
                website,
                @as(?*anyopaque, null),
            );
        } else {
            gtk.showAboutDialog(
                self.as(gtk.Window),
                "program-name",
                name,
                "logo-icon-name",
                icon,
                "title",
                i18n._("About Ghostty"),
                "version",
                build_config.version_string.ptr,
                "website",
                website,
                @as(?*anyopaque, null),
            );
        }
    }

    fn actionClose(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Self,
    ) callconv(.c) void {
        self.as(gtk.Window).close();
    }

    fn actionCloseTab(
        _: *gio.SimpleAction,
        param_: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        const param = param_ orelse {
            log.warn("win.close-tab called without a parameter", .{});
            return;
        };

        var str: ?[*:0]const u8 = null;
        param.get("&s", &str);

        const mode = std.meta.stringToEnum(
            input.Binding.Action.CloseTabMode,
            std.mem.span(
                str orelse {
                    log.warn("invalid mode provided to win.close-tab", .{});
                    return;
                },
            ),
        ) orelse {
            log.warn("invalid mode provided to win.close-tab: {s}", .{str.?});
            return;
        };

        self.performBindingAction(.{ .close_tab = mode });
    }

    fn actionNewWindow(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.new_window);
    }

    fn actionNewTab(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.new_tab);
    }

    fn actionPromptContextTabTitle(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Self,
    ) callconv(.c) void {
        const priv = self.private();
        const page = priv.context_menu_page orelse return;
        const child = page.getChild();
        const tab = gobject.ext.cast(Tab, child) orelse return;
        tab.promptTabTitle();
    }

    fn actionPromptSurfaceTitle(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.prompt_surface_title);
    }

    fn actionPromptTabTitle(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.prompt_tab_title);
    }

    fn actionSplitRight(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.{ .new_split = .right });
    }

    fn actionSplitLeft(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.{ .new_split = .left });
    }

    fn actionSplitUp(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.{ .new_split = .up });
    }

    fn actionSplitDown(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.{ .new_split = .down });
    }

    fn actionCopy(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.{ .copy_to_clipboard = .mixed });
    }

    fn actionPaste(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.paste_from_clipboard);
    }

    fn actionReset(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.reset);
    }

    fn actionClear(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        self.performBindingAction(.clear_screen);
    }

    fn actionRingBell(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        const priv = self.private();
        const config = if (priv.config) |v| v.get() else return;

        if (config.@"bell-features".system) system: {
            const native = self.as(gtk.Native).getSurface() orelse {
                log.warn("unable to get native surface from window", .{});
                break :system;
            };
            native.beep();
        }

        if (config.@"bell-features".attention) attention: {
            // Dont set urgency if the window is already active.
            if (self.as(gtk.Window).isActive() != 0) break :attention;

            // Request user attention
            self.winproto().setUrgent(true) catch |err| {
                log.warn("winproto failed to set urgency={}", .{err});
            };
        }
    }

    /// Toggle the command palette.
    ///
    /// TODO: accept the surface that toggled the command palette as a parameter
    fn toggleCommandPalette(self: *Window) void {
        const priv = self.private();

        // Get a reference to a command palette. First check the weak reference
        // that we save to see if we already have one stored. If we don't then
        // create a new one.
        const command_palette = priv.command_palette.get() orelse command_palette: {
            // Create a fresh command palette.
            const command_palette = CommandPalette.new();

            // Synchronize our config to the command palette's config.
            _ = gobject.Object.bindProperty(
                self.as(gobject.Object),
                "config",
                command_palette.as(gobject.Object),
                "config",
                .{ .sync_create = true },
            );

            // Listen to the activate signal to know if the user selected an option in
            // the command palette.
            _ = CommandPalette.signals.trigger.connect(
                command_palette,
                *Window,
                signalCommandPaletteTrigger,
                self,
                .{},
            );

            // Save a weak reference to the command palette. We use a weak reference to avoid
            // reference counting cycles that might cause problems later.
            priv.command_palette.set(command_palette);

            break :command_palette command_palette;
        };
        defer command_palette.unref();

        // Tell the command palette to toggle itself. If the dialog gets
        // presented (instead of hidden) it will be modal over our window.
        command_palette.toggle(self);
    }

    // React to a signal from a command palette asking an action to be performed.
    fn signalCommandPaletteTrigger(_: *CommandPalette, action: *const input.Binding.Action, self: *Self) callconv(.c) void {
        // If the activation actually has an action, perform it.
        self.performBindingAction(action.*);
    }

    /// React to a GTK action requesting that the command palette be toggled.
    fn actionToggleCommandPalette(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        // TODO: accept the surface that toggled the command palette as a
        // parameter
        self.toggleCommandPalette();
    }

    /// Toggle the Ghostty inspector for the active surface.
    fn toggleInspector(self: *Self) void {
        const surface = self.getActiveSurface() orelse return;
        _ = surface.controlInspector(.toggle);
    }

    /// React to a GTK action requesting that the Ghostty inspector be toggled.
    fn actionToggleInspector(
        _: *gio.SimpleAction,
        _: ?*glib.Variant,
        self: *Window,
    ) callconv(.c) void {
        // TODO: accept the surface that toggled the command palette as a
        // parameter
        self.toggleInspector();
    }

    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    const private = C.private;

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        fn init(class: *Class) callconv(.c) void {
            gobject.ext.ensureType(DebugWarning);
            gobject.ext.ensureType(SplitTree);
            gobject.ext.ensureType(Surface);
            gobject.ext.ensureType(Tab);
            gtk.Widget.Class.setTemplateFromResource(
                class.as(gtk.Widget.Class),
                comptime gresource.blueprint(.{
                    .major = 1,
                    .minor = 5,
                    .name = "window",
                }),
            );

            // Properties
            gobject.ext.registerProperties(class, &.{
                properties.@"active-surface".impl,
                properties.config.impl,
                properties.debug.impl,
                properties.@"headerbar-visible".impl,
                properties.@"quick-terminal".impl,
                properties.@"tabs-autohide".impl,
                properties.@"tabs-visible".impl,
                properties.@"tabs-wide".impl,
                properties.@"toolbar-style".impl,
                properties.@"titlebar-style".impl,
            });

            // Bindings
            class.bindTemplateChildPrivate("tab_overview", .{});
            class.bindTemplateChildPrivate("sidebar", .{});
            class.bindTemplateChildPrivate("panmux_detail_title", .{});
            class.bindTemplateChildPrivate("panmux_detail_summary", .{});
            class.bindTemplateChildPrivate("panmux_ack_button", .{});
            class.bindTemplateChildPrivate("panmux_session_source", .{});
            class.bindTemplateChildPrivate("panmux_attention_source", .{});
            class.bindTemplateChildPrivate("tab_bar", .{});
            class.bindTemplateChildPrivate("tab_view", .{});
            class.bindTemplateChildPrivate("toolbar", .{});
            class.bindTemplateChildPrivate("toast_overlay", .{});

            // Template Callbacks
            class.bindTemplateCallback("realize", &windowRealize);
            class.bindTemplateCallback("new_tab", &btnNewTab);
            class.bindTemplateCallback("overview_create_tab", &tabOverviewCreateTab);
            class.bindTemplateCallback("overview_notify_open", &tabOverviewOpen);
            class.bindTemplateCallback("close_request", &windowCloseRequest);
            class.bindTemplateCallback("close_page", &tabViewClosePage);
            class.bindTemplateCallback("page_attached", &tabViewPageAttached);
            class.bindTemplateCallback("page_detached", &tabViewPageDetached);
            class.bindTemplateCallback("sidebar_activate", &sidebarActivate);
            class.bindTemplateCallback("setup_tab_menu", &setupTabMenu);
            class.bindTemplateCallback("tab_create_window", &tabViewCreateWindow);
            class.bindTemplateCallback("notify_n_pages", &tabViewNPages);
            class.bindTemplateCallback("notify_selected_page", &tabViewSelectedPage);
            class.bindTemplateCallback("notify_config", &propConfig);
            class.bindTemplateCallback("notify_fullscreened", &propFullscreened);
            class.bindTemplateCallback("notify_is_active", &propIsActive);
            class.bindTemplateCallback("notify_maximized", &propMaximized);
            class.bindTemplateCallback("notify_menu_active", &propMenuActive);
            class.bindTemplateCallback("notify_quick_terminal", &propQuickTerminal);
            class.bindTemplateCallback("notify_scale_factor", &propScaleFactor);
            class.bindTemplateCallback("sidebar_cwd", &closureSidebarCwd);
            class.bindTemplateCallback("sidebar_hint", &closureSidebarHint);
            class.bindTemplateCallback("sidebar_hint_visible", &closureSidebarHintVisible);
            class.bindTemplateCallback("sidebar_running_label", &closureSidebarRunningLabel);
            class.bindTemplateCallback("sidebar_other_label", &closureSidebarOtherLabel);
            class.bindTemplateCallback("sidebar_unread_count", &closureSidebarUnreadCount);
            class.bindTemplateCallback("sidebar_unread_visible", &closureSidebarUnreadVisible);
            class.bindTemplateCallback("sidebar_status_is_running", &closureSidebarStatusIsRunning);
            class.bindTemplateCallback("sidebar_status_is_info", &closureSidebarStatusIsInfo);
            class.bindTemplateCallback("sidebar_status_is_warning", &closureSidebarStatusIsWarning);
            class.bindTemplateCallback("sidebar_status_is_error", &closureSidebarStatusIsError);
            class.bindTemplateCallback("sidebar_status_is_other", &closureSidebarStatusIsOther);
            class.bindTemplateCallback("sidebar_overlay_is_info", &closureSidebarOverlayIsInfo);
            class.bindTemplateCallback("sidebar_overlay_is_warning", &closureSidebarOverlayIsWarning);
            class.bindTemplateCallback("sidebar_overlay_is_error", &closureSidebarOverlayIsError);
            class.bindTemplateCallback("panmux_ack_all_attention", &panmuxAckAllAttention);
            class.bindTemplateCallback("titlebar_style_is_tabs", &closureTitlebarStyleIsTab);
            class.bindTemplateCallback("computed_subtitle", &closureSubtitle);

            // Virtual methods
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
        }

        pub const as = C.Class.as;
        pub const bindTemplateChildPrivate = C.Class.bindTemplateChildPrivate;
        pub const bindTemplateCallback = C.Class.bindTemplateCallback;
    };
};

test "panmux info states stay plain info" {
    const turn_complete = Window.storedPanmuxState("info");
    try std.testing.expectEqualStrings("info", turn_complete);

    try std.testing.expectEqualStrings("info", Window.publicPanmuxState(turn_complete).?);
}

test "panmux running is derived separately from stored status" {
    try std.testing.expectEqualStrings("", Window.storedPanmuxState("running"));
    try std.testing.expectEqualStrings("running", Window.sidebarStatusKind(true, null));
    try std.testing.expectEqualStrings("info", Window.sidebarStatusKind(false, "info"));
    try std.testing.expectEqualStrings("warning", Window.sidebarStatusKind(false, "warning"));
    try std.testing.expectEqualStrings("error", Window.sidebarStatusKind(false, "error"));
    try std.testing.expectEqualStrings("other", Window.sidebarStatusKind(false, "custom"));
    try std.testing.expectEqualStrings("empty", Window.sidebarStatusKind(false, null));
}

test "sidebar status helpers agree on visibility" {
    try std.testing.expect(Window.sidebarStatusIs(false, "info", "info"));
    try std.testing.expect(Window.sidebarStatusIs(false, "warning", "warning"));
    try std.testing.expect(!Window.sidebarStatusIs(false, "warning", "info"));
    try std.testing.expectEqualStrings("info", Window.sidebarOverlayKindForOverlay(.info));
    try std.testing.expectEqualStrings("warning", Window.sidebarOverlayKindForOverlay(.warning));
    try std.testing.expectEqualStrings("error", Window.sidebarOverlayKindForOverlay(.@"error"));
    try std.testing.expectEqualStrings("", Window.sidebarOverlayKindForOverlay(.none));
}

test "panmux desktop notification maps pong to plain info" {
    const params = Window.desktopNotificationPanmuxParams("", "pong");
    try std.testing.expectEqualStrings("info", params.state.?);
    try std.testing.expectEqualStrings("info", Window.publicPanmuxState(params.state).?);
}

test "panmux running status is preserved across notifications" {
    try std.testing.expect(Window.panmuxShouldPreserveRunningStatus(true, ""));
    try std.testing.expect(Window.panmuxShouldPreserveRunningStatus(true, "info"));
    try std.testing.expect(Window.panmuxShouldPreserveRunningStatus(true, "warning"));
    try std.testing.expect(!Window.panmuxShouldPreserveRunningStatus(true, "running"));
    try std.testing.expect(!Window.panmuxShouldPreserveRunningStatus(false, "info"));
}

test "panmux attention is only for state-less notifications" {
    try std.testing.expect(Window.panmuxShouldMarkNeedsAttention(""));
    try std.testing.expect(!Window.panmuxShouldMarkNeedsAttention("running"));
    try std.testing.expect(!Window.panmuxShouldMarkNeedsAttention("info"));
    try std.testing.expect(!Window.panmuxShouldMarkNeedsAttention("warning"));
}

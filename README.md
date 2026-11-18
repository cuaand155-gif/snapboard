# Snapboard

A Mac menu bar app for arranging windows and setting up a workspace. Its main areas are:

1. **Snaps windows into zones you draw.** Hold **Shift** while dragging a window: your zones light up, and the window fills whichever zone you let go over. Dragging without Shift works exactly as before.
2. **Shows desktop widgets.** A clock, your **Lifeboard** tasks and medication times, the weather, and what's playing. They sit on your desktop, under your normal windows.
3. **Saves workspaces and a shared library.** Keep apps, links, folders, and actions in one library. Arrange launcher pages and choose which items belong to each workspace.
4. **Runs actions and keyboard triggers.** Build a sequence that opens saved items, switches workspaces, or snaps the front window. Assign an enabled action to a keyboard shortcut.
5. **Adds custom surfaces.** Put library items in floating docks and menu groups, with optional workspace and display choices.
6. **Saves native Dock presets.** Capture the Mac Dock's apps, folders, position, size, and visibility, preview a preset, and apply it with a confirmation. Snapboard keeps a snapshot for a one-step restore.
7. **Records the screen.** Choose a display or window, optionally include a webcam corner and audio, then trim and export a `.mov` file.

8. **Vinyl turntable widget (inspired by Vinyl).** A live, animated rotating turntable on your desktop with vinyl groove reflections, live album art on the label, a physical tonearm that moves onto the record when music plays, playback controls, and transparent/solid deck options.
9. **Drop shelf (inspired by Droppy).** Stash files, images, or text in a floating shelf docked below the notch/menu bar across spaces. Drag files out anywhere, or run quick actions: merge files into a PDF, convert images to PNG, or copy paths.
10. **Fullscreen launcher (inspired by LaunchOS).** A full-screen Liquid Glass app launcher with instant keyboard search, high-res app icons, arrow-key navigation, and Return to launch.

---

## 1. Download the app (easiest)

GitHub builds Snapboard for you every time the code changes. No Xcode needed.

1. Open **github.com/cuaand155-gif/snapboard/actions** and click the newest run with a green tick.
2. Scroll to **Artifacts** at the bottom and click **Snapboard** to download it.
3. In Downloads, double-click the downloaded ZIP, then double-click the **Snapboard.zip** inside it. You now have **Snapboard.app**.
4. Drag **Snapboard.app** into your **Applications** folder.

It runs on both newer (Apple silicon) and older (Intel) Macs.

## 2. Or build it yourself (only if you want to)

You need **Xcode** from the App Store (open it once and accept the licence). Then download the code (**Code → Download ZIP** on GitHub), open **Terminal**, type `cd `, drag the unzipped `snapboard` folder in, press Return, and run:

```bash
./scripts/build-app.sh
```

The app appears in the `build` folder. If it stops with an error, copy everything Terminal printed and paste it to Claude.

## 3. First launch

1. Open **Snapboard** from Applications. macOS will say it can't check the app, because it isn't from the App Store. Press **Done**, then go to **System Settings → Privacy & Security**, scroll down, and press **Open Anyway** next to the Snapboard message. Confirm with your password. You only do this once per new version.
2. A welcome window asks for Accessibility permission to move windows. Press **Open Accessibility settings**, then switch **Snapboard** on in the list. The welcome window closes by itself. Recording and webcam access are requested separately when you use those features.
3. Look for the new icon in your menu bar (two side-by-side rectangles). Everything is in that menu.

## Using it

**Snap a window:** start dragging a window by its title bar, hold **Shift**, move over a zone, and let go.

**Keyboard shortcuts** (Control + Option, plus a key): **←** left half, **→** right half, **↑** top half, **↓** bottom half, **Return** fill the screen. You can switch them off in Settings.

**Change your zones:** menu bar icon → **Edit layout…**

- **Start from…** picks a ready-made layout (halves, thirds, big left with two on the right, quarters).
- Click a zone to select it, then **Split side by side**, **Split top / bottom** or **Remove zone**.
- Drag the white bars between zones to resize them.
- Press **Save**, or **Cancel** (or Escape) to leave it unchanged.

Each screen keeps its own layout. To switch quickly without editing, use **Quick layout** in the menu.

### Workspaces

A workspace saves the zone layouts on your connected screens and a list of apps or links you choose. Switching workspaces applies its saved zones for future snaps. It does not move windows that are already open, close apps, or change the macOS Dock.

1. Set up your zones with **Edit layout…** or **Quick layout**.
2. Click the Snapboard menu bar icon → **Workspaces** → **Manage workspaces…**.
3. Type a name under **New workspace name**, then click **Save current layouts as workspace**.
4. Select that workspace in the left list. Click **Add application…** to pick a `.app` in Finder, or enter a full `https://` link and click **Add link**. Apps and links stay saved until you click **Remove** beside one.
5. Click **Use workspace**, or choose its name in the menu bar **Workspaces** submenu, to apply its saved zones. To open a saved app or link, click **Open** beside it in the editor, or use **Workspaces → Open saved item** for the current workspace. Switching a workspace does not automatically launch its items.
6. After changing your zones, select the workspace and click **Update saved layouts from current screens** to save those changes into it. Zone changes are not copied into a workspace automatically.

If an app was moved or removed, Snapboard says it cannot open it. Remove the old entry and add the app from its current location. Links must begin with `http://` or `https://`.

### Library and launcher

1. Menu bar icon → **Library and launcher…**. Save an app, link, folder, or action. Add tags to find it later and select the workspaces where it belongs.
2. Choose **Launcher** at the top to make pages and place saved items on them. Open an item from the library or launcher.
3. Use **Export…** for a JSON copy of your library or **Import…** to add items from one. Check the imported items before opening them.

### Actions and triggers

1. Menu bar icon → **Automation…** → **New action**. Add steps in the order you want them to run, such as opening a saved item, switching a workspace, opening a link, or snapping the front window.
2. Press **Run** to try the action. Under **Keyboard triggers**, add a shortcut for it. A warning appears if it conflicts with another enabled trigger or a built-in shortcut.
3. **Settings… → Keyboard shortcuts** controls whether saved keyboard triggers are active. The setting takes effect when you close Settings. Actions remain available in the library when shortcuts are off.

### Custom surfaces

1. Menu bar icon → **Custom surfaces → Manage docks and groups…** to add a floating dock or a menu group. Choose its items from the shared library and, if useful, associate it with workspaces.
2. For a floating dock, choose an edge and display and whether to hide it until hovered. Menu groups appear under **Custom surfaces**; **Search menu items…** opens the picker.

### Native Dock presets

1. Menu bar icon → **Dock presets…** → **Capture current Dock**. Select a saved preset to preview the differences.
2. Press **Apply preset…** and confirm to change the macOS Dock. **Restore previous Dock…** returns to the snapshot Snapboard saved just before the last apply.

### Screen recording

1. Menu bar icon → **Record screen…**. Choose a display or window. Choose cursor, audio, webcam corner, and center zoom options before starting.
2. Press **Start recording**. The menu bar icon turns red while recording; open the menu to stop it even if you closed the recorder window.
3. Adjust the start and end trim points, then press **Export…** and choose where to save the `.mov` file. If you do not want the capture, use **Discard…**. Snapboard keeps running until an active or pending capture is resolved.

macOS may request Screen Recording, Microphone, and Camera access when you use those inputs. Declining an optional input leaves the rest of the app available.

**Widgets:** menu bar icon → **Widgets** → pick one to add it, or pick it again to remove it. Drag a widget anywhere and it lines up neatly on an invisible grid. Right-click a widget for **Remove widget** (and **Refresh now** on the Lifeboard and weather widgets).

## Connect Lifeboard (for the Lifeboard and weather widgets)

This needs the Lifeboard update that adds the widget feed, plus a `WIDGET_TOKEN` in Vercel. The Lifeboard README section **"Snapboard Mac widgets"** walks through it.

1. Menu bar icon → **Settings…**
2. **Lifeboard address**: your site's address, for example `lifeboard-yourname.vercel.app`.
3. **Widget token**: the same characters you saved as `WIDGET_TOKEN` in Vercel.
4. Press **Save and test connection**. It should say **Connected**.

Once the address is saved, **Open Lifeboard** in the menu (or the ↗ button on the Lifeboard widget) opens your site in the browser.

The token is kept in your Mac's Keychain, never in a file. Snapboard only reads from Lifeboard and can't change anything there. If you're offline, the widgets keep showing the last update.

**Now playing** reads Spotify or Apple Music, but only while that widget is on your desktop and only if the app is already open. The first time, macOS asks whether Snapboard may talk to it: say OK. It never opens or controls them.

## Good to know

- **Open at login:** Settings → **Open Snapboard when I log in**.
- **After building a new version:** macOS treats each new build as a different app, so snapping stops working even though Snapboard still looks switched on. Fix it once per new build: System Settings → Privacy & Security → Accessibility, select **Snapboard**, press the **–** button, then open Snapboard again and allow it when asked. A paid Apple Developer membership would stop this.
- **Windows that won't resize:** some apps have fixed-size windows. They move into the zone but keep their own size.
- **Settings file:** your layouts and widget positions are saved in `~/Library/Application Support/Snapboard/settings.json`. Deleting it resets Snapboard.

## For developers

See `CLAUDE.md`. `swift test` runs the core tests (needs Xcode).

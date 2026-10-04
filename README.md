# Snapboard

A small Mac app that lives in your menu bar. It does two things:

1. **Snaps windows into zones you draw.** Hold **Shift** while dragging a window: your zones light up, and the window fills whichever zone you let go over. Dragging without Shift works exactly as before.
2. **Shows desktop widgets.** A clock, your **Lifeboard** tasks and medication times, the weather, and what's playing. They sit on your desktop, under your normal windows.

It's version 0.1, so expect rough edges. Tell Claude what feels wrong.

---

## 1. Get it onto your Mac (once)

You need **Xcode**, Apple's free app for building Mac apps.

1. Open the **App Store**, search for **Xcode**, and install it. It's large, so this can take a while.
2. Open Xcode once, accept the licence, let it finish installing its extras, then quit it.
3. On GitHub, open **cuaand155-gif/snapboard**, click the green **Code** button, then **Download ZIP**.
4. Double-click the ZIP in your Downloads folder to unzip it. You get a folder called `snapboard` (maybe with a branch name added to the end).

## 2. Build the app

1. Open **Terminal** (press ⌘-Space, type *Terminal*, press Return).
2. Type `cd ` (with a space after it), drag the `snapboard` folder from Finder into the Terminal window, then press Return.
3. Paste this and press Return:

   ```bash
   ./scripts/build-app.sh
   ```

4. Wait until it says **Done**. The app is now in the `build` folder inside `snapboard`.
5. Drag **Snapboard.app** from that `build` folder into your **Applications** folder.

If it stops with an error instead, copy everything Terminal printed and paste it to Claude.

## 3. First launch

1. Open **Snapboard** from Applications. If macOS says it's from an unidentified developer, right-click the app, choose **Open**, then **Open** again. You only do this once.
2. A welcome window asks for one permission. Press **Open Accessibility settings**, then switch **Snapboard** on in the list. The welcome window closes by itself.
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

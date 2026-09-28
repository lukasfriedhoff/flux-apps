# h4xx Valheim — server manual

For everyone who has been given access. Nothing here needs a shell, `kubectl`,
or a Kubernetes login — two web pages cover all of it.

| | |
|---|---|
| **Controls** | <https://valheim.h4xx.io> — status, backups, restart |
| **Files** | <https://valheim-files.h4xx.io> — worlds, mods, admin list |
| **Connect** | `redacted.invalid:2456` (on the LAN: `10.1.20.43:2456`) |

Both pages sit behind the usual single sign-on, so if you can open one you can
open the other.

## Joining

Easiest path is *Join Game → Community* in the server browser and search for
the server name. Otherwise add it manually with the address above. The join
password is the one you were given — it is not written down here on purpose.

The server is on **Valheim 1.0**. It updates itself every 15 minutes, but only
while nobody is playing, so a patch never drops you mid-raid.

## Installing a mod

1. Get the mod's `.dll` (Thunderstore is the usual source).
2. Open the **file browser** and go to `bepinex/plugins/`.
3. Drag the `.dll` in.
4. Open the **controls** page and press **Restart server**.

That is the whole procedure. BepInEx — the thing that loads mods — is already
installed and keeps itself updated, so you never touch it.

Three things that will bite you, in the order they usually do:

- **Everyone needs the same mods.** Valheim mods are client *and* server side.
  If the server loads a mod and your game does not, you cannot join at all.
  Agree on a list before installing anything.
- **Most pre-1.0 mods are broken right now.** 1.0 was a major release with a
  Unity engine upgrade, and the developers state plainly that they cannot
  guarantee any mod still works. If a mod misbehaves, check whether its author
  has shipped a 1.0 build before assuming the server is at fault.
- **A mod can break joining silently.** The symptom is a server that looks
  healthy and refuses connections. Use **Server status** on the controls page:
  if it answers but nobody can join, suspect the newest mod, remove the `.dll`,
  restart.

To uninstall, delete the `.dll` and restart. There is no other state to clean.

## Uploading a world

Worlds live in `worlds_local/` in the file browser, one folder per world.

**Close Valheim on your PC first.** A running game keeps the save files open,
and the usual result is that only the map-cache files copy across and the
actual world silently does not. That has already happened once here.

Then copy the **entire** world folder from

```
%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local\
```

A complete upload contains, besides the `cacheMinimap*` files:

- `_main.<number>.db2` — the world itself, the important one
- `_main.<number>.fwl2` — seed and metadata
- `_main.<number>.chunks` and `_main.<number>.ok`
- one or more `*.chunk` files

If all you see after uploading are four `cacheMinimap*` files, the world did
not come with it. Nothing is broken, it just is not there yet.

Note that world names get truncated to 20 characters, so check the folder name
survived the trip.

## Switching which world runs

This one is not self-service, and not because of permissions: a Valheim
dedicated server hosts exactly **one** world, chosen when it starts. There is
no in-game world picker, and the setting lives in the server's deployment
config rather than in any file you can reach.

So: ask Lukas, it is a one-line change. If two worlds need to be playable at
the same time, that means a second server instance rather than a setting —
also possible, also ask.

Switching does not delete anything. Old worlds stay on disk.

## Backups

Three buttons on the controls page:

- **Backup now** — take one immediately, e.g. before trying something risky.
- **List snapshots** — show what can be restored, with dates.
- **Restore snapshot (STOPS the server)** — exactly what it says.

On top of that the server writes its own world snapshots every 6 hours and
keeps a few days, and a separate nightly job ships everything off-site. So
there are two independent layers before anything is truly lost.

**Restoring rolls the world back for everybody.** Check **Server status**
first, and tell people.

## Please do not

- Delete or rename anything inside `worlds_local/` other than a world folder
  you uploaded yourself. The auto-backup folders are the server's safety net.
- Restore a snapshot while people are playing.
- Install a mod on the server without telling the others — they will be locked
  out until they install it too.

## When something is wrong

| Symptom | First thing to check |
|---|---|
| Server not in the browser list | **Check Steam listing** on the controls page. Steam sometimes drops a server that is running fine. |
| Cannot join, others can | Your mods differ from the server's. |
| Nobody can join, server looks up | Newest mod. Remove the `.dll`, restart. |
| World looks older than it should | Someone restored a snapshot. **List snapshots** shows when. |
| Uploaded world does not appear | It is not selected yet — see *Switching which world runs*. Also confirm the `_main.*.db2` file actually uploaded. |

If none of that fits, grab the time it happened and ask Lukas — the server
keeps logs, so an exact time makes it findable.

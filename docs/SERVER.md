# Running a dedicated server (optional, free)

Normal hosting is unchanged: **Host** in the game's menu, the lobby is listed on the LAN / internet board, UPnP is tried for you. A dedicated server is an *extra option* for when you want a game that stays up without anybody sitting in it.

## Start it
Any computer with the game folder and Godot 4.4.1 (no graphics card or screen needed):

    godot --headless --path . -- --server "--name=My server" --password=secret --wait=60

- `--name=`      lobby name (default "Dedicated server")
- `--password=`  optional; players need it to join
- `--wait=`      seconds before the round starts by itself when not everybody has locked a ship (default: the normal lobby timer)
- `--port=`      UDP port (default 24565; forward it on your router when the computer is at home)

The server is not a player: it starts the round when everybody is ready (or after `--wait`), and lets new players join while it runs. Stop it with Ctrl+C. Test: `bash tests/run_server_test.sh`.

## Where to run it without paying
There is no truly free *and* card-free 24/7 machine; these are the realistic free options (checked 8 Nov 2026; terms change, read them before you rely on them):

1. **Your own PC / an old laptop / a Raspberry Pi** - free, no card. Only on while that machine is on. Forward UDP 24565 on the router (or rely on UPnP). This is the zero-risk option and the one to start with.
2. **Oracle Cloud "Always Free"** - 2 ARM cores + 12 GB RAM (or two tiny x86 VMs), 10 TB/month traffic. Needs a credit/debit card for identity verification (not charged unless you upgrade; no prepaid cards). Catches: instances under ~20% CPU for 7 days may be reclaimed, "out of capacity" errors in some regions, idle accounts can be closed. Godot has Linux ARM64 builds.
3. **Google Cloud "Always Free" e2-micro** - one tiny VM (about 1 GB RAM) in some US regions; card required; outbound traffic beyond the free allowance is billed, so watch it. A 1 GB machine is tight for big fleets.

Nothing here is needed to play: friends can always join the host in the normal way.

PIZZA PANIC - CO-OP NETWORKING TEST
A tiny throwaway project that proves the multiplayer approach before the real co-op rebuild.
One room, a table, two soda cans. Players can see each other move, pick up cans, and throw them.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HOW THE NETWORKING WORKS (the pattern the rebuild will use)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- One player HOSTS. Their game is the "real" world: physics props, who holds what.
- Each player controls their OWN character and broadcasts its position/look direction.
- To change the world (pick up a can, throw it), a player ASKS the host. The host checks
  it's allowed, applies it, and the change syncs out to everyone.
- Built on Godot's high-level multiplayer (ENet). Later the connection layer can be
  swapped for Steam lobbies/invites without rewriting the game code.

Files: scripts/net.gd (host/join/spawning), scripts/player.gd, scripts/can.gd,
scripts/spike_test.gd (automated two-window test).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CONTROLS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WASD move, Shift sprint, Space jump, mouse look, E pick up a can, Right click throw it,
Esc frees the mouse, Alt+F4 (Cmd+Q on Mac) quits.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TESTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Builds are in Pizza Panic/build/net_spike/ (Windows zip, Mac zip).

1. ON ONE PC: run the game twice. Window 1: Host. Window 2: Join with the IP box empty.

2. SAME HOUSE / SAME WIFI: host clicks Host. The friend types the host's local IP
   (on the host PC: Windows key > "cmd" > ipconfig > "IPv4 Address", e.g. 192.168.1.23)
   and clicks Join.

3. OVER THE INTERNET - easiest way: Tailscale (free, no router settings)
   a. Both people install Tailscale (tailscale.com) and sign in.
   b. The host invites the friend to their tailnet (Tailscale admin page > Share/Invite),
      or both sign in to the same account.
   c. Host clicks Host. Friend joins using the host's Tailscale IP (100.x.x.x, shown in the
      Tailscale tray icon).

   Alternative: the host forwards UDP port 7777 on their router to their PC, and the friend
   joins with the host's public IP (google "what is my ip").

The first time the HOST clicks Host, Windows Firewall will ask about network access:
click Allow (tick both Private and Public if offered).

Mac friend: same unsigned-app steps as the main game (System Settings > Privacy & Security
> Open Anyway, or run  xattr -cr "/path/to/Pizza Panic Co-op Test.app"  in Terminal).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT TO LOOK FOR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- Do you see each other move smoothly? Any rubber-banding or teleporting?
- Pick up a can: does the other person see it in your hand, pointing where you look?
- Throw it at each other: does it fly and land in the same place on both screens?
- Try both grabbing the same can at once: only one should get it.
- Quit the game while holding a can: it should drop for the person still playing.

Automated version (for Claude):  run one instance with  -- --test=host --shots=<dir>
and a second with  -- --test=client --shots=<dir>. Both print SHOT lines and save screenshots.

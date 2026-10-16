# Firecracker Alpine Wayland Lab

Two Alpine Linux Firecracker microVMs, each with:

- Sway as the Wayland desktop compositor
- Chromium
- a software-rendered 1280×800 virtual display
- VNC access for keyboard, mouse, and display
- an optional Xvfb compatibility display on `:99`
- a guest-local Tic-Tac-Toe web app served by BusyBox HTTP on port `8080`
- SSH access (available, but not required for desktop use)

Firecracker requires Linux KVM and intentionally has no emulated display or GPU.
On this Apple-silicon Mac, the `lab` launcher creates a small Lima Linux host with
nested virtualization enabled. The desktop itself runs inside each Firecracker
guest; VNC carries that desktop into a normal macOS window.

## Quick start

```bash
make setup
make build
make up
make open-1
```

Open the second desktop with `make open-2`. Stop everything with `make down`.

The first build downloads Firecracker, a Firecracker-compatible guest kernel,
Alpine packages, Chromium, and the Wayland stack. Expect several minutes and
roughly 8 GB of guest-host disk use.

## Commands

```text
./lab setup                create/provision the nested Linux KVM host
./lab build                build two Alpine GUI rootfs images
./lab up                   boot both Firecracker microVMs
./lab open alpine-1        open desktop 1 in macOS Screen Sharing
./lab open alpine-2        open desktop 2 in macOS Screen Sharing
./lab ssh alpine-1         SSH into desktop 1
./lab ssh alpine-2         SSH into desktop 2
./lab logs alpine-1        follow desktop 1 serial log
./lab status               show VM, VNC, and SSH status
./lab update-desktop       install/update Wayland, WayVNC, and Xvfb services
./lab set-mirror           switch both guests to the configured Alpine mirror
./lab novnc                install/start both browser-based VNC gateways
./lab diagnose alpine-1    collect boot, network, proxy, and desktop diagnostics
./lab vnc-test alpine-1    negotiate VNC and report the exported desktop
./lab capture alpine-1     save a PNG of the current VNC framebuffer
./lab open-web alpine-1    open desktop 1 through noVNC in a browser
./lab open-game alpine-1   open VM 1's game directly from macOS
./lab down                 stop the microVMs and remove lab networking
```

The default Alpine package and image mirror is NYCU in Taiwan
(`https://alpine.cs.nycu.edu.tw`). Override it for a future build or mirror
update by setting `ALPINE_MIRROR`.

VNC endpoints are `127.0.0.1:5901` and `127.0.0.1:5902`. SSH endpoints are
`127.0.0.1:2221` and `127.0.0.1:2222`. The VNC listeners exist only inside the
private lab path and are forwarded to localhost on macOS.

Browser viewers are `http://127.0.0.1:6081/vnc.html?autoconnect=true&resize=scale`
and `http://127.0.0.1:6082/vnc.html?autoconnect=true&resize=scale`. The
`./lab novnc` command installs noVNC and Websockify only in the outer Ubuntu
host, then runs one gateway for each guest.

Sway/Wayland remains the interactive desktop shown over VNC. Xvfb runs
independently on display `:99` for legacy X11 tools and browser automation; it
does not require Python or Node.js.

Chromium opens `http://127.0.0.1:8080` inside each guest. The page is a
self-contained Tic-Tac-Toe game: the user plays X and a small in-browser
minimax opponent plays O. Alpine's built-in BusyBox `nc` applet provides the
HTTP listener; the page itself has no external web dependencies.

Lima and the outer-host proxies expose the same guest services directly to
macOS at `http://127.0.0.1:8081/` for `alpine-1` and
`http://127.0.0.1:8082/` for `alpine-2`.

Sway and WayVNC start with debug logging enabled. `./lab diagnose` combines the
Firecracker serial boot log, TAP/proxy state, and the guest desktop logs. The
VNC probe and capture commands use only Python's standard library.

This is an experiment, not a production isolation setup. It deliberately skips
Firecracker's jailer and uses simple TAP/NAT networking.

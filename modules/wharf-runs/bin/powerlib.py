"""powerlib — a process told that the Mac is about to sleep, before it sleeps (dispatch-queue S10(c); the requeue
component's "The sleep hook"). dispatch-rc's watcher loads it, as does the lid-close probe in the component's
evidence folder, so the probe proves the code the watcher runs.

    stop = powerlib.listen(on_will_sleep, say)   # a daemon thread; None where it cannot register

`IORegisterForSystemPower` through ctypes (no pyobjc), its notification port's run-loop source on a run loop of
the listener's own thread. On `kIOMessageCanSystemSleep` (an idle sleep asking) it allows at once: the watcher's
`caffeinate -i` is what holds idle sleep off, never a no here. On `kIOMessageSystemWillSleep` (a lid close, the
menu, an idle sleep allowed) it calls ON_WILL_SLEEP() and then `IOAllowPowerChange`: the sleep waits for that
answer up to 30 s, then goes on anyway (Apple's QA1340: "delayed by 30 seconds", never prevented), so
ON_WILL_SLEEP bounds itself below that. Registration was probed from a plain Python process (the evidence's
iokit_register.py); a delivered message and its acknowledgement are S10(a)'s lid closes, not yet seen.

DISPATCH_POWER_FAKE=<dir> stands in for the OS (the suites): no IOKit; a file `<dir>/willsleep.<n>` is message n,
handled once per listener, and the acknowledgement is a line `<n> <epoch>` in `<dir>/ack.<pid>`. Python 3.9,
stdlib only.
"""
import ctypes
import ctypes.util
import glob
import os
import threading
import time

# IOKit.framework/Headers/IOMessage.h (the evidence's corrected map)
CAN_SLEEP, WILL_SLEEP, WILL_NOT_SLEEP, POWERED_ON = 0xE0000270, 0xE0000280, 0xE0000290, 0xE0000300


def listen(on_will_sleep, say=print):
    """Start the listener thread; a callable that stops it, or None where nothing could register."""
    fake = os.environ.get("DISPATCH_POWER_FAKE")
    if fake:
        return _fake(fake, on_will_sleep, say)
    try:
        return _iokit(on_will_sleep, say)
    except (OSError, AttributeError, ValueError, TypeError) as x:
        say("power: no sleep notice here (%s: %s); a sleep freezes the run as before" % (type(x).__name__, x))
        return None


def _iokit(on_will_sleep, say):
    iokit = ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))
    cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))
    callback_t = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p)
    iokit.IORegisterForSystemPower.restype = ctypes.c_uint32
    iokit.IORegisterForSystemPower.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), callback_t,
                                               ctypes.POINTER(ctypes.c_void_p)]
    iokit.IOAllowPowerChange.restype = ctypes.c_int
    iokit.IOAllowPowerChange.argtypes = [ctypes.c_uint32, ctypes.c_long]
    iokit.IONotificationPortGetRunLoopSource.restype = ctypes.c_void_p
    iokit.IONotificationPortGetRunLoopSource.argtypes = [ctypes.c_void_p]
    cf.CFRunLoopGetCurrent.restype = ctypes.c_void_p
    cf.CFRunLoopAddSource.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    cf.CFRunLoopRunInMode.restype = ctypes.c_int32
    cf.CFRunLoopRunInMode.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_bool]
    mode = ctypes.c_void_p.in_dll(cf, "kCFRunLoopDefaultMode")
    state = {"root": 0, "stop": False}

    def on_power(refcon, service, msg, arg):
        try:
            if msg == WILL_SLEEP:
                t0 = time.time()
                say("power: kIOMessageSystemWillSleep")
                try:
                    on_will_sleep()
                finally:
                    iokit.IOAllowPowerChange(state["root"], arg or 0)
                    say("power: sleep acknowledged after %.1f s" % (time.time() - t0))
            elif msg == CAN_SLEEP:
                iokit.IOAllowPowerChange(state["root"], arg or 0)
            elif msg == POWERED_ON:
                say("power: kIOMessageSystemHasPoweredOn")
        except Exception as x:   # a callback that raises would leave the sleep waiting its 30 s
            say("power: %s: %s" % (type(x).__name__, x))

    cb = callback_t(on_power)   # kept referenced for the thread's life: a collected callback crashes the process
    ready = threading.Event()

    def run():
        port, notifier = ctypes.c_void_p(), ctypes.c_void_p()
        state["root"] = iokit.IORegisterForSystemPower(None, ctypes.byref(port), cb, ctypes.byref(notifier))
        if state["root"]:
            cf.CFRunLoopAddSource(cf.CFRunLoopGetCurrent(), iokit.IONotificationPortGetRunLoopSource(port), mode)
        ready.set()
        while state["root"] and not state["stop"]:
            cf.CFRunLoopRunInMode(mode, 1.0, False)
        cb  # noqa: B018 — the reference above, kept on this frame too

    threading.Thread(target=run, name="power", daemon=True).start()
    ready.wait(5)
    if not state["root"]:
        say("power: IORegisterForSystemPower returned no connection; a sleep freezes the run as before")
        return None
    return lambda: state.update(stop=True)


def _fake(d, on_will_sleep, say):
    state = {"stop": False, "seen": set(glob.glob(os.path.join(d, "willsleep.*")))}

    def run():
        while not state["stop"]:
            for p in sorted(glob.glob(os.path.join(d, "willsleep.*"))):
                if p in state["seen"]:
                    continue
                state["seen"].add(p)
                say("power: kIOMessageSystemWillSleep (stand-in %s)" % os.path.basename(p))
                try:
                    on_will_sleep()
                finally:
                    with open(os.path.join(d, "ack.%d" % os.getpid()), "a") as f:
                        f.write("%s %d\n" % (p.rsplit(".", 1)[-1], time.time()))
            time.sleep(0.2)

    threading.Thread(target=run, name="power", daemon=True).start()
    return lambda: state.update(stop=True)

"""Offer SEVERAL clipboard MIME types in one selection, with nothing but the standard library.

`wl-copy` offers one type per run and no other tool here (no wl-clipboard-rs, no CopyQ) does more, so this speaks the
data-control protocol itself (zwlr_data_control_manager_v1, else ext_data_control_manager_v1; both have the same
opcodes) over the Wayland socket. Data-control needs no keyboard focus, which is why Qt/GTK cannot do this from a
background process.

`python3 wlsel.py` reads {"<mime>": "<base64>"} from stdin, sets the selection, prints "ok" once the compositor has it
and keeps serving the data until another program takes the selection (then exits). Exit status 1 with a message on
stderr when it cannot (no socket, no data-control support).
"""
from __future__ import annotations

import array
import base64
import json
import os
import socket
import struct
import sys

MANAGERS = ("zwlr_data_control_manager_v1", "ext_data_control_manager_v1")
DISPLAY_ID, REGISTRY_ID = 1, 2


class WlError(Exception):
    pass


def _protocol_error(payload: bytes) -> WlError:
    obj, code, ln = struct.unpack_from("<III", payload)
    return WlError(f"compositor protocol error on object {obj}, code {code}: {payload[12:12 + ln - 1].decode(errors='replace')}")


def _s(text: str) -> bytes:
    raw = text.encode() + b"\0"
    return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)


class Conn:
    def __init__(self) -> None:
        name = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
        path = name if name.startswith("/") else os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "", name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            self.sock.connect(path)
        except OSError as e:
            raise WlError(f"cannot connect to {path}: {e}") from e
        self.buf = b""
        self.fds: list = []
        self.next_id = 1  # ids must be allocated one after the other (libwayland refuses gaps)

    def new_id(self) -> int:
        self.next_id += 1
        return self.next_id

    def send(self, obj: int, opcode: int, args: bytes = b"") -> None:
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(args)) << 16) | opcode) + args)

    def events(self):
        """Yield (object, opcode, payload) until the connection closes; received fds land in self.fds."""
        while True:
            while len(self.buf) >= 8:
                obj, word = struct.unpack_from("<II", self.buf)
                size = word >> 16
                if len(self.buf) < size:
                    break
                payload, self.buf = self.buf[8:size], self.buf[size:]
                yield obj, word & 0xFFFF, payload
            fds = array.array("i")
            data, anc, _flags, _addr = self.sock.recvmsg(65536, socket.CMSG_LEN(16 * fds.itemsize))
            for level, typ, cdata in anc:
                if level == socket.SOL_SOCKET and typ == socket.SCM_RIGHTS:
                    fds.frombytes(cdata[:len(cdata) - len(cdata) % fds.itemsize])
            self.fds.extend(fds)
            if not data:
                return
            self.buf += data

    def roundtrip(self, on_event) -> None:
        callback = self.new_id()
        self.send(DISPLAY_ID, 0, struct.pack("<I", callback))  # wl_display.sync
        for obj, op, payload in self.events():
            if obj == callback and op == 0:
                return
            if obj == DISPLAY_ID and op == 0:
                raise _protocol_error(payload)
            on_event(obj, op, payload)
        raise WlError("connection closed")


def serve(offers: dict, announce=None) -> None:
    """Set the selection to `offers` ({mime: bytes}) and serve it until it is replaced. `announce()` runs once the
    compositor has accepted it."""
    c = Conn()
    c.new_id()  # the registry takes id 2
    globals_: dict = {}

    def on_registry(obj, op, payload):
        if obj == REGISTRY_ID and op == 0:
            name, ln = struct.unpack_from("<II", payload)
            iface = payload[8:8 + ln - 1].decode()
            off = 8 + ln + (-ln % 4)
            globals_[iface] = (name, struct.unpack_from("<I", payload, off)[0])

    c.send(DISPLAY_ID, 1, struct.pack("<I", REGISTRY_ID))  # wl_display.get_registry
    c.roundtrip(on_registry)
    mgr_iface = next((m for m in MANAGERS if m in globals_), None)
    if mgr_iface is None or "wl_seat" not in globals_:
        raise WlError("the compositor offers no data-control protocol")

    def bind(iface: str) -> int:
        name = globals_[iface][0]
        oid = c.new_id()
        c.send(REGISTRY_ID, 0, struct.pack("<I", name) + _s(iface) + struct.pack("<II", 1, oid))
        return oid

    mgr, seat = bind(mgr_iface), bind("wl_seat")
    source, device = c.new_id(), c.new_id()
    c.send(mgr, 0, struct.pack("<I", source))                    # create_data_source
    for mime in offers:
        c.send(source, 0, _s(mime))                              # offer
    c.send(mgr, 1, struct.pack("<II", device, seat))             # get_data_device
    c.send(device, 0, struct.pack("<I", source))                 # set_selection
    c.roundtrip(lambda *a: None)
    if announce:
        announce()
    for obj, op, payload in c.events():
        if obj == source and op == 0:                            # send(mime, fd)
            ln = struct.unpack_from("<I", payload)[0]
            mime = payload[4:4 + ln - 1].decode()
            if not c.fds:
                continue
            fd = c.fds.pop(0)
            try:
                with os.fdopen(fd, "wb") as f:
                    f.write(offers.get(mime, b""))
            except OSError:
                pass
        elif obj == source and op == 1:                          # cancelled: somebody else owns the clipboard now
            return
        elif obj == DISPLAY_ID and op == 0:
            raise _protocol_error(payload)


def main() -> int:
    try:
        raw = json.load(sys.stdin)
        offers = {m: base64.b64decode(b) for m, b in raw.items()}
        if not offers:
            raise WlError("nothing to offer")

        def announce():
            sys.stdout.write("ok\n")
            sys.stdout.flush()
            sys.stdout.close()  # the parent stops waiting; serving goes on
            sys.stdin.close()

        serve(offers, announce)
    except (WlError, OSError, ValueError) as e:
        print(f"wlsel: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

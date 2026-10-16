"""Usage: ensure-proxy UNIT DESCRIPTION SOCKET COMMAND...

Make sure the transient user units UNIT.socket and UNIT.service run COMMAND
behind SOCKET. Units with another DESCRIPTION, from an older build, are
replaced. Returns once systemd is listening.
"""

import sys
from collections import deque

from jeepney import DBusAddress, MatchRule, Properties, message_bus, new_method_call
from jeepney.io.blocking import open_dbus_connection
from jeepney.wrappers import DBusErrorResponse, unwrap_msg

MANAGER = DBusAddress(
    "/org/freedesktop/systemd1",
    bus_name="org.freedesktop.systemd1",
    interface="org.freedesktop.systemd1.Manager",
)
JOB_REMOVED = MatchRule(
    type="signal",
    path=MANAGER.object_path,
    interface=MANAGER.interface,
    member="JobRemoved",
)


def call(conn, signature, method, *args):
    message = new_method_call(MANAGER, method, signature, args)
    return unwrap_msg(conn.send_and_get_reply(message))


def description(conn, unit):
    try:
        (path,) = call(conn, "s", "GetUnit", unit)
    except DBusErrorResponse:
        return None
    obj = DBusAddress(path, MANAGER.bus_name, "org.freedesktop.systemd1.Unit")
    ((_, value),) = unwrap_msg(conn.send_and_get_reply(Properties(obj).get("Description")))
    return value


def run_job(conn, jobs, signature, method, *args):
    (job,) = call(conn, signature, method, *args)
    while True:
        _, path, unit, result = conn.recv_until_filtered(jobs).body
        if path == job:
            return unit, result


def main():
    unit, desc, socket_path, *command = sys.argv[1:]
    socket_unit, service_unit = f"{unit}.socket", f"{unit}.service"

    with open_dbus_connection("SESSION") as conn:
        if description(conn, socket_unit) == desc:
            return

        call(conn, None, "Subscribe")
        unwrap_msg(conn.send_and_get_reply(message_bus.AddMatch(JOB_REMOVED)))
        with conn.filter(JOB_REMOVED, queue=deque()) as jobs:
            for old in (socket_unit, service_unit):
                try:
                    run_job(conn, jobs, "ss", "StopUnit", old, "replace")
                except DBusErrorResponse:
                    pass

            common = [
                ("Description", ("s", desc)),
                ("CollectMode", ("s", "inactive-or-failed")),
            ]
            socket = common + [("Listen", ("a(ss)", [("Stream", socket_path)]))]
            service = common + [("ExecStart", ("a(sasb)", [(command[0], command, False)]))]
            try:
                unit, result = run_job(
                    conn, jobs, "ssa(sv)a(sa(sv))", "StartTransientUnit",
                    socket_unit, "fail", socket, [(service_unit, service)],
                )
            except DBusErrorResponse as e:
                if e.name != "org.freedesktop.systemd1.UnitExists":
                    raise
                # another sandbox created it first
                unit, result = run_job(conn, jobs, "ss", "StartUnit", socket_unit, "replace")

    if result != "done":
        sys.exit(f"ensure-proxy: starting {unit}: {result}")


if __name__ == "__main__":
    main()

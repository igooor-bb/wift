#!/usr/bin/env wift

import Wift

guard let swiftc = which("swiftc") else {
    die("swiftc is not available on PATH")
}

eprint("Script directory: \(Script.directory.path)")
try checkRun(swiftc.path, "--version")

let system = try capture("/usr/bin/uname", "-sm")
guard system.status == 0 else {
    throw CommandFailure(
        executable: "/usr/bin/uname",
        arguments: ["-sm"],
        status: system.status
    )
}

print("System: \(system.stdout)", terminator: "")

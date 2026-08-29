#!/usr/bin/env wift

import Wift

eprint("Script directory: \(Script.directory.path)")

try cmd("swiftc", "--version").run()

let system = try cmd("/usr/bin/uname", "-sm").text()
print("System: \(system)")

let sorted = try cmd("/usr/bin/printf", "beta\nalpha\n")
    .pipe(to: cmd("/usr/bin/sort"))
    .lines()
print("Sorted: \(sorted.joined(separator: ", "))")

let value = "; remains one argument"
try print(shell("printf '%s\n' \(value)").text())

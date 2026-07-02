local process = require("@lune/process")
local frktest = require("@packages/frktest")

require("@tests/Buffer.spec")()

local lune_console_reporter = (frktest :: any)._reporters.lune_console_reporter
lune_console_reporter.init()

local success = frktest.run()
process.exit(if success then 0 else 1)

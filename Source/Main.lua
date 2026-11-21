local QCBE = require("Source.QCBE")

local State = QCBE.new()

local FileName = nil
for ArgumentIndex, Argument in ipairs(arg) do
  if Argument == "-sHiddenDevMode" then
    QCBE._DevMode = true
  else
    FileName = Argument
  end
end

if FileName == nil then
  return
end

local Result, Error = QCBE:Compile(State, FileName, FileName .. ".sh", "Executable")

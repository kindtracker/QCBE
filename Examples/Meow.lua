local meow = ptr("meow")

function main.export.arg.i32.ptr:i32(argc, argv)
  call.puts(ptr(meow))
  return i32(0)
end

local FFI = require("ffi")

local QCBE = {}
local State = nil
local Logger = {}
local Tokenizer = {}
local Parser = {}
local BytecodeGenerator = {}

local BaseIdent = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
local BasePunct = "(){}:,."
local BaseDigits = "0123456789"
local BaseOperators = "=<>~&|+-*/^%"
local BaseWhiteSpace = "\n\t\r "

local BaseKeywords = {
  "function",
  "return",
  "end",
  "global",
  "local",
  "true",
  "false",
  "null",
}

local BaseEscapes = {
  ["n"] = "\n",
  ["t"] = "\t",
  ["r"] = "\r",
  ["\\"] = "\\",
  ['"'] = '"',
  ["'"] = "'",
  ["0"] = "\0",
}

local OpcodeTable = {
  call = 0, -- Implemented
  push = 1, -- Implemented
  load = 2, -- Not implemented
  store = 3, -- Not implemented
  add = 4, -- Not implemented
  sub = 5, -- Not implemented
  mul = 6, -- Not implemented
  div = 7, -- Not implemented
  mod = 8, -- Not implemented
  cmp = 10, -- Not implemented
  jmp = 11, -- Not implemented
  jmpn = 13, -- Not implemented
}

local TypeTable = {
  void = 0,
  ptr = 1,
  i8 = 2,
  i16 = 3,
  i32 = 4,
  i64 = 5,
  u8 = 6,
  u16 = 7,
  u32 = 8,
  u64 = 9,
  f32 = 10,
  f64 = 11,
}

local function TableHasString(Table, Value)
  for _, Item in pairs(Table) do
    if type(Item) == "string" and Item == Value then
      return true
    end
  end

  return false
end

local function StringHasLetter(String, Letter)
  return Letter ~= "" and string.find(String, Letter, 1, true) ~= nil
end

function Logger:Error(...)
  io.stdout:flush()
  io.stderr:write("\27[1;37mQCBE:\27[0m ")
  io.stderr:write("\27[1;31mError:\27[0m ")
  io.stderr:write(string.format(...))
  io.stderr:write("\n")
  os.exit(1)
end

function Logger:PrintTable(Table, Indent, Seen)
  Indent = Indent or 0
  Seen = Seen or {}

  if type(Table) ~= "table" then
    print(string.rep("  ", Indent) .. tostring(Table))
    return
  end

  if Seen[Table] then
    print(string.rep("  ", Indent) .. "<circular reference>")
    return
  end

  Seen[Table] = true

  local Prefix = string.rep("  ", Indent)

  print(Prefix .. "{")

  for Key, Value in pairs(Table) do
    io.write(Prefix .. "  [" .. string.format("%q", Key) .. "] = ")

    if type(Value) == "table" then
      print()
      Logger:PrintTable(Value, Indent + 1, Seen)
    else
      print(string.format("%q", Value) .. ",")
    end
  end

  print(Prefix .. "}")

  Seen[Table] = nil
end

function Tokenizer:Advance(Step)
  if Step == 0 then
    Tokenizer.Character = State.File.Content:sub(Tokenizer.Index, Tokenizer.Index)
    return
  end

  local Direction = Step > 0 and 1 or -1

  for _ = 1, math.abs(Step) do
    if Direction > 0 then
      if Tokenizer.Character == "\n" then
        Tokenizer.Row = Tokenizer.Row + 1
        Tokenizer.Column = 1
      else
        Tokenizer.Column = Tokenizer.Column + 1
      end
    else
      local PreviousCharacter = State.File.Content:sub(Tokenizer.Index - 1, Tokenizer.Index - 1)

      if PreviousCharacter == "\n" then
        Tokenizer.Row = Tokenizer.Row - 1
        Tokenizer.Column = 1
      else
        Tokenizer.Column = Tokenizer.Column - 1
      end
    end

    Tokenizer.Index = Tokenizer.Index + Direction
    Tokenizer.Character = State.File.Content:sub(Tokenizer.Index, Tokenizer.Index)
  end
end

function Tokenizer:NewToken(Kind, Value)
  local Token = {
    Kind = Kind,
    Value = Value,
    Column = Tokenizer.Column,
    Row = Tokenizer.Row,
  }
  table.insert(State.Tokens, Token)
end

function Tokenizer:Tokenize()
  State.Tokens = {}
  Tokenizer.Column = 1
  Tokenizer.Row = 1
  Tokenizer.Index = 1
  Tokenizer.Character = ""

  Tokenizer:Advance(0)
  while #Tokenizer.Character > 0 do
    if StringHasLetter(BaseWhiteSpace, Tokenizer.Character) then
      Tokenizer:Advance(1)
    elseif StringHasLetter(BaseIdent, Tokenizer.Character) then
      local StartIndex = Tokenizer.Index
      while StringHasLetter(BaseIdent .. BaseDigits, Tokenizer.Character) do
        Tokenizer:Advance(1)
      end
      local EndIndex = Tokenizer.Index - 1

      local Ident = State.File.Content:sub(StartIndex, EndIndex)
      local Keyword = TableHasString(BaseKeywords, Ident)
      Tokenizer:NewToken(Keyword and "Keyword" or "Ident", Ident)
    elseif StringHasLetter(BasePunct, Tokenizer.Character) then
      Tokenizer:NewToken("Punct", Tokenizer.Character)
      Tokenizer:Advance(1)
    elseif StringHasLetter(BaseOperators, Tokenizer.Character) then
      if Tokenizer.Character == "-" then
        Tokenizer:Advance(1)

        if Tokenizer.Character == "-" then
          while Tokenizer.Character ~= "\n" and Tokenizer.Character ~= "" do
            Tokenizer:Advance(1)
          end
          goto continue
        end

        Tokenizer:NewToken("Operator", "-")
      else
        Tokenizer:NewToken("Operator", Tokenizer.Character)
      end
      Tokenizer:Advance(1)
    elseif Tokenizer.Character == '"' or Tokenizer.Character == "'" then
      local Quote = Tokenizer.Character
      Tokenizer:Advance(1)
      local StartIndex = Tokenizer.Index

      while Tokenizer.Character ~= Quote do
        Tokenizer:Advance(1)
      end
      local EndIndex = Tokenizer.Index - 1
      Tokenizer:Advance(1)

      local String = State.File.Content:sub(StartIndex, EndIndex)
      Tokenizer:NewToken("String", String)
    elseif StringHasLetter(BaseDigits, Tokenizer.Character) then
      local StartIndex = Tokenizer.Index

      while StringHasLetter(BaseDigits, Tokenizer.Character) do
        Tokenizer:Advance(1)
      end
      local EndIndex = Tokenizer.Index - 1

      local NumberString = State.File.Content:sub(StartIndex, EndIndex)
      local Number = tonumber(NumberString)
      if Number == nil then
        Logger:Error("Failed to convert string to number: %s", NumberString)
      end

      Tokenizer:NewToken("Number", Number)
    else
      Logger:Error("Unexpected character: %s", Tokenizer.Character)
    end
    ::continue::
  end
end

function Parser:Advance(Step)
  Parser.Index = Parser.Index + Step
  Parser.Token = State.Tokens[Parser.Index]
end

function Parser:CheckToken(Offset, Kind, Value)
  local Token = State.Tokens[Parser.Index + Offset]

  if not Token or Token.Kind ~= Kind then
    return false
  end

  if Value ~= nil and Token.Value ~= Value then
    return false
  end

  return true
end

function Parser:Expect(Offset, Kind, Value)
  if not Parser:CheckToken(Offset, Kind, Value) then
    local Token = State.Tokens[Parser.Index + Offset]
    if not Token then
      Logger:Error("Unexpected end of file")
    end

    Logger:Error("Unexpected token %q", Token.Value)
  end

  return State.Tokens[Parser.Index + Offset]
end

function Parser:ParseBody()
  local Body = {}

  while not Parser:CheckToken(0, "Keyword", "end") do
    local PreviousIndex = Parser.Index
    local StatementName = Parser.Token.Value
    local Statement = Parser:ParseStatement()

    if not Statement then
      Logger:Error("Unexpected token: %q", StatementName)
    end

    if Parser.Index == PreviousIndex then
      Logger:Error("Parser made no progress")
    end

    table.insert(Body, Statement)
  end

  return Body
end

function Parser:ParseFunction()
  local Function = {
    Kind = "Function",
    Name = "",
    Attributes = {},
    Arguments = {},
    ReturnType = "",
    Body = {},
  }

  Parser:Advance(1)

  Parser:Expect(0, "Ident")
  Function.Name = Parser.Token.Value
  Parser:Advance(1)

  local ArgMode = false
  local ArgumentTypes = {}

  while Parser:CheckToken(0, "Punct", ".") do
    Parser:Advance(1)
    Parser:Expect(0, "Ident")

    local Attribute = Parser.Token.Value
    if Attribute == "arg" then
      ArgMode = not ArgMode
    elseif ArgMode then
      table.insert(ArgumentTypes, Attribute)
    else
      table.insert(Function.Attributes, Attribute)
    end

    Parser:Advance(1)
  end

  Parser:Expect(0, "Punct", ":")
  Parser:Advance(1)

  Parser:Expect(0, "Ident")
  Function.ReturnType = Parser.Token.Value
  Parser:Advance(1)

  Parser:Expect(0, "Punct", "(")
  Parser:Advance(1)

  local Idx = 1
  while not Parser:CheckToken(0, "Punct", ")") do
    Parser:Expect(0, "Ident")

    local ArgumentType = ArgumentTypes[Idx]
    local ArgumentName = Parser.Token.Value
    Function.Arguments[Idx] = { Name = ArgumentName, Type = ArgumentType }

    Parser:Advance(1)
    Idx = Idx + 1

    if Parser:CheckToken(0, "Punct", ",") then
      Parser:Advance(1)
    elseif not Parser:CheckToken(0, "Punct", ")") then
      Logger:Error("Expected ',' or ')'")
    end
  end

  Parser:Expect(0, "Punct", ")")
  Parser:Advance(1)

  local Body = Parser:ParseBody()
  Function.Body = Body
  Parser:Advance(1)

  return Function
end

function Parser:ParseOperation()
  local Operation = {
    Kind = "Operation",
    Opcode = "",
    Target = "",
    Arguments = {},
  }

  Operation.Opcode = Parser.Token.Value

  if Parser:CheckToken(1, "Punct", ".") then
    Parser:Advance(2)

    Parser:Expect(0, "Ident")
    Operation.Target = Parser.Token.Value
    Parser:Advance(1)
  else
    Operation.Opcode = nil
    Operation.Target = nil
    Operation.Type = Parser.Token.Value
    Operation.Kind = "Type"
    Parser:Advance(1)
  end

  Parser:Expect(0, "Punct", "(")
  Parser:Advance(1)

  while not Parser:CheckToken(0, "Punct", ")") do
    local Argument

    if Parser:CheckToken(0, "Ident") then
      Argument = Parser:ParseOperation()
    elseif Parser:CheckToken(0, "String") then
      Argument = {
        Kind = "String",
        Value = Parser.Token.Value,
      }
      Parser:Advance(1)
    elseif Parser:CheckToken(0, "Number") then
      Argument = {
        Kind = "Number",
        Value = Parser.Token.Value,
      }
      Parser:Advance(1)
    else
      Logger:Error("Unexpected token in operation argument: %s", tostring(Parser.Token.Value))
    end

    table.insert(Operation.Arguments, Argument)

    if Parser:CheckToken(0, "Punct", ",") then
      Parser:Advance(1)
    elseif not Parser:CheckToken(0, "Punct", ")") then
      Logger:Error("Expected ',' or ')'")
    end
  end

  if Operation.Type then
    Operation.Value = Operation.Arguments[1]
    Operation.Arguments = nil
  end

  Parser:Expect(0, "Punct", ")")
  Parser:Advance(1)

  return Operation
end

function Parser:ParseReturn()
  local Return = {
    Kind = "Return",
    Type = "",
    Value = {},
  }

  Parser:Advance(1)

  Parser:Expect(0, "Ident")
  Return.Type = Parser.Token.Value
  Parser:Advance(1)

  Parser:Expect(0, "Punct", "(")
  Parser:Advance(1)

  if not Parser:CheckToken(0, "Punct", ")") then
    if Parser:CheckToken(0, "Ident") then
      Return.Value = Parser:ParseOperation()
    elseif Parser:CheckToken(0, "Number") then
      Return.Value = {
        Kind = "Number",
        Value = Parser.Token.Value,
      }
      Parser:Advance(1)
    elseif Parser:CheckToken(0, "String") then
      Return.Value = {
        Kind = "String",
        Value = Parser.Token.Value,
      }
      Parser:Advance(1)
    end
  end

  Parser:Expect(0, "Punct", ")")
  Parser:Advance(1)

  return Return
end

function Parser:ParseStatement()
  if Parser:CheckToken(0, "Keyword", "function") then
    return Parser:ParseFunction()
  elseif Parser:CheckToken(0, "Keyword", "return") then
    return Parser:ParseReturn()
  elseif Parser:CheckToken(0, "Ident") then
    return Parser:ParseOperation()
  end
end

function Parser:Parse()
  State.Ast = {}
  Parser.Token = {}
  Parser.Index = 1

  Parser:Advance(0)
  while Parser.Token do
    local PreviousIndex = Parser.Index
    local Statement = Parser:ParseStatement()

    if not Statement then
      Logger:Error("Unexpected token: %s", tostring(Parser.Token.Value))
    end

    if Parser.Index == PreviousIndex then
      Logger:Error("Parser made no progress")
    end

    table.insert(State.Ast, Statement)
  end
end

function BytecodeGenerator:Write8(Value)
  State.Bytecode = State.Bytecode .. string.char(Value % 256)
  BytecodeGenerator.Pc = BytecodeGenerator.Pc + 1
end

function BytecodeGenerator:Write16(Value)
  BytecodeGenerator:Write8(Value)
  BytecodeGenerator:Write8(math.floor(Value / 256))
end

function BytecodeGenerator:Write32(Value)
  BytecodeGenerator:Write16(Value)
  BytecodeGenerator:Write16(math.floor(Value / 65536))
end

function BytecodeGenerator:Write64(Value)
  BytecodeGenerator:Write32(Value)
  BytecodeGenerator:Write32(math.floor(Value / 4294967296))
end

function BytecodeGenerator:WriteFloat(Value)
  local Data = FFI.new("float[1]", Value)
  local Bytes = FFI.string(Data, 4)

  State.Bytecode = State.Bytecode .. Bytes
  BytecodeGenerator.Pc = BytecodeGenerator.Pc + 4
end

function BytecodeGenerator:WriteDouble(Value)
  local Data = FFI.new("double[1]", Value)
  local Bytes = FFI.string(Data, 8)

  State.Bytecode = State.Bytecode .. Bytes
  BytecodeGenerator.Pc = BytecodeGenerator.Pc + 8
end

function BytecodeGenerator:WriteString(String)
  BytecodeGenerator:Write32(#String)
  State.Bytecode = State.Bytecode .. String
  BytecodeGenerator.Pc = BytecodeGenerator.Pc + #String
end

function BytecodeGenerator:AddConstant(Value)
  local Index = BytecodeGenerator.ConstantLookup[Value]
  if Index ~= nil then
    return Index
  end

  Index = #BytecodeGenerator.Constants
  table.insert(BytecodeGenerator.Constants, Value)
  BytecodeGenerator.ConstantLookup[Value] = Index

  return Index
end

function BytecodeGenerator:WriteTypedValue(Type, Value)
  BytecodeGenerator:Write8(TypeTable[Type])

  if Type == "ptr" then
    BytecodeGenerator:Write32(BytecodeGenerator:AddConstant(Value.Value))
  elseif Type == "i8" or Type == "u8" then
    BytecodeGenerator:Write8(Value.Value)
  elseif Type == "i16" or Type == "u16" then
    BytecodeGenerator:Write16(Value.Value)
  elseif Type == "i32" or Type == "u32" then
    BytecodeGenerator:Write32(Value.Value)
  elseif Type == "i64" or Type == "u64" then
    BytecodeGenerator:Write64(Value.Value)
  elseif Type == "f32" then
    BytecodeGenerator:WriteFloat(Value.Value)
  elseif Type == "f64" then
    BytecodeGenerator:WriteDouble(Value.Value)
  end
end

function BytecodeGenerator:EmitFunction(Ast)
  local Export = TableHasString(Ast.Attributes, "Export")

  local Symbol = {
    Name = Ast.Name,
    NameIndex = BytecodeGenerator:AddConstant(Ast.Name),
    Export = Export,
    Offset = BytecodeGenerator.Pc,
    Size = 0,
    Arguments = Ast.Arguments,
    ReturnType = Ast.ReturnType,
  }

  BytecodeGenerator.SymbolTable[Ast.Name] = Symbol
  table.insert(BytecodeGenerator.Symbols, Symbol)

  for _, ChildAst in ipairs(Ast.Body) do
    BytecodeGenerator:Emit(ChildAst)
  end

  if #Ast.Body == 0 or Ast.Body[#Ast.Body].Kind ~= "Return" then
    BytecodeGenerator:EmitReturn({
      Type = "void",
      Value = {},
    })
  end

  Symbol.Size = BytecodeGenerator.Pc - Symbol.Offset
end

function BytecodeGenerator:EmitOperation(Ast)
  BytecodeGenerator:Write8(OpcodeTable[Ast.Opcode])
  BytecodeGenerator:Write32(BytecodeGenerator:AddConstant(Ast.Target))
  BytecodeGenerator:Write16(#Ast.Arguments)

  for _, Argument in ipairs(Ast.Arguments) do
    BytecodeGenerator:WriteTypedValue(Argument.Type, Argument.Value)
  end
end

function BytecodeGenerator:EmitReturn(Ast)
  BytecodeGenerator:Write8(OpcodeTable.push)
  BytecodeGenerator:WriteTypedValue(Ast.Type, Ast.Value)
end

function BytecodeGenerator:Emit(Ast)
  if Ast.Kind == "Function" then
    BytecodeGenerator:EmitFunction(Ast)
  elseif Ast.Kind == "Operation" then
    BytecodeGenerator:EmitOperation(Ast)
  elseif Ast.Kind == "Return" then
    BytecodeGenerator:EmitReturn(Ast)
  end
end

function BytecodeGenerator:EmitAst()
  State.Bytecode = ""
  BytecodeGenerator.Pc = 0

  BytecodeGenerator.Constants = {}
  BytecodeGenerator.ConstantLookup = {}
  BytecodeGenerator.Symbols = {}
  BytecodeGenerator.SymbolTable = {}

  for _, Ast in ipairs(State.Ast) do
    BytecodeGenerator:Emit(Ast)
  end
end

function BytecodeGenerator:BuildFile()
  local Code = State.Bytecode

  State.Bytecode = ""
  BytecodeGenerator.Pc = 0
  BytecodeGenerator.WriteBytes = nil

  BytecodeGenerator:Write8(string.byte("Q"))
  BytecodeGenerator:Write8(string.byte("C"))
  BytecodeGenerator:Write8(string.byte("B"))
  BytecodeGenerator:Write8(string.byte("E"))

  BytecodeGenerator:Write32(#Code)
  BytecodeGenerator:Write32(#BytecodeGenerator.Symbols)
  BytecodeGenerator:Write32(#BytecodeGenerator.Constants)

  State.Bytecode = State.Bytecode .. Code

  for _, Symbol in ipairs(BytecodeGenerator.Symbols) do
    BytecodeGenerator:Write32(Symbol.NameIndex)
    BytecodeGenerator:Write8(Symbol.Export and 1 or 0)
    BytecodeGenerator:Write32(Symbol.Offset)
    BytecodeGenerator:Write32(Symbol.Size)
    BytecodeGenerator:Write16(#Symbol.Arguments)
    BytecodeGenerator:Write8(TypeTable[Symbol.ReturnType])

    for _, Argument in ipairs(Symbol.Arguments) do
      BytecodeGenerator:Write8(TypeTable[Argument.Type])
    end
  end

  for _, Constant in ipairs(BytecodeGenerator.Constants) do
    BytecodeGenerator:WriteString(Constant)
  end

  return State.Bytecode
end

function QCBE.new()
  return {
    File = {
      Content = 0,
      Name = "",
    },
  }
end

function QCBE:Compile(_State, FileName, OutputFile, Type)
  State = _State

  State.File.Name = FileName

  local FilePtr = io.open(FileName, "r")
  State.File.Content = FilePtr:read("*a")
  FilePtr:close()

  Tokenizer:Tokenize()
  if QCBE.HiddenDevMode then
    Logger:PrintTable(State.Tokens)
  end

  Parser:Parse()
  if QCBE.HiddenDevMode then
    Logger:PrintTable(State.Ast)
  end

  BytecodeGenerator:EmitAst()
  if QCBE.HiddenDevMode then
    local BytecodeFile = io.open(OutputFile:gsub("%..*$", "") .. ".qcbe", "wb")
    BytecodeFile:write(BytecodeGenerator.BuildFile())
    BytecodeFile:close()
  end
end

return QCBE

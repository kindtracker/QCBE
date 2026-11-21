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
  self:Write8(Value % 256)
  self:Write8(math.floor(Value / 256))
end

function BytecodeGenerator:Write32(Value)
  self:Write16(Value % 65536)
  self:Write16(math.floor(Value / 65536))
end

function BytecodeGenerator:Write64(Value)
  self:Write32(Value % 4294967296)
  self:Write32(math.floor(Value / 4294967296))
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
  for Character in String:gmatch(".") do
    local Number = string.byte(Character)
    BytecodeGenerator:Write8(Number)
  end
end

function BytecodeGenerator:EmitFunction(Ast)
  local Export = false
  for _, Attribute in ipairs(Ast.Attributes) do
    if Attribute == "Export" then
      Export = true
    end
  end

  BytecodeGenerator.SymbolTable[Ast.Name] = {
    Kind = "Function",
    Name = Ast.Name,
    Export = Export,
  }

  for _, ChildAst in ipairs(Ast.Body) do
    BytecodeGenerator:Emit(ChildAst)
  end
end

function BytecodeGenerator:EmitOperation(Ast)
  local OpcodeTable = {
    call = 0,
  }

  local WriteTable = {
    ptr = BytecodeGenerator.Write64,
    i8 = BytecodeGenerator.Write8,
    i16 = BytecodeGenerator.Write16,
    i32 = BytecodeGenerator.Write32,
    i64 = BytecodeGenerator.Write64,
    u8 = BytecodeGenerator.Write8,
    u16 = BytecodeGenerator.Write16,
    u32 = BytecodeGenerator.Write32,
    u64 = BytecodeGenerator.Write64,
  }

  local OpcodeNumber = OpcodeTable[Ast.Opcode]
  BytecodeGenerator:Write8(OpcodeNumber)
  BytecodeGenerator:WriteString(Ast.Target)

  for _, Argument in ipairs(Ast.Arguments) do
    local WriteFunction = WriteTable[Argument.Type]

    if Argument.Type == "ptr" then
      BytecodeGenerator:Write64(0) -- TODO: Add constant pools
    else
      WriteFunction(BytecodeGenerator, Argument.Value)
    end
  end
end

function BytecodeGenerator:Emit(Ast)
  print(Ast.Kind)
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
  BytecodeGenerator.SymbolTable = {}
  BytecodeGenerator.Pc = 0

  for _, Ast in ipairs(State.Ast) do
    BytecodeGenerator:Emit(Ast)
  end
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
  if QCBE._DevMode then
    Logger:PrintTable(State.Tokens)
  end

  Parser:Parse()
  if QCBE._DevMode then
    Logger:PrintTable(State.Ast)
  end

  BytecodeGenerator:EmitAst()
  if QCBE._DevMode then
    local BytecodeFile = io.open(OutputFile:gsub("%..*$", "") .. ".qcbe", "wb")
    BytecodeFile:write(State.Bytecode)
    BytecodeFile:close()
  end
end

return QCBE

local QCBE = {}
local State = nil
local Logger = {}
local Tokenizer = {}
local Parser = {}

local BaseIdent = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
local BasePunct = "(){};,."
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

function Parser:Parse() end

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
  Logger:PrintTable(State.Tokens)

  Parser:Parse()
end

return QCBE

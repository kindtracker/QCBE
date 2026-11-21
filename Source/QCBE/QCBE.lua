local QCBE = {}
local State = nil
local Logger = {}
local Tokenizer = {}
local Parser = {}

local BaseIdent = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
local BasePunct = "(){}[];,:."
local BaseDigits = "0123456789"
local BaseOperators = "=<>~&|+-*/^%#"
local BaseWhiteSpace = "\n\t\r "

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
	io.stderr:write("\27[1;37mCrosh:\27[0m ")
	io.stderr:write("\27[1;31mError:\27[0m ")
	io.stderr:write(string.format(...))
	io.stderr:write("\n")
	os.exit(1)
end

function Tokenizer:Advance(Step)
	local Direction = Step > 0 and 1 or -1

	for _ = 1, math.abs(Step) do
		Tokenizer.Index = Tokenizer.Index + Direction
		Tokenizer.Character = State.File.Content:sub(Tokenizer.Index, Tokenizer.Index)
	end

	Tokenizer.Character = State.File.Content:sub(Tokenizer.Index, Tokenizer.Index)
end

function Tokenizer:NewToken(Kind, Value)
	local Token = {
		Kind = Kind,
		Value = Value,
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
			while StringHasLetter(BaseIdent, Tokenizer.Character) do
				Tokenizer:Advance(1)
			end
			local EndIndex = Tokenizer.Index - 1

			local Ident = State.File.Content:sub(StartIndex, EndIndex)
			Tokenizer:NewToken("Ident", Ident)
		end
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
	Parser:Parse()
end

return QCBE

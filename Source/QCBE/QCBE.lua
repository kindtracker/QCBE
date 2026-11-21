local QCBE = {}
local State = nil
local Tokenizer = {}
local Parser = {}

function QCBE.new()
	return {
		File = {
			Content = 0,
			Name = "",
		},
	}
end

function Tokenizer:Advance(Step)
	local Direction = Step > 0 and 1 or -1

	for _ = 1, math.abs(Step) do
		Tokenizer.Index = Tokenizer.Index + Direction
		Tokenizer.Character = State.File.Content:sub(Tokenizer.Index, Tokenizer.Index)
		print(Tokenizer.Charactera)
	end

	Tokenizer.Character = State.File.Content:sub(Tokenizer.Index, Tokenizer.Index)
end

function Tokenizer:Tokenize()
	Tokenizer.Column = 1
	Tokenizer.Row = 1
	Tokenizer.Index = 1
	Tokenizer.Character = ""

	Tokenizer:Advance(0)
	print(Tokenizer.Character)
end

function Parser:Parse() end

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

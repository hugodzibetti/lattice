--!strict

local Types = require("@src/artifacts/types")

type ClassDef = Types.ClassDef
type PropertyDef = Types.PropertyDef

-- Input: decoded JSON table from Roblox API dump
-- Output: { ClassDef }

local function parse(raw: any): { ClassDef }
	local rawClasses = raw.Classes
	if type(rawClasses) ~= "table" then
		return {}
	end

	-- Build a map of className -> rawClass for superclass resolution
	local classMap: { [string]: any } = {}
	for _, rawClass in rawClasses do
		if type(rawClass) == "table" and type(rawClass.Name) == "string" then
			classMap[rawClass.Name] = rawClass
		end
	end

	-- Returns alphabetically sorted PropertyDef for a raw class, including inherited.
	-- ancestorFirst=true means superclass properties come before own properties.
	local function collectProperties(rawClass: any): { PropertyDef }
		local ownProps: { PropertyDef } = {}
		local superName = rawClass.Superclass
		local inherited: { PropertyDef }
		if type(superName) == "string" and classMap[superName] then
			inherited = collectProperties(classMap[superName])
		else
			inherited = {}
		end

		local members = rawClass.Members
		if type(members) ~= "table" then
			return inherited
		end

		for _, member in members do
			if type(member) ~= "table" then
				continue
			end
			if member.MemberType ~= "Property" then
				continue
			end

			-- Skip notScriptable, hidden, deprecated, readOnly
			local tags = member.Tags
			if type(tags) == "table" then
				local skip = false
				for _, tag in tags do
					if tag == "notScriptable" or tag == "hidden" or tag == "deprecated" or tag == "readOnly" then
						skip = true
						break
					end
				end
				if skip then
					continue
				end
			end

			-- Only CanSave == true (or absent, or is "Parent", "Size", "Position")
			local serialization = member.Serialization
			if type(serialization) == "table" and serialization.CanSave == false 
				and member.Name ~= "Parent" 
				and member.Name ~= "Size" 
				and member.Name ~= "Position" then
				continue
			end

			-- Get value type info
			local valueTypeRaw = member.ValueType
			if type(valueTypeRaw) ~= "table" then
				continue
			end
			local valueTypeName = valueTypeRaw.Name
			if type(valueTypeName) ~= "string" then
				continue
			end

			-- Skip BinaryString
			if valueTypeName == "BinaryString" then
				continue
			end

			-- Build valueTypeParams from ValueType's extra info
			local valueTypeParams: { string }? = nil
			if valueTypeRaw.Category == "Enum" then
				valueTypeParams = { valueTypeRaw.Name }
				valueTypeName = "Enum"
			elseif valueTypeName == "Array" or valueTypeName == "Optional" then
				local inner = valueTypeRaw.InnerType
				if type(inner) == "table" and type(inner.Name) == "string" then
					valueTypeParams = { inner.Name }
				end
			end

			local hasDefault = type(member.Default) == "string"
			local defaultRaw: string? = if hasDefault then member.Default else nil

			table.insert(ownProps, {
				name = member.Name :: string,
				valueType = valueTypeName,
				valueTypeParams = valueTypeParams,
				hasDefault = hasDefault,
				defaultRaw = defaultRaw,
			})
		end

		-- Sort own properties alphabetically by name
		table.sort(ownProps, function(a: PropertyDef, b: PropertyDef): boolean
			return a.name < b.name
		end)

		-- Merge: inherited first, then own, ensuring subclass wins on override
		local result: { PropertyDef } = {}
		local seen: {[string]: boolean} = {}
		for _, p in ownProps do
			seen[p.name] = true
		end
		for _, p in inherited do
			if not seen[p.name] then
				table.insert(result, p)
				seen[p.name] = true
			end
		end
		for _, p in ownProps do
			table.insert(result, p)
		end
		return result
	end

	-- Build ClassDef for each class
	local result: { ClassDef } = {}
	for _, rawClass in rawClasses do
		if type(rawClass) ~= "table" or type(rawClass.Name) ~= "string" then
			continue
		end
		local props = collectProperties(rawClass)
		if #props > 0 then
			table.insert(result, {
				name = rawClass.Name,
				superclass = if type(rawClass.Superclass) == "string" then rawClass.Superclass else nil,
				properties = props,
			})
		end
	end

	return result
end

return parse

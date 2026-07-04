--!strict

export type PropertyMetadata = {
	name: string,
	codecId: number,
	codecParams: { number }?,
	default: any?,
	codec: any?,
}

export type ClassMetadata = {
	id: number,
	name: string,
	properties: { PropertyMetadata },
}

export type ArtifactData = {
	version: number,
	classes: { ClassMetadata },
	classByName: { [string]: ClassMetadata },
	classById: { [number]: ClassMetadata },
}

export type PropertyDef = {
	name: string,
	valueType: string,
	valueTypeParams: { string }?,
	hasDefault: boolean,
	defaultRaw: string?,
}

export type ClassDef = {
	name: string,
	superclass: string?,
	properties: { PropertyDef },
}

return {}

package model

#point: {
	latitude:   number & >=-90 & <=90
	longitude:  number & >=-180 & <=180
	label?:     string
	color?:     =~"^#[0-9a-fA-F]{6}$"
	size?:      number & >0
}

kind: "WorldMap"
spec: close({
	points?:         [...#point]
	latitudeLabel?:  string
	longitudeLabel?: string
	labelLabel?:     string
	valueMode?:      "timestamp" | "size" | "ignore"
})

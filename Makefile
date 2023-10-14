DIR = "~/.config/home-manager/"

all:
	mkdir -p $(DIR)

pull: all
	cp $(DIR)* .

push: all
	cp ./* $(DIR)

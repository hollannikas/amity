PROJECT = threads_of_amity

AS = rgbasm
LD = rgblink
FIX = rgbfix

SRCS = src/main.asm
OBJS = main.o
ROM = $(PROJECT).gb

KOTLINC = /opt/homebrew/bin/kotlinc
JAVA = /opt/homebrew/opt/openjdk/bin/java

.PHONY: all assets editor clean

all: $(ROM)

assets:
	python3 tools/gen_assets.py

tools/sprite_editor.jar: tools/SpriteEditor.kt
	$(KOTLINC) tools/SpriteEditor.kt -include-runtime -d tools/sprite_editor.jar

editor: tools/sprite_editor.jar
	$(JAVA) -jar tools/sprite_editor.jar src/assets.inc

main.o: src/main.asm src/hardware.inc src/assets.inc
	$(AS) -o $@ $<

$(ROM): $(OBJS)
	$(LD) -m $(PROJECT).map -n $(PROJECT).sym -o $@ $(OBJS)
	$(FIX) -v -p 0x00 -t "THREADSAMITY" $@
	cp $@ aretha2_demo.gb

clean:
	rm -f $(OBJS) $(ROM) $(PROJECT).map $(PROJECT).sym aretha2_demo.gb aretha2_demo.map aretha2_demo.sym

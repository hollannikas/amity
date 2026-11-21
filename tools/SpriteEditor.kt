import java.awt.*
import java.awt.event.*
import java.awt.image.BufferedImage
import java.io.File
import java.util.ArrayDeque
import javax.swing.*
import javax.swing.border.EmptyBorder
import javax.swing.border.TitledBorder

/**
 * Threads of Amity - Portable Game Boy (DMG 2bpp) Sprite & Map Tile Editor
 * Reads and writes directly from/to src/assets.inc, preserving all labels, comments, and structure.
 * Supports editing existing sprites/tiles AND adding new Sprites & 16x16 Overworld Map Metatiles!
 */

data class TileLine(
    var lineIndex: Int,
    val labelSection: String,
    val indexInSection: Int,
    val bytes: ByteArray, // 16 bytes (8x8 2bpp)
    var comment: String
)

data class SpriteGroupItem(
    val title: String,
    val sectionName: String,
    val startTileIndex: Int,
    val tilesWide: Int,
    val tilesHigh: Int,
    val isSpritePalette: Boolean
) {
    override fun toString(): String = title
}

data class CategoryDef(
    val name: String,
    val items: MutableList<SpriteGroupItem>
) {
    override fun toString(): String = name
}

class AssetsIncDocument(val file: File) {
    val rawLines = mutableListOf<String>()
    val sectionTiles = linkedMapOf<String, MutableList<TileLine>>()

    init {
        reload()
    }

    fun reload() {
        rawLines.clear()
        sectionTiles.clear()
        if (!file.exists()) {
            throw IllegalStateException("Could not find ${file.absolutePath}")
        }
        rawLines.addAll(file.readLines())

        var currentSection = ""
        val pendingAliases = mutableListOf<String>()
        val dbRegex = Regex("""^\s*db\s+((?:\$[0-9A-Fa-f]{2}\s*,\s*){15}\$[0-9A-Fa-f]{2})\s*(?:;\s*(.*))?$""")
        val labelRegex = Regex("""^([A-Za-z0-9_]+):\s*$""")

        for ((lineIdx, line) in rawLines.withIndex()) {
            val labelMatch = labelRegex.matchEntire(line.trim())
            if (labelMatch != null) {
                val lbl = labelMatch.groupValues[1]
                if (!lbl.endsWith("End")) {
                    currentSection = lbl
                    pendingAliases.add(lbl)
                } else {
                    pendingAliases.clear()
                }
                continue
            }

            if (currentSection == "PortraitTilemap") continue

            val dbMatch = dbRegex.matchEntire(line)
            if (dbMatch != null && currentSection.isNotEmpty()) {
                val hexPart = dbMatch.groupValues[1]
                val commentPart = dbMatch.groupValues[2]
                val byteStrings = hexPart.split(",").map { it.trim().removePrefix("$") }
                if (byteStrings.size == 16) {
                    val bytes = ByteArray(16) { i -> byteStrings[i].toInt(16).toByte() }
                    val list = sectionTiles.getOrPut(currentSection) { mutableListOf() }
                    for (alias in pendingAliases) {
                        sectionTiles[alias] = list
                    }
                    pendingAliases.clear()
                    list.add(TileLine(lineIdx, currentSection, list.size, bytes, commentPart))
                }
            }
        }
    }

    /** Decode an 8x8 tile (16 bytes 2bpp) into an 8x8 array of color indices 0..3 */
    fun decodeTile(section: String, tileIdx: Int): Array<IntArray> {
        val list = sectionTiles[section] ?: return Array(8) { IntArray(8) }
        if (tileIdx !in list.indices) return Array(8) { IntArray(8) }
        val b = list[tileIdx].bytes
        val grid = Array(8) { IntArray(8) }
        for (y in 0 until 8) {
            val lo = b[y * 2].toInt() and 0xFF
            val hi = b[y * 2 + 1].toInt() and 0xFF
            for (x in 0 until 8) {
                val bit = 7 - x
                val c = ((lo shr bit) and 1) or (((hi shr bit) and 1) shl 1)
                grid[y][x] = c
            }
        }
        return grid
    }

    /** Encode an 8x8 array of color indices 0..3 back into 16 bytes 2bpp */
    fun encodeTile(section: String, tileIdx: Int, grid: Array<IntArray>) {
        val list = sectionTiles[section] ?: return
        if (tileIdx !in list.indices) return
        val b = list[tileIdx].bytes
        for (y in 0 until 8) {
            var lo = 0
            var hi = 0
            for (x in 0 until 8) {
                val c = grid[y][x] and 3
                val bit = 7 - x
                if ((c and 1) != 0) lo = lo or (1 shl bit)
                if ((c and 2) != 0) hi = hi or (1 shl bit)
            }
            b[y * 2] = lo.toByte()
            b[y * 2 + 1] = hi.toByte()
        }
        syncLinkedTiles(section, tileIdx, b)
    }

    /**
     * Append a grid of (tilesWide x tilesHigh) 8x8 tiles to an existing section right before <Section>End:,
     * or create a brand-new section if it doesn't exist yet!
     * Returns the starting tile index in that section.
     */
    fun appendTilesToSection(
        sectionName: String,
        tilesWide: Int,
        tilesHigh: Int,
        baseComment: String,
        initialPixels: Array<IntArray>? = null
    ): Int {
        syncRawLinesFromMemory()

        val endLabel = "${sectionName}End:"
        var insertLineIdx = rawLines.indexOfFirst { it.trim() == endLabel }

        if (insertLineIdx == -1) {
            // Section does not exist yet — insert before PortraitTilemap: or at the end of the file
            val portraitMapIdx = rawLines.indexOfFirst { it.trim() == "PortraitTilemap:" }
            insertLineIdx = if (portraitMapIdx != -1) portraitMapIdx else rawLines.size
            rawLines.add(insertLineIdx, "$sectionName:")
            insertLineIdx++
            rawLines.add(insertLineIdx, endLabel)
            rawLines.add(insertLineIdx + 1, "")
        }

        val existingCount = sectionTiles[sectionName]?.size ?: 0
        val newLines = mutableListOf<String>()

        for (ty in 0 until tilesHigh) {
            for (tx in 0 until tilesWide) {
                val b = ByteArray(16)
                if (initialPixels != null) {
                    val srcH = initialPixels.size
                    val srcW = initialPixels[0].size
                    for (py in 0 until 8) {
                        var lo = 0
                        var hi = 0
                        for (px in 0 until 8) {
                            val gy = (ty * 8 + py).coerceIn(0, srcH - 1)
                            val gx = (tx * 8 + px).coerceIn(0, srcW - 1)
                            val c = initialPixels[gy][gx] and 3
                            val bit = 7 - px
                            if ((c and 1) != 0) lo = lo or (1 shl bit)
                            if ((c and 2) != 0) hi = hi or (1 shl bit)
                        }
                        b[py * 2] = lo.toByte()
                        b[py * 2 + 1] = hi.toByte()
                    }
                }
                val hexes = b.joinToString(", ") { String.format("\$%02X", it.toInt() and 0xFF) }
                val comment = if (tilesWide == 1 && tilesHigh == 1) {
                    baseComment
                } else {
                    "$baseComment ($tx,$ty)"
                }
                newLines.add("    db $hexes ; $comment")
            }
        }

        rawLines.addAll(insertLineIdx, newLines)
        file.writeText(rawLines.joinToString("\n") + "\n")
        reload()
        return existingCount
    }

    /**
     * Keep duplicate/preview tile blocks in sync automatically:
     * - SpritesAriaTiles[0..7]    <-> TilesetData[$D0..$D7] and SelectScreenHeroSprites[0..7]
     * - SpritesSakuraTiles[0..7]  <-> TilesetData[$D8..$DF] and SelectScreenHeroSprites[8..15]
     * - SpritesOrionTiles[0..7]   <-> TilesetData[$E0..$E7] and SelectScreenHeroSprites[16..23]
     * - MapMetatilesData[0..23]   <-> TilesetData[$10..$27]
     * - CustomSpritesTiles[0..3]  <-> TilesetData[$F0..$F3]
     * - BattleFiendTiles[0..15]   <-> TilesetData[$70..$7F]
     */
    private fun syncLinkedTiles(section: String, tileIdx: Int, srcBytes: ByteArray) {
        fun copyTo(targetSection: String, targetIdx: Int) {
            val tList = sectionTiles[targetSection] ?: return
            if (targetIdx in tList.indices) {
                System.arraycopy(srcBytes, 0, tList[targetIdx].bytes, 0, 16)
            }
        }

        when (section) {
            "SpritesAriaTiles" -> if (tileIdx in 0..7) {
                copyTo("TilesetData", 0xD0 + tileIdx)
                copyTo("SelectScreenHeroSprites", tileIdx)
            }
            "SpritesSakuraTiles" -> if (tileIdx in 0..7) {
                copyTo("TilesetData", 0xD8 + tileIdx)
                copyTo("SelectScreenHeroSprites", 8 + tileIdx)
            }
            "SpritesOrionTiles" -> if (tileIdx in 0..7) {
                copyTo("TilesetData", 0xE0 + tileIdx)
                copyTo("SelectScreenHeroSprites", 16 + tileIdx)
            }
            "MapMetatilesData" -> if (tileIdx in 0..23) {
                copyTo("TilesetData", 0x10 + tileIdx)
            }
            "CustomSpritesTiles" -> if (tileIdx in 0..3) {
                copyTo("TilesetData", 0xF0 + tileIdx)
            }
            "BattleFiendTiles" -> if (tileIdx in 0..15) {
                copyTo("TilesetData", 0x70 + tileIdx)
            }
            "TilesetData" -> {
                when (tileIdx) {
                    in 0x10..0x27 -> copyTo("MapMetatilesData", tileIdx - 0x10)
                    in 0x70..0x7F -> copyTo("BattleFiendTiles", tileIdx - 0x70)
                    in 0xD0..0xD7 -> {
                        copyTo("SpritesAriaTiles", tileIdx - 0xD0)
                        copyTo("SelectScreenHeroSprites", tileIdx - 0xD0)
                    }
                    in 0xD8..0xDF -> {
                        copyTo("SpritesSakuraTiles", tileIdx - 0xD8)
                        copyTo("SelectScreenHeroSprites", 8 + (tileIdx - 0xD8))
                    }
                    in 0xE0..0xE7 -> {
                        copyTo("SpritesOrionTiles", tileIdx - 0xE0)
                        copyTo("SelectScreenHeroSprites", 16 + (tileIdx - 0xE0))
                    }
                    in 0xF0..0xF3 -> copyTo("CustomSpritesTiles", tileIdx - 0xF0)
                }
            }
        }
    }

    private fun syncRawLinesFromMemory() {
        for (list in sectionTiles.values) {
            for (tile in list) {
                val hexes = tile.bytes.joinToString(", ") { String.format("\$%02X", it.toInt() and 0xFF) }
                rawLines[tile.lineIndex] = if (tile.comment.isNotEmpty()) {
                    "    db $hexes ; ${tile.comment}"
                } else {
                    "    db $hexes"
                }
            }
        }
    }

    fun save() {
        syncRawLinesFromMemory()
        file.writeText(rawLines.joinToString("\n") + "\n")
    }
}

class SpriteEditorFrame(private val doc: AssetsIncDocument) : JFrame("Threads of Amity - Game Boy 2bpp Sprite & Map Tile Editor") {
    private var categories = mutableListOf<CategoryDef>()
    private val categoryCombo = JComboBox<CategoryDef>()
    private val itemListModel = DefaultListModel<SpriteGroupItem>()
    private val itemList = JList(itemListModel)

    // Current composite pixel buffer (width = tilesWide*8, height = tilesHigh*8)
    private lateinit var currentItem: SpriteGroupItem
    private var pixels: Array<IntArray> = Array(16) { IntArray(16) }
    private val undoStack = ArrayDeque<Array<IntArray>>()

    private var selectedColor: Int = 3 // 0..3
    private var useSpritePalette: Boolean = true
    private var showGrid: Boolean = true
    private var bucketTool: Boolean = false
    private var animFrameToggle: Boolean = false
    private var suppressComboEvents: Boolean = false

    // DMG Palettes
    private val spriteColors = arrayOf(
        Color(220, 245, 210), // 0: Transparent backdrop tint (drawn with checkerboard)
        Color(250, 250, 245), // 1: Opaque White
        Color(148, 156, 142), // 2: Mid/Light Gray
        Color(24, 28, 24)     // 3: Black
    )

    private val bgColors = arrayOf(
        Color(250, 250, 245), // 0: White
        Color(172, 180, 165), // 1: Light Gray
        Color(92, 100, 88),   // 2: Dark Gray
        Color(20, 24, 20)     // 3: Black
    )

    private val canvasPanel = PixelCanvasPanel()
    private val previewPanel = PreviewPanel()
    private val statusLabel = JLabel("Loaded ${doc.file.path}")
    private val paletteButtons = Array(4) { JToggleButton() }
    private val palModeChk = JCheckBox("Sprite Mode (OBP0: 0=Trans)", true)

    init {
        defaultCloseOperation = EXIT_ON_CLOSE
        minimumSize = Dimension(1150, 760)
        preferredSize = Dimension(1220, 800)
        layout = BorderLayout(8, 8)
        (contentPane as JComponent).border = EmptyBorder(8, 8, 8, 8)

        // Left Panel: Category, Sprite List, and "+ Add Sprite / + Add Map Tile / Duplicate" buttons
        val leftPanel = JPanel(BorderLayout(6, 6))
        leftPanel.preferredSize = Dimension(310, 0)
        leftPanel.border = TitledBorder("1. Select or Add Sprite / Map Tile")

        val catTop = JPanel(BorderLayout(4, 4))
        catTop.add(JLabel("Group:"), BorderLayout.NORTH)
        catTop.add(categoryCombo, BorderLayout.CENTER)
        leftPanel.add(catTop, BorderLayout.NORTH)

        itemList.selectionMode = ListSelectionModel.SINGLE_SELECTION
        itemList.cellRenderer = SpriteThumbnailRenderer()
        itemList.fixedCellHeight = 44
        leftPanel.add(JScrollPane(itemList), BorderLayout.CENTER)

        // Add / Duplicate Action Buttons at bottom of Left Panel
        val addBtnPanel = JPanel(GridLayout(2, 2, 4, 4))
        val addSpriteBtn = JButton("+ Add Sprite...")
        addSpriteBtn.toolTipText = "Add a new 16x16, 32x32, or 80x64 Sprite to src/assets.inc"
        addSpriteBtn.addActionListener { promptAddNewSprite() }

        val addMapTileBtn = JButton("+ Add Map Tile...")
        addMapTileBtn.toolTipText = "Add a new 16x16 (2x2 tiles) Overworld Map Metatile to MapMetatilesData"
        addMapTileBtn.addActionListener { promptAddNewMapTile() }

        val dupBtn = JButton("Duplicate Current")
        dupBtn.toolTipText = "Clone the currently selected Sprite or Map Tile into a new entry"
        dupBtn.addActionListener { duplicateCurrentItem() }

        val renameCommentBtn = JButton("Rename Label...")
        renameCommentBtn.toolTipText = "Rename the display comment for the selected Sprite or Map Tile"
        renameCommentBtn.addActionListener { renameCurrentItem() }

        addBtnPanel.add(addSpriteBtn)
        addBtnPanel.add(addMapTileBtn)
        addBtnPanel.add(dupBtn)
        addBtnPanel.add(renameCommentBtn)
        leftPanel.add(addBtnPanel, BorderLayout.SOUTH)

        add(leftPanel, BorderLayout.WEST)

        // Center Panel: Toolbar + Pixel Canvas
        val centerPanel = JPanel(BorderLayout(6, 6))
        centerPanel.border = TitledBorder("2. Pixel Editor (Left-click: Draw | Right-click: Pick Color)")

        val toolBar = JPanel(FlowLayout(FlowLayout.LEFT, 6, 4))
        val drawBtn = JToggleButton("Pencil", true)
        val fillBtn = JToggleButton("Bucket Fill", false)
        val toolBg = ButtonGroup()
        toolBg.add(drawBtn)
        toolBg.add(fillBtn)
        drawBtn.addActionListener { bucketTool = false }
        fillBtn.addActionListener { bucketTool = true }

        val gridChk = JCheckBox("Grid", true)
        gridChk.addActionListener {
            showGrid = gridChk.isSelected
            canvasPanel.repaint()
        }

        val undoBtn = JButton("Undo")
        undoBtn.addActionListener { performUndo() }

        val flipHBtn = JButton("Flip H")
        flipHBtn.addActionListener { flipHorizontal() }

        val flipVBtn = JButton("Flip V")
        flipVBtn.addActionListener { flipVertical() }

        val shiftLBtn = JButton("←")
        shiftLBtn.toolTipText = "Nudge Left 1px"
        shiftLBtn.addActionListener { shiftPixels(-1, 0) }
        val shiftRBtn = JButton("→")
        shiftRBtn.toolTipText = "Nudge Right 1px"
        shiftRBtn.addActionListener { shiftPixels(1, 0) }
        val shiftUBtn = JButton("↑")
        shiftUBtn.toolTipText = "Nudge Up 1px"
        shiftUBtn.addActionListener { shiftPixels(0, -1) }
        val shiftDBtn = JButton("↓")
        shiftDBtn.toolTipText = "Nudge Down 1px"
        shiftDBtn.addActionListener { shiftPixels(0, 1) }

        val clearBtn = JButton("Clear")
        clearBtn.addActionListener { clearCanvas() }

        toolBar.add(drawBtn)
        toolBar.add(fillBtn)
        toolBar.add(gridChk)
        toolBar.add(JSeparator(SwingConstants.VERTICAL))
        toolBar.add(undoBtn)
        toolBar.add(flipHBtn)
        toolBar.add(flipVBtn)
        toolBar.add(shiftLBtn)
        toolBar.add(shiftRBtn)
        toolBar.add(shiftUBtn)
        toolBar.add(shiftDBtn)
        toolBar.add(clearBtn)

        centerPanel.add(toolBar, BorderLayout.NORTH)
        centerPanel.add(canvasPanel, BorderLayout.CENTER)
        add(centerPanel, BorderLayout.CENTER)

        // Right Panel: Palette + Live Preview + Save / Build Actions
        val rightPanel = JPanel()
        rightPanel.layout = BoxLayout(rightPanel, BoxLayout.Y_AXIS)
        rightPanel.preferredSize = Dimension(300, 0)

        val palPanel = JPanel(GridLayout(5, 1, 4, 4))
        palPanel.border = TitledBorder("3. DMG 2bpp Palette (0..3)")
        palModeChk.addActionListener {
            useSpritePalette = palModeChk.isSelected
            updatePaletteButtons()
            canvasPanel.repaint()
            previewPanel.repaint()
        }
        palPanel.add(palModeChk)

        val palGroup = ButtonGroup()
        for (i in 0..3) {
            val btn = paletteButtons[i]
            btn.isFocusPainted = false
            btn.horizontalAlignment = SwingConstants.LEFT
            if (i == selectedColor) btn.isSelected = true
            btn.addActionListener {
                selectedColor = i
                updatePaletteButtons()
            }
            palGroup.add(btn)
            palPanel.add(btn)
        }
        updatePaletteButtons()
        rightPanel.add(palPanel)
        rightPanel.add(Box.createVerticalStrut(8))

        previewPanel.border = TitledBorder("4. Live Preview & Walk Anim")
        previewPanel.preferredSize = Dimension(280, 260)
        rightPanel.add(previewPanel)
        rightPanel.add(Box.createVerticalStrut(8))

        val savePanel = JPanel(GridLayout(3, 1, 6, 6))
        savePanel.border = TitledBorder("5. Save & Compile ROM")

        val saveBtn = JButton("Save to src/assets.inc (Cmd+S)")
        saveBtn.font = saveBtn.font.deriveFont(Font.BOLD)
        saveBtn.addActionListener { saveAssets(false) }

        val saveBuildBtn = JButton("Save & Build ROM (make)")
        saveBuildBtn.font = saveBuildBtn.font.deriveFont(Font.BOLD)
        saveBuildBtn.addActionListener { saveAssets(true) }

        val reloadBtn = JButton("Reload from src/assets.inc")
        reloadBtn.addActionListener {
            doc.reload()
            rebuildCategoryModelsAndSelect(currentItem.sectionName, currentItem.startTileIndex)
            statusLabel.text = "Reloaded ${doc.file.path} from disk."
        }

        savePanel.add(saveBtn)
        savePanel.add(saveBuildBtn)
        savePanel.add(reloadBtn)
        rightPanel.add(savePanel)

        add(rightPanel, BorderLayout.EAST)

        // Bottom Status Bar
        val bottomPanel = JPanel(BorderLayout())
        bottomPanel.border = EmptyBorder(4, 4, 0, 4)
        bottomPanel.add(statusLabel, BorderLayout.WEST)
        add(bottomPanel, BorderLayout.SOUTH)

        // Wire Category & List Listeners
        categoryCombo.addActionListener {
            if (suppressComboEvents) return@addActionListener
            val cat = categoryCombo.selectedItem as? CategoryDef ?: return@addActionListener
            populateCategory(cat)
        }

        itemList.addListSelectionListener { e ->
            if (!e.valueIsAdjusting) {
                val item = itemList.selectedValue ?: return@addListSelectionListener
                palModeChk.isSelected = item.isSpritePalette
                useSpritePalette = item.isSpritePalette
                updatePaletteButtons()
                loadItemIntoCanvas(item)
            }
        }

        // Keyboard shortcuts: Cmd/Ctrl+Z for Undo, Cmd/Ctrl+S for Save, 1..4 for Palette
        val im = rootPane.getInputMap(JComponent.WHEN_IN_FOCUSED_WINDOW)
        val am = rootPane.actionMap
        val menuMask = Toolkit.getDefaultToolkit().menuShortcutKeyMaskEx
        im.put(KeyStroke.getKeyStroke(KeyEvent.VK_Z, menuMask), "undo")
        am.put("undo", object : AbstractAction() {
            override fun actionPerformed(e: ActionEvent?) = performUndo()
        })
        im.put(KeyStroke.getKeyStroke(KeyEvent.VK_S, menuMask), "save")
        am.put("save", object : AbstractAction() {
            override fun actionPerformed(e: ActionEvent?) = saveAssets(false)
        })
        for (k in 0..3) {
            im.put(KeyStroke.getKeyStroke(KeyEvent.VK_1 + k, 0), "color$k")
            am.put("color$k", object : AbstractAction() {
                override fun actionPerformed(e: ActionEvent?) {
                    selectedColor = k
                    paletteButtons[k].isSelected = true
                    updatePaletteButtons()
                }
            })
        }

        Timer(350) {
            animFrameToggle = !animFrameToggle
            previewPanel.repaint()
        }.start()

        rebuildCategoryModelsAndSelect(null, 0)
        pack()
        setLocationRelativeTo(null)
    }

    private fun stripCoordSuffix(comment: String): String {
        return comment
            .replace(Regex("""\s*\(\d+\s*,\s*\d+\)\s*$"""), "")
            .replace(Regex("""^Tile\s+\$[0-9A-Fa-f]{2}:\s*"""), "")
            .trim()
    }

    private fun buildCategories(): MutableList<CategoryDef> {
        fun charSpritesForSection(charName: String, sec: String): MutableList<SpriteGroupItem> {
            val stdDirs = listOf(
                "Down Frame 0", "Down Frame 1",
                "Up Frame 0", "Up Frame 1",
                "Left Frame 0", "Left Frame 1",
                "Right Frame 0", "Right Frame 1"
            )
            val totalTiles = doc.sectionTiles[sec]?.size ?: 0
            val numSprites = totalTiles / 4
            val list = mutableListOf<SpriteGroupItem>()
            for (idx in 0 until numSprites) {
                val label = if (idx < stdDirs.size) {
                    "$charName - ${stdDirs[idx]} (16x16)"
                } else {
                    val rawComment = doc.sectionTiles[sec]?.getOrNull(idx * 4)?.comment ?: "Extra Frame $idx"
                    "$charName - ${stripCoordSuffix(rawComment)} (16x16)"
                }
                list.add(SpriteGroupItem(label, sec, idx * 4, 2, 2, true))
            }
            return list
        }

        // Overworld NPC, Enemy & Custom 16x16 Sprites
        val npcEnemyItems = mutableListOf(
            SpriteGroupItem("Boss Terf Overworld (\$F4-\$F7, 16x16)", "TilesetData", 0xF4, 2, 2, true),
            SpriteGroupItem("NPC Gaius Overworld (\$F8-\$FB, 16x16)", "TilesetData", 0xF8, 2, 2, true),
            SpriteGroupItem("Shadow Fiend Overworld (\$FC-\$FF, 16x16)", "TilesetData", 0xFC, 2, 2, true)
        )
        val customSpriteTiles = doc.sectionTiles["CustomSpritesTiles"] ?: emptyList()
        val numCustomSprites = customSpriteTiles.size / 4
        for (i in 0 until numCustomSprites) {
            val rawCmt = stripCoordSuffix(customSpriteTiles[i * 4].comment.ifEmpty { "Custom Sprite $i" })
            npcEnemyItems.add(SpriteGroupItem("$rawCmt (Custom #$i, 16x16)", "CustomSpritesTiles", i * 4, 2, 2, true))
        }
        // Also scan any user-created Sprite*Tiles sections!
        val builtInSpriteSecs = setOf("SpritesAriaTiles", "SpritesSakuraTiles", "SpritesOrionTiles", "CustomSpritesTiles", "SelectScreenHeroSprites")
        for ((secName, list) in doc.sectionTiles) {
            if (secName.startsWith("Sprite") && secName !in builtInSpriteSecs && list.size >= 4) {
                val count = list.size / 4
                for (i in 0 until count) {
                    val cmt = stripCoordSuffix(list[i * 4].comment.ifEmpty { "$secName #$i" })
                    npcEnemyItems.add(SpriteGroupItem("$cmt [$secName, 16x16]", secName, i * 4, 2, 2, true))
                }
            }
        }

        // 2.5D Overworld Map Metatiles (reads all 16x16 metatiles in MapMetatilesData, or falls back to TilesetData $10..$27)
        val mapMetatileItems = mutableListOf<SpriteGroupItem>()
        val mtList = doc.sectionTiles["MapMetatilesData"]
        if (mtList != null && mtList.size >= 4) {
            val numMetatiles = mtList.size / 4
            for (mtId in 0 until numMetatiles) {
                val cmt = stripCoordSuffix(mtList[mtId * 4].comment.ifEmpty { "Metatile $mtId" })
                val vramTile = 0x80 + mtId * 4
                mapMetatileItems.add(
                    SpriteGroupItem(
                        String.format("%s (ID %d, VRAM \$%02X, 16x16)", cmt, mtId, vramTile),
                        "MapMetatilesData",
                        mtId * 4,
                        2,
                        2,
                        false
                    )
                )
            }
        } else {
            val fallbackNames = listOf("Grass", "Road", "2.5D Tree", "Stone Wall", "River Water", "Shrine Roof")
            for (mtId in 0 until 6) {
                mapMetatileItems.add(
                    SpriteGroupItem("Metatile $mtId: ${fallbackNames[mtId]} (16x16)", "TilesetData", 0x10 + mtId * 4, 2, 2, false)
                )
            }
        }

        // Battle Monster Graphics (including any user-added Battle*Tiles sections!)
        val battleItems = mutableListOf(
            SpriteGroupItem("Shadow Fiend Battle (32x32, 4x4 tiles)", "BattleFiendTiles", 0, 4, 4, false),
            SpriteGroupItem("Boss Terf Battle (64x48, 8x6 tiles)", "BattleTerfTiles", 0, 8, 6, false)
        )
        for ((secName, list) in doc.sectionTiles) {
            if (secName.startsWith("Battle") && secName != "BattleFiendTiles" && secName != "BattleTerfTiles") {
                if (list.size == 48) {
                    battleItems.add(SpriteGroupItem("$secName (64x48, 8x6 tiles)", secName, 0, 8, 6, false))
                } else if (list.size >= 16) {
                    val count = list.size / 16
                    for (i in 0 until count) {
                        val cmt = stripCoordSuffix(list[i * 16].comment.ifEmpty { "$secName #$i" })
                        battleItems.add(SpriteGroupItem("$cmt [$secName, 32x32]", secName, i * 16, 4, 4, false))
                    }
                }
            }
        }

        // Dialogue Portraits (including any user-added Portrait*Tiles sections!)
        val portraitItems = mutableListOf(
            SpriteGroupItem("Aria Portrait (80x64, 10x8 tiles)", "PortraitAriaTiles", 0, 10, 8, false),
            SpriteGroupItem("Sakura Portrait (80x64, 10x8 tiles)", "PortraitSakuraTiles", 0, 10, 8, false),
            SpriteGroupItem("Orion Portrait (80x64, 10x8 tiles)", "PortraitOrionTiles", 0, 10, 8, false),
            SpriteGroupItem("Gaius Portrait (80x64, 10x8 tiles)", "PortraitGaiusTiles", 0, 10, 8, false),
            SpriteGroupItem("Boss Terf Portrait (80x64, 10x8 tiles)", "PortraitTerfTiles", 0, 10, 8, false),
            SpriteGroupItem("Bob (Bearded) Portrait (80x64, 10x8 tiles)", "PortraitBobBeardedTiles", 0, 10, 8, false),
            SpriteGroupItem("Bob (She/Her) Portrait (80x64, 10x8 tiles)", "PortraitBobFemTiles", 0, 10, 8, false)
        )
        val builtInPortraits = setOf(
            "PortraitAriaTiles", "PortraitSakuraTiles", "PortraitOrionTiles",
            "PortraitGaiusTiles", "PortraitMateriaTiles", "PortraitTerfTiles",
            "PortraitBobBeardedTiles", "PortraitBobFemTiles"
        )
        for ((secName, list) in doc.sectionTiles) {
            if (secName.startsWith("Portrait") && secName !in builtInPortraits && list.size >= 80) {
                val cmt = stripCoordSuffix(list[0].comment.ifEmpty { secName })
                portraitItems.add(SpriteGroupItem("$cmt [$secName, 80x64]", secName, 0, 10, 8, false))
            }
        }

        // Inventory Item Sprites (16x16) - reads ItemSpritesTiles and any Item*Tiles sections
        val itemSpriteList = doc.sectionTiles["ItemSpritesTiles"] ?: emptyList()
        val numItemSprites = itemSpriteList.size / 4
        val itemSpriteItems = mutableListOf<SpriteGroupItem>()
        for (i in 0 until numItemSprites) {
            val rawCmt = stripCoordSuffix(itemSpriteList[i * 4].comment.ifEmpty { "Item ${i + 1}" })
            val vramTile = 0xD0 + i * 4
            itemSpriteItems.add(
                SpriteGroupItem(
                    String.format("%s (Item ID %d, VRAM \$%02X, 16x16)", rawCmt, i + 1, vramTile),
                    "ItemSpritesTiles",
                    i * 4,
                    2,
                    2,
                    true
                )
            )
        }
        for ((secName, list) in doc.sectionTiles) {
            if (secName.startsWith("Item") && secName != "ItemSpritesTiles" && list.size >= 4) {
                val count = list.size / 4
                for (i in 0 until count) {
                    val cmt = stripCoordSuffix(list[i * 4].comment.ifEmpty { "$secName #$i" })
                    itemSpriteItems.add(SpriteGroupItem("$cmt [$secName, 16x16]", secName, i * 4, 2, 2, true))
                }
            }
        }

        val all8x8Tiles = (0x00..0xFF).map { tid ->
            val comment = doc.sectionTiles["TilesetData"]?.getOrNull(tid)?.comment ?: "Tile \$${String.format("%02X", tid)}"
            val isSpr = tid >= 0xD0
            SpriteGroupItem(
                String.format("\$%02X: %s", tid, comment.removePrefix("Tile \$${String.format("%02X", tid)}: ")),
                "TilesetData", tid, 1, 1, isSpr
            )
        }.toMutableList()

        return mutableListOf(
            CategoryDef("Hero Sprites: M - ARIA (16x16)", charSpritesForSection("Aria", "SpritesAriaTiles")),
            CategoryDef("Hero Sprites: F - SAKURA (16x16)", charSpritesForSection("Sakura", "SpritesSakuraTiles")),
            CategoryDef("Hero Sprites: NB - ORION (16x16)", charSpritesForSection("Orion", "SpritesOrionTiles")),
            CategoryDef("Overworld NPC, Enemy & Custom Sprites (16x16)", npcEnemyItems),
            CategoryDef("Inventory Item Sprites (16x16)", itemSpriteItems),
            CategoryDef("2.5D Overworld Map Metatiles (16x16)", mapMetatileItems),
            CategoryDef("Battle Monster Graphics (32x32 & 64x48)", battleItems),
            CategoryDef("Dialogue Portraits (80x64)", portraitItems),
            CategoryDef("All VRAM 8x8 Tiles (\$00..\$FF)", all8x8Tiles)
        )
    }

    private fun rebuildCategoryModelsAndSelect(targetSection: String?, targetTileIdx: Int) {
        suppressComboEvents = true
        val prevCatIdx = categoryCombo.selectedIndex.coerceAtLeast(0)
        categories = buildCategories()
        categoryCombo.removeAllItems()
        for (c in categories) categoryCombo.addItem(c)

        var chosenCatIdx = prevCatIdx.coerceIn(0, categories.lastIndex)
        var chosenItemIdx = 0

        if (targetSection != null) {
            for ((cIdx, cat) in categories.withIndex()) {
                val iIdx = cat.items.indexOfFirst { it.sectionName == targetSection && it.startTileIndex == targetTileIdx }
                if (iIdx != -1) {
                    chosenCatIdx = cIdx
                    chosenItemIdx = iIdx
                    break
                }
            }
        }

        categoryCombo.selectedIndex = chosenCatIdx
        suppressComboEvents = false
        populateCategory(categories[chosenCatIdx], chosenItemIdx)
    }

    private fun populateCategory(cat: CategoryDef, selectIndex: Int = 0) {
        itemListModel.clear()
        for (it in cat.items) itemListModel.addElement(it)
        if (!itemListModel.isEmpty) {
            itemList.selectedIndex = selectIndex.coerceIn(0, itemListModel.size() - 1)
            itemList.ensureIndexIsVisible(itemList.selectedIndex)
        }
    }

    /** Dialog to add a brand-new Sprite (16x16 Inventory Item, Overworld/Hero/Custom Bank, 32x32 Battle Monster, or 80x64 Portrait) */
    private fun promptAddNewSprite() {
        writeCanvasBackToDocument()

        val nextItemId = ((doc.sectionTiles["ItemSpritesTiles"]?.size ?: 0) / 4) + 1
        val isInvCat = (categoryCombo.selectedItem as? CategoryDef)?.name?.contains("Inventory Item") == true
        val nameField = JTextField(if (isInvCat) "Item $nextItemId: Health Potion" else "NewSprite", 18)
        val typeOptions = arrayOf(
            "16x16 Inventory Item Sprite (adds to ItemSpritesTiles)",
            "16x16 Overworld / Custom Sprite (adds to CustomSpritesTiles)",
            "16x16 New Named Sprite Bank (creates Sprite<Name>Tiles: in assets.inc)",
            "16x16 Extra Frame for M: ARIA (adds to SpritesAriaTiles)",
            "16x16 Extra Frame for F: SAKURA (adds to SpritesSakuraTiles)",
            "16x16 Extra Frame for NB: ORION (adds to SpritesOrionTiles)",
            "32x32 Battle Monster Graphic (creates Battle<Name>Tiles: in assets.inc)",
            "80x64 Dialogue Portrait (creates Portrait<Name>Tiles: in assets.inc)"
        )
        val typeCombo = JComboBox(typeOptions)
        typeCombo.selectedIndex = if (isInvCat) 0 else 1
        val cloneChk = JCheckBox("Initialize with copy of current canvas pixels", false)

        val panel = JPanel(GridLayout(0, 1, 4, 4))
        panel.add(JLabel("Sprite / Item Name:"))
        panel.add(nameField)
        panel.add(JLabel("Sprite Type & Destination:"))
        panel.add(typeCombo)
        panel.add(cloneChk)

        val res = JOptionPane.showConfirmDialog(
            this, panel, "Add New Sprite / Inventory Item to src/assets.inc",
            JOptionPane.OK_CANCEL_OPTION, JOptionPane.PLAIN_MESSAGE
        )
        if (res != JOptionPane.OK_OPTION) return

        val rawName = nameField.text.trim().ifEmpty { "NewSprite" }
        val cleanId = rawName.replace(Regex("""[^A-Za-z0-9_]"""), "")
            .replaceFirstChar { it.uppercase() }
            .ifEmpty { "Custom" }
        val initPx = if (cloneChk.isSelected) pixels else null

        val (targetSection, tw, th, comment) = when (typeCombo.selectedIndex) {
            0 -> Quad("ItemSpritesTiles", 2, 2, if (rawName.startsWith("Item", ignoreCase = true)) rawName else "Item $nextItemId: $rawName")
            1 -> Quad("CustomSpritesTiles", 2, 2, "Custom Sprite: $rawName")
            2 -> Quad("Sprite${cleanId}Tiles", 2, 2, "$rawName")
            3 -> Quad("SpritesAriaTiles", 2, 2, "Aria $rawName")
            4 -> Quad("SpritesSakuraTiles", 2, 2, "Sakura $rawName")
            5 -> Quad("SpritesOrionTiles", 2, 2, "Orion $rawName")
            6 -> Quad("Battle${cleanId}Tiles", 4, 4, "Battle $rawName")
            else -> Quad("Portrait${cleanId}Tiles", 10, 8, "Portrait $rawName")
        }

        val newStartIdx = doc.appendTilesToSection(targetSection, tw, th, comment, initPx)
        rebuildCategoryModelsAndSelect(targetSection, newStartIdx)
        statusLabel.text = "Added '$rawName' (${tw * 8}x${th * 8}px) to $targetSection at tile #$newStartIdx and saved src/assets.inc!"
    }

    /** Dialog to add a brand-new 16x16 (2x2 tiles) Overworld Map Metatile to MapMetatilesData */
    private fun promptAddNewMapTile() {
        writeCanvasBackToDocument()

        val nextMtId = (doc.sectionTiles["MapMetatilesData"]?.size ?: 24) / 4
        val nameField = JTextField("Flower Grass", 18)
        val cloneChk = JCheckBox("Initialize with copy of current canvas pixels", false)

        val panel = JPanel(GridLayout(0, 1, 4, 4))
        panel.add(JLabel("Adding Metatile ID #$nextMtId (16x16px = 4 8x8 tiles in MapMetatilesData):"))
        panel.add(JLabel("Map Metatile Name:"))
        panel.add(nameField)
        panel.add(cloneChk)

        val res = JOptionPane.showConfirmDialog(
            this, panel, "Add New 16x16 Overworld Map Metatile",
            JOptionPane.OK_CANCEL_OPTION, JOptionPane.PLAIN_MESSAGE
        )
        if (res != JOptionPane.OK_OPTION) return

        val rawName = nameField.text.trim().ifEmpty { "Custom Tile $nextMtId" }
        val initPx = if (cloneChk.isSelected) pixels else null
        val comment = "Metatile $nextMtId: $rawName"

        val newStartIdx = doc.appendTilesToSection("MapMetatilesData", 2, 2, comment, initPx)
        rebuildCategoryModelsAndSelect("MapMetatilesData", newStartIdx)
        statusLabel.text = "Added '$comment' (Metatile ID #$nextMtId) to MapMetatilesData and saved src/assets.inc!"
    }

    /** One-click Duplicate of the currently selected Sprite or Map Metatile */
    private fun duplicateCurrentItem() {
        writeCanvasBackToDocument()
        val item = currentItem
        val baseTitle = item.title.replace(Regex("""\s*\([^)]*\)\s*$"""), "").trim()

        if (item.sectionName == "MapMetatilesData" || (item.sectionName == "TilesetData" && item.startTileIndex in 0x10..0x27)) {
            val nextMtId = (doc.sectionTiles["MapMetatilesData"]?.size ?: 24) / 4
            val comment = "Metatile $nextMtId: $baseTitle Copy"
            val newStartIdx = doc.appendTilesToSection("MapMetatilesData", 2, 2, comment, pixels)
            rebuildCategoryModelsAndSelect("MapMetatilesData", newStartIdx)
            statusLabel.text = "Duplicated as '$comment' (Metatile ID #$nextMtId)!"
        } else {
            val destSec = if (item.sectionName == "TilesetData") "CustomSpritesTiles" else item.sectionName
            val comment = "$baseTitle Copy"
            val newStartIdx = doc.appendTilesToSection(destSec, item.tilesWide, item.tilesHigh, comment, pixels)
            rebuildCategoryModelsAndSelect(destSec, newStartIdx)
            statusLabel.text = "Duplicated '$baseTitle' into $destSec at tile #$newStartIdx!"
        }
    }

    /** Rename the comment/label of the currently selected Sprite or Map Metatile */
    private fun renameCurrentItem() {
        writeCanvasBackToDocument()
        val item = currentItem
        val list = doc.sectionTiles[item.sectionName] ?: return
        if (item.startTileIndex !in list.indices) return
        val currentName = stripCoordSuffix(list[item.startTileIndex].comment)
        val newName = JOptionPane.showInputDialog(this, "Enter new label/comment:", currentName)?.trim()
        if (newName.isNullOrEmpty()) return

        val count = item.tilesWide * item.tilesHigh
        for (ty in 0 until item.tilesHigh) {
            for (tx in 0 until item.tilesWide) {
                val idx = item.startTileIndex + ty * item.tilesWide + tx
                if (idx in list.indices) {
                    list[idx].comment = if (count == 1) newName else "$newName ($tx,$ty)"
                }
            }
        }
        doc.save()
        rebuildCategoryModelsAndSelect(item.sectionName, item.startTileIndex)
        statusLabel.text = "Renamed to '$newName' and saved src/assets.inc."
    }

    private data class Quad(val sec: String, val tw: Int, val th: Int, val comment: String)

    private fun updatePaletteButtons() {
        val labels = if (useSpritePalette) {
            arrayOf(
                "0: Transparent (Exterior)",
                "1: Opaque White (Skin/Eyes)",
                "2: Light Gray (Shading/Cloth)",
                "3: Black (Outlines/Hair)"
            )
        } else {
            arrayOf(
                "0: White (BG Paper)",
                "1: Light Gray",
                "2: Dark Gray",
                "3: Black"
            )
        }
        val pal = if (useSpritePalette) spriteColors else bgColors
        for (i in 0..3) {
            val btn = paletteButtons[i]
            val prefix = if (i == selectedColor) "▶ " else "   "
            btn.text = "$prefix${labels[i]}  [Key ${i + 1}]"
            btn.icon = ColorSwatchIcon(pal[i], useSpritePalette && i == 0)
        }
    }

    private fun loadItemIntoCanvas(item: SpriteGroupItem) {
        currentItem = item
        undoStack.clear()
        val pw = item.tilesWide * 8
        val ph = item.tilesHigh * 8
        pixels = Array(ph) { IntArray(pw) }

        for (ty in 0 until item.tilesHigh) {
            for (tx in 0 until item.tilesWide) {
                val tileOffset = ty * item.tilesWide + tx
                val tGrid = doc.decodeTile(item.sectionName, item.startTileIndex + tileOffset)
                for (py in 0 until 8) {
                    for (px in 0 until 8) {
                        pixels[ty * 8 + py][tx * 8 + px] = tGrid[py][px]
                    }
                }
            }
        }
        canvasPanel.repaint()
        previewPanel.repaint()
        statusLabel.text = "Editing: ${item.title} [${item.sectionName}, tile #${item.startTileIndex}, ${pw}x${ph}px]"
    }

    private fun writeCanvasBackToDocument() {
        if (!::currentItem.isInitialized) return
        val item = currentItem
        for (ty in 0 until item.tilesHigh) {
            for (tx in 0 until item.tilesWide) {
                val tileOffset = ty * item.tilesWide + tx
                val sub = Array(8) { py ->
                    IntArray(8) { px ->
                        pixels[ty * 8 + py][tx * 8 + px]
                    }
                }
                doc.encodeTile(item.sectionName, item.startTileIndex + tileOffset, sub)
            }
        }
        itemList.repaint()
        previewPanel.repaint()
    }

    private fun pushUndo() {
        val copy = Array(pixels.size) { y -> pixels[y].clone() }
        undoStack.push(copy)
        if (undoStack.size > 50) undoStack.removeLast()
    }

    private fun performUndo() {
        if (undoStack.isNotEmpty()) {
            pixels = undoStack.pop()
            writeCanvasBackToDocument()
            canvasPanel.repaint()
            statusLabel.text = "Undid last action."
        }
    }

    private fun flipHorizontal() {
        pushUndo()
        val h = pixels.size
        val w = pixels[0].size
        for (y in 0 until h) {
            for (x in 0 until w / 2) {
                val tmp = pixels[y][x]
                pixels[y][x] = pixels[y][w - 1 - x]
                pixels[y][w - 1 - x] = tmp
            }
        }
        writeCanvasBackToDocument()
        canvasPanel.repaint()
    }

    private fun flipVertical() {
        pushUndo()
        val h = pixels.size
        for (y in 0 until h / 2) {
            val tmp = pixels[y]
            pixels[y] = pixels[h - 1 - y]
            pixels[h - 1 - y] = tmp
        }
        writeCanvasBackToDocument()
        canvasPanel.repaint()
    }

    private fun shiftPixels(dx: Int, dy: Int) {
        pushUndo()
        val h = pixels.size
        val w = pixels[0].size
        val next = Array(h) { IntArray(w) }
        for (y in 0 until h) {
            for (x in 0 until w) {
                val sy = (y - dy + h) % h
                val sx = (x - dx + w) % w
                next[y][x] = pixels[sy][sx]
            }
        }
        pixels = next
        writeCanvasBackToDocument()
        canvasPanel.repaint()
    }

    private fun clearCanvas() {
        pushUndo()
        for (y in pixels.indices) {
            for (x in pixels[y].indices) {
                pixels[y][x] = 0
            }
        }
        writeCanvasBackToDocument()
        canvasPanel.repaint()
    }

    private fun floodFill(startX: Int, startY: Int, targetColor: Int, replacementColor: Int) {
        if (targetColor == replacementColor) return
        val h = pixels.size
        val w = pixels[0].size
        val q = ArrayDeque<Pair<Int, Int>>()
        q.add(startX to startY)
        pixels[startY][startX] = replacementColor
        val dirs = arrayOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)
        while (q.isNotEmpty()) {
            val (cx, cy) = q.removeFirst()
            for ((dx, dy) in dirs) {
                val nx = cx + dx
                val ny = cy + dy
                if (nx in 0 until w && ny in 0 until h && pixels[ny][nx] == targetColor) {
                    pixels[ny][nx] = replacementColor
                    q.add(nx to ny)
                }
            }
        }
    }

    private fun saveAssets(andBuildRom: Boolean) {
        try {
            writeCanvasBackToDocument()
            doc.save()
            if (!andBuildRom) {
                statusLabel.text = "Saved changes to ${doc.file.path}!"
                JOptionPane.showMessageDialog(
                    this,
                    "Successfully saved 2bpp tiles to ${doc.file.path}!\nRun 'make' to compile threads_of_amity.gb.",
                    "Saved assets.inc",
                    JOptionPane.INFORMATION_MESSAGE
                )
            } else {
                val proc = ProcessBuilder("make")
                    .directory(doc.file.parentFile?.parentFile ?: File("."))
                    .redirectErrorStream(true)
                    .start()
                val out = proc.inputStream.bufferedReader().readText()
                val code = proc.waitFor()
                if (code == 0) {
                    statusLabel.text = "Saved ${doc.file.path} and built threads_of_amity.gb!"
                    JOptionPane.showMessageDialog(
                        this,
                        "Saved ${doc.file.path} and rebuilt threads_of_amity.gb!\n\n$out",
                        "ROM Built Successfully",
                        JOptionPane.INFORMATION_MESSAGE
                    )
                } else {
                    statusLabel.text = "Build failed (exit $code)"
                    JOptionPane.showMessageDialog(
                        this,
                        "Saved ${doc.file.path}, but 'make' returned exit code $code:\n\n$out",
                        "Build Error",
                        JOptionPane.ERROR_MESSAGE
                    )
                }
            }
        } catch (ex: Exception) {
            JOptionPane.showMessageDialog(this, "Error saving: ${ex.message}", "Error", JOptionPane.ERROR_MESSAGE)
        }
    }

    fun renderItemImage(item: SpriteGroupItem, sprPal: Boolean): BufferedImage {
        val pw = item.tilesWide * 8
        val ph = item.tilesHigh * 8
        val img = BufferedImage(pw, ph, BufferedImage.TYPE_INT_ARGB)
        val pal = if (sprPal) spriteColors else bgColors
        for (ty in 0 until item.tilesHigh) {
            for (tx in 0 until item.tilesWide) {
                val tGrid = doc.decodeTile(item.sectionName, item.startTileIndex + ty * item.tilesWide + tx)
                for (py in 0 until 8) {
                    for (px in 0 until 8) {
                        val c = tGrid[py][px] and 3
                        val gx = tx * 8 + px
                        val gy = ty * 8 + py
                        if (sprPal && c == 0) {
                            val chk = if (((gx / 2) + (gy / 2)) % 2 == 0) Color(215, 238, 205).rgb else Color(190, 220, 180).rgb
                            img.setRGB(gx, gy, chk)
                        } else {
                            img.setRGB(gx, gy, pal[c].rgb)
                        }
                    }
                }
            }
        }
        return img
    }

    private inner class PixelCanvasPanel : JPanel() {
        private var isDrawing = false

        init {
            background = Color(40, 44, 40)
            val mouseHandler = object : MouseAdapter() {
                override fun mousePressed(e: MouseEvent) {
                    val pt = screenToPixel(e.x, e.y) ?: return
                    if (SwingUtilities.isRightMouseButton(e)) {
                        selectedColor = pixels[pt.second][pt.first]
                        paletteButtons[selectedColor].isSelected = true
                        updatePaletteButtons()
                        statusLabel.text = "Picked color $selectedColor at (${pt.first}, ${pt.second})"
                        return
                    }
                    pushUndo()
                    isDrawing = true
                    applyToolAt(pt.first, pt.second)
                }

                override fun mouseDragged(e: MouseEvent) {
                    if (!isDrawing || bucketTool) return
                    val pt = screenToPixel(e.x, e.y) ?: return
                    applyToolAt(pt.first, pt.second)
                }

                override fun mouseReleased(e: MouseEvent) {
                    if (isDrawing) {
                        isDrawing = false
                        writeCanvasBackToDocument()
                    }
                }
            }
            addMouseListener(mouseHandler)
            addMouseMotionListener(mouseHandler)
        }

        private fun applyToolAt(px: Int, py: Int) {
            if (bucketTool) {
                floodFill(px, py, pixels[py][px], selectedColor)
                writeCanvasBackToDocument()
            } else {
                if (pixels[py][px] != selectedColor) {
                    pixels[py][px] = selectedColor
                    writeCanvasBackToDocument()
                }
            }
            repaint()
        }

        private fun computeLayoutMetrics(): IntArray {
            val pw = pixels[0].size
            val ph = pixels.size
            val pad = 16
            val availW = (width - pad * 2).coerceAtLeast(64)
            val availH = (height - pad * 2).coerceAtLeast(64)
            val scale = minOf(availW / pw, availH / ph).coerceAtLeast(4)
            val drawW = pw * scale
            val drawH = ph * scale
            val ox = (width - drawW) / 2
            val oy = (height - drawH) / 2
            return intArrayOf(ox, oy, scale, pw, ph)
        }

        private fun screenToPixel(mx: Int, my: Int): Pair<Int, Int>? {
            val (ox, oy, scale, pw, ph) = computeLayoutMetrics()
            val px = (mx - ox) / scale
            val py = (my - oy) / scale
            if (mx < ox || my < oy || px !in 0 until pw || py !in 0 until ph) return null
            return px to py
        }

        override fun paintComponent(g: Graphics) {
            super.paintComponent(g)
            if (!::currentItem.isInitialized) return
            val g2 = g as Graphics2D
            val (ox, oy, scale, pw, ph) = computeLayoutMetrics()
            val pal = if (useSpritePalette) spriteColors else bgColors

            for (y in 0 until ph) {
                for (x in 0 until pw) {
                    val c = pixels[y][x] and 3
                    val rx = ox + x * scale
                    val ry = oy + y * scale
                    if (useSpritePalette && c == 0) {
                        val half = (scale / 2).coerceAtLeast(2)
                        g2.color = Color(218, 240, 210)
                        g2.fillRect(rx, ry, scale, scale)
                        g2.color = Color(188, 218, 178)
                        g2.fillRect(rx + half, ry, scale - half, half)
                        g2.fillRect(rx, ry + half, half, scale - half)
                    } else {
                        g2.color = pal[c]
                        g2.fillRect(rx, ry, scale, scale)
                    }
                }
            }

            if (showGrid && scale >= 6) {
                g2.color = Color(100, 110, 100, 90)
                for (x in 0..pw) {
                    g2.drawLine(ox + x * scale, oy, ox + x * scale, oy + ph * scale)
                }
                for (y in 0..ph) {
                    g2.drawLine(ox, oy + y * scale, ox + pw * scale, oy + y * scale)
                }
            }

            g2.color = Color(255, 200, 60, 190)
            g2.stroke = BasicStroke(1.5f)
            for (tx in 0..currentItem.tilesWide) {
                val lx = ox + tx * 8 * scale
                g2.drawLine(lx, oy, lx, oy + ph * scale)
            }
            for (ty in 0..currentItem.tilesHigh) {
                val ly = oy + ty * 8 * scale
                g2.drawLine(ox, ly, ox + pw * scale, ly)
            }
        }
    }

    private inner class PreviewPanel : JPanel() {
        init {
            background = Color(48, 52, 48)
        }

        override fun paintComponent(g: Graphics) {
            super.paintComponent(g)
            if (!::currentItem.isInitialized) return
            val g2 = g as Graphics2D
            val img = renderItemImage(currentItem, useSpritePalette)

            g2.color = Color(230, 235, 230)
            g2.drawString("Actual (1x / 2x / 4x):", 14, 24)

            g2.drawImage(img, 16, 36, img.width, img.height, null)
            val x2 = 28 + img.width
            g2.drawImage(img, x2, 36, img.width * 2, img.height * 2, null)
            if (img.width <= 32) {
                val x4 = x2 + img.width * 2 + 16
                g2.drawImage(img, x4, 36, img.width * 4, img.height * 4, null)
            }

            if (currentItem.sectionName.startsWith("Sprites") && currentItem.tilesWide == 2 && currentItem.tilesHigh == 2) {
                val pairBase = (currentItem.startTileIndex / 8) * 8
                val secSize = doc.sectionTiles[currentItem.sectionName]?.size ?: 0
                val frameTile = if (animFrameToggle && pairBase + 7 < secSize) pairBase + 4 else pairBase
                val animItem = currentItem.copy(startTileIndex = frameTile)
                val animImg = renderItemImage(animItem, true)

                val ay = 135
                g2.color = Color(230, 235, 230)
                g2.drawString("Live 2-Frame Walk Animation:", 14, ay)
                g2.drawImage(animImg, 24, ay + 10, 64, 64, null)
                g2.drawString(if (animFrameToggle) "Frame 1" else "Frame 0", 104, ay + 46)
            }
        }
    }

    private inner class SpriteThumbnailRenderer : DefaultListCellRenderer() {
        override fun getListCellRendererComponent(
            list: JList<*>?,
            value: Any?,
            index: Int,
            isSelected: Boolean,
            cellHasFocus: Boolean
        ): Component {
            val lbl = super.getListCellRendererComponent(list, value, index, isSelected, cellHasFocus) as JLabel
            val item = value as? SpriteGroupItem ?: return lbl
            val raw = renderItemImage(item, item.isSpritePalette)
            val thumbH = 32
            val thumbW = ((raw.width.toDouble() / raw.height.toDouble()) * thumbH).toInt().coerceIn(16, 48)
            val scaled = BufferedImage(thumbW, thumbH, BufferedImage.TYPE_INT_ARGB)
            val g2 = scaled.createGraphics()
            g2.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR)
            g2.drawImage(raw, 0, 0, thumbW, thumbH, null)
            g2.dispose()
            lbl.icon = ImageIcon(scaled)
            lbl.border = EmptyBorder(4, 6, 4, 6)
            return lbl
        }
    }

    private class ColorSwatchIcon(val color: Color, val isTransparent: Boolean) : Icon {
        override fun getIconWidth(): Int = 22
        override fun getIconHeight(): Int = 22
        override fun paintIcon(c: Component?, g: Graphics, x: Int, y: Int) {
            if (isTransparent) {
                g.color = Color(218, 240, 210)
                g.fillRect(x, y, 22, 22)
                g.color = Color(180, 210, 170)
                g.fillRect(x + 11, y, 11, 11)
                g.fillRect(x, y + 11, 11, 11)
            } else {
                g.color = color
                g.fillRect(x, y, 22, 22)
            }
            g.color = Color.DARK_GRAY
            g.drawRect(x, y, 21, 21)
        }
    }
}

fun main(args: Array<String>) {
    if (args.contains("--test-roundtrip")) {
        val path = args.firstOrNull { !it.startsWith("--") } ?: "src/assets.inc"
        val doc = AssetsIncDocument(File(path))
        println("Loaded sections from $path:")
        for ((sec, list) in doc.sectionTiles) {
            if (list.isNotEmpty()) {
                println("  - $sec: ${list.size} tiles")
                for (i in list.indices) {
                    val grid = doc.decodeTile(sec, i)
                    doc.encodeTile(sec, i, grid)
                }
            }
        }
        doc.save()
        println("Roundtrip save to $path succeeded!")
        return
    }
    val path = if (args.isNotEmpty()) args[0] else "src/assets.inc"
    val file = File(path)
    SwingUtilities.invokeLater {
        try {
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName())
        } catch (_: Exception) {}
        val doc = AssetsIncDocument(file)
        val frame = SpriteEditorFrame(doc)
        frame.isVisible = true
    }
}

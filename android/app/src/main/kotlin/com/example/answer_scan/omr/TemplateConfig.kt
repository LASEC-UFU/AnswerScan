package com.example.answer_scan.omr

object TemplateConfig {
    const val WARP_W = 2100
    const val WARP_H = 780

    const val N_COLS = 20
    const val N_ROWS = 5
    val OPTION_LABELS = arrayOf("A", "B", "C", "D", "E")

    // Per-column cell center X positions in the warped image (WARP_W=2100).
    // Measured from gabarito_render-1.png at 300 DPI — non-uniform widths:
    // Q1-Q9: 50px wide cells; Q10: 58px; Q11-Q20: ~59px.
    val COLUMN_CENTERS_PX = intArrayOf(
        73, 171, 269, 367, 465, 562, 660, 758, 856,  // Q1-Q9
        958,                                           // Q10
        1064, 1170, 1277, 1383, 1489, 1596, 1702, 1809, 1915, 2021,  // Q11-Q20
    )
    val COLUMN_HALF_W_PX = intArrayOf(
        24, 24, 24, 24, 24, 24, 24, 24, 24,  // Q1-Q9
        28,                                   // Q10
        29, 29, 29, 28, 29, 29, 29, 28, 29, 29,  // Q11-Q20
    )

    // Per-row cell center Y positions in the warped image (WARP_H=780). Rows A–E.
    val ROW_CENTERS_PX = intArrayOf(191, 303, 416, 528, 642)
    val ROW_HALF_H_PX  = intArrayOf(28, 28, 28, 28, 28)

    const val CELL_READ_FRAC = 0.70
    const val CELL_CORE_FRAC = 0.40

    // Effective margins derived from measured cell centers (used for orientation/debug)
    val EFFECTIVE_LABEL_W:  Int get() = COLUMN_CENTERS_PX[0] - COLUMN_HALF_W_PX[0]  // =49
    val EFFECTIVE_HEADER_H: Int get() = ROW_CENTERS_PX[0]   - ROW_HALF_H_PX[0]     // =163

    val MIN_CELL_W: Int get() = COLUMN_HALF_W_PX.minOrNull()!! * 2  // =48
    val MIN_CELL_H: Int get() = ROW_HALF_H_PX.minOrNull()!!  * 2   // =56
    val MAX_CELL_W: Int get() = COLUMN_HALF_W_PX.maxOrNull()!! * 2
    val MAX_CELL_H: Int get() = ROW_HALF_H_PX.maxOrNull()!! * 2

    // Compatibility aliases used by orientation/debug code.
    val LABEL_W: Int get() = EFFECTIVE_LABEL_W
    val HEADER_H: Int get() = EFFECTIVE_HEADER_H
    val CELL_W: Int get() = MIN_CELL_W
    val CELL_H: Int get() = MIN_CELL_H

    // Static thresholds (used as fallback when noiseFloor is unavailable)
    const val BLANK_THRESHOLD    = 0.07
    const val FILL_THRESHOLD     = 0.18
    const val MULTIPLE_THRESHOLD = 0.15
    const val DOMINANCE_DELTA    = 0.06
    const val GAP_RATIO          = 1.50

    // Adaptive multipliers applied to per-sheet noise floor (P25 of all 100 cell scores)
    const val ADAPTIVE_BLANK_MULT = 2.8
    const val ADAPTIVE_FILL_MULT  = 6.5
    const val ADAPTIVE_MULTI_MULT = 5.5

    // CLAHE parameters
    const val CLAHE_CLIP_LIMIT = 2.0
    const val CLAHE_TILE_GRID  = 8

    const val MORPH_OPEN_SIZE = 3

    // Small/perspective markers in 1200x1600 gallery photos can fall just below
    // 0.0002 (about 384 px), while still being perfectly readable.
    const val MARKER_MIN_AREA_FRAC      = 0.0001
    const val MARKER_MAX_AREA_FRAC      = 0.045
    const val MARKER_MIN_SOLIDITY       = 0.68
    const val MARKER_MIN_DENSITY        = 0.50
    const val MARKER_MIN_ASPECT         = 0.55
    const val MARKER_MAX_ASPECT         = 1.45
    const val MARKER_CORNER_REGION_FRAC = 0.45

    const val MIN_SHARPNESS_VARIANCE  = 12.0
    const val MIN_TEMPLATE_AREA_FRAC  = 0.12
    const val MAX_OPPOSITE_SIDE_RATIO = 1.85
}

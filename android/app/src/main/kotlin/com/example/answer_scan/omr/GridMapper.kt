package com.example.answer_scan.omr

import kotlin.math.roundToInt

class GridMapper {

    data class CellROI(
        val col: Int,
        val row: Int,
        val x1: Int,
        val y1: Int,
        val x2: Int,
        val y2: Int,
    ) {
        val width: Int get() = x2 - x1
        val height: Int get() = y2 - y1
        val isEmpty: Boolean get() = width <= 0 || height <= 0
    }

    private val readHalfX = IntArray(TemplateConfig.N_COLS) { col ->
        (TemplateConfig.COLUMN_HALF_W_PX[col] * TemplateConfig.CELL_READ_FRAC).roundToInt()
    }
    private val readHalfY = IntArray(TemplateConfig.N_ROWS) { row ->
        (TemplateConfig.ROW_HALF_H_PX[row] * TemplateConfig.CELL_READ_FRAC).roundToInt()
    }
    private val coreHalfX = IntArray(TemplateConfig.N_COLS) { col ->
        (TemplateConfig.COLUMN_HALF_W_PX[col] * TemplateConfig.CELL_CORE_FRAC).roundToInt()
    }
    private val coreHalfY = IntArray(TemplateConfig.N_ROWS) { row ->
        (TemplateConfig.ROW_HALF_H_PX[row] * TemplateConfig.CELL_CORE_FRAC).roundToInt()
    }

    fun getCellROI(col: Int, row: Int): CellROI {
        val cx = TemplateConfig.COLUMN_CENTERS_PX[col]
        val cy = TemplateConfig.ROW_CENTERS_PX[row]
        return CellROI(
            col = col, row = row,
            x1 = cx - readHalfX[col], y1 = cy - readHalfY[row],
            x2 = cx + readHalfX[col], y2 = cy + readHalfY[row],
        )
    }

    fun getCellCoreROI(col: Int, row: Int): CellROI {
        val cx = TemplateConfig.COLUMN_CENTERS_PX[col]
        val cy = TemplateConfig.ROW_CENTERS_PX[row]
        return CellROI(
            col = col, row = row,
            x1 = cx - coreHalfX[col], y1 = cy - coreHalfY[row],
            x2 = cx + coreHalfX[col], y2 = cy + coreHalfY[row],
        )
    }

    fun getFullCellRect(col: Int, row: Int): CellROI {
        val cx = TemplateConfig.COLUMN_CENTERS_PX[col]
        val cy = TemplateConfig.ROW_CENTERS_PX[row]
        val hw = TemplateConfig.COLUMN_HALF_W_PX[col]
        val hh = TemplateConfig.ROW_HALF_H_PX[row]
        return CellROI(col, row, cx - hw, cy - hh, cx + hw, cy + hh)
    }

    fun debugSummary(): String =
        "GridMapper(center-based: ${TemplateConfig.N_COLS} cols × ${TemplateConfig.N_ROWS} rows)"
}

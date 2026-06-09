package com.example.answer_scan.omr

import org.opencv.core.Core
import org.opencv.core.Mat

class AnswerReader(private val gridMapper: GridMapper = GridMapper()) {

    data class CellMeasurement(
        val score: Double,
        val fullDensity: Double,
        val coreDensity: Double,
        val componentDensity: Double,
    )

    /**
     * Returns the per-cell fill scores AND the per-sheet noise floor.
     *
     * The noise floor is the P25 of all 100 scores (20 cols × 5 rows).
     * Because ~80% of cells are blank on a typical exam sheet, the 25th-percentile
     * falls solidly in the blank cluster and provides a reliable per-image estimate
     * of background density — enabling adaptive classification thresholds downstream.
     */
    fun scoreAllCells(gray: Mat): Pair<Array<DoubleArray>, Double> {
        val scores = Array(TemplateConfig.N_COLS) {
            DoubleArray(TemplateConfig.N_ROWS)
        }

        for (col in 0 until TemplateConfig.N_COLS) {
            for (row in 0 until TemplateConfig.N_ROWS) {
                scores[col][row] = measureCell(gray, col, row).score
            }
        }

        val sorted = scores.flatMap { it.toList() }.sorted()
        val p25Idx = (sorted.size * 0.25).toInt().coerceIn(0, sorted.size - 1)
        val noiseFloor = sorted[p25Idx].coerceAtLeast(0.005)

        return scores to noiseFloor
    }

    fun measureCell(gray: Mat, col: Int, row: Int): CellMeasurement {
        val roi = gridMapper.getCellROI(col, row)
        val coreRoi = gridMapper.getCellCoreROI(col, row)

        if (roi.isEmpty || coreRoi.isEmpty) {
            return CellMeasurement(0.0, 0.0, 0.0, 0.0)
        }

        val full = gray.submat(roi.y1, roi.y2, roi.x1, roi.x2)
        val core = gray.submat(coreRoi.y1, coreRoi.y2, coreRoi.x1, coreRoi.x2)

        val fullDensity = darkness(full)
        val coreDensity = darkness(core)
        val combinedScore = coreDensity

        full.release()
        core.release()

        return CellMeasurement(
            score = combinedScore,
            fullDensity = fullDensity,
            coreDensity = coreDensity,
            componentDensity = 0.0,
        )
    }

    private fun darkness(mat: Mat): Double =
        (1.0 - Core.mean(mat).`val`[0] / 255.0).coerceIn(0.0, 1.0)
}

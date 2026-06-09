package com.example.answer_scan.omr

import android.util.Log
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc

class OmrDebugHelper {

    companion object {
        private const val TAG = "OmrDebugHelper"

        private val GREEN = Scalar(0.0, 220.0, 0.0)
        private val RED = Scalar(0.0, 0.0, 220.0)
        private val YELLOW = Scalar(0.0, 220.0, 220.0)
        private val BLUE = Scalar(220.0, 0.0, 0.0)
        private val MAGENTA = Scalar(200.0, 0.0, 200.0)
        private val GRAY = Scalar(120.0, 120.0, 120.0)
        private val WHITE = Scalar(255.0, 255.0, 255.0)
        private val BLACK = Scalar(0.0, 0.0, 0.0)

        private val CORNER_COLORS = listOf(GREEN, RED, YELLOW, BLUE)
    }

    fun generate(
        oriented: Mat,
        markerBinary: Mat,
        templateCorners: List<Point>,
        warped: Mat,
        warpBinary: Mat,
        scores: Array<DoubleArray>,
        questions: List<ScanResultMapper.QuestionResult>,
        gridMapper: GridMapper,
        originalPath: String,
    ): String? = try {
        val targetW = TemplateConfig.WARP_W.toDouble()
        val scaleOrig = targetW / oriented.width().coerceAtLeast(1)

        val panel1 = Mat()
        Imgproc.resize(
            oriented,
            panel1,
            Size(targetW, oriented.height() * scaleOrig),
        )
        templateCorners.forEachIndexed { index, point ->
            val scaled = Point(point.x * scaleOrig, point.y * scaleOrig)
            val color = CORNER_COLORS.getOrElse(index) { WHITE }
            Imgproc.circle(panel1, scaled, 14, color, -1)
            Imgproc.circle(panel1, scaled, 14, BLACK, 2)
        }
        label(panel1, "Panel 1: original + corners")

        val panel2 = Mat()
        Imgproc.cvtColor(markerBinary, panel2, Imgproc.COLOR_GRAY2BGR)
        Imgproc.resize(
            panel2,
            panel2,
            Size(targetW, markerBinary.height() * scaleOrig),
        )
        templateCorners.forEachIndexed { index, point ->
            val scaled = Point(point.x * scaleOrig, point.y * scaleOrig)
            val color = CORNER_COLORS.getOrElse(index) { WHITE }
            Imgproc.circle(panel2, scaled, 12, color, 2)
        }
        label(panel2, "Panel 2: marker binary")

        val panel3 = Mat()
        Imgproc.cvtColor(warped, panel3, Imgproc.COLOR_GRAY2BGR)
        Imgproc.rectangle(
            panel3,
            Point(TemplateConfig.LABEL_W.toDouble(), TemplateConfig.HEADER_H.toDouble()),
            Point(TemplateConfig.WARP_W.toDouble(), TemplateConfig.WARP_H.toDouble()),
            BLUE,
            2,
        )
        for (col in 0 until TemplateConfig.N_COLS) {
            for (row in 0 until TemplateConfig.N_ROWS) {
                val full = gridMapper.getFullCellRect(col, row)
                val roi = gridMapper.getCellROI(col, row)
                val core = gridMapper.getCellCoreROI(col, row)
                Imgproc.rectangle(panel3, full.tl(), full.br(), GRAY, 1)
                Imgproc.rectangle(panel3, roi.tl(), roi.br(), YELLOW, 1)
                Imgproc.rectangle(panel3, core.tl(), core.br(), MAGENTA, 1)
            }
        }
        label(panel3, "Panel 3: homography + ROIs")

        val panel4 = Mat()
        Imgproc.cvtColor(warpBinary, panel4, Imgproc.COLOR_GRAY2BGR)
        val optionLabels = TemplateConfig.OPTION_LABELS.toList()
        for (col in 0 until TemplateConfig.N_COLS) {
            val question = questions[col]
            for (row in 0 until TemplateConfig.N_ROWS) {
                val roi = gridMapper.getCellROI(col, row)
                val color = when {
                    question.answer == optionLabels.getOrNull(row) -> GREEN
                    scores[col][row] >= TemplateConfig.FILL_THRESHOLD -> RED
                    else -> GRAY
                }
                Imgproc.rectangle(panel4, roi.tl(), roi.br(), color, 2)
                Imgproc.putText(
                    panel4,
                    "%.0f".format(scores[col][row] * 100),
                    Point(roi.x1.toDouble() + 2, roi.y1.toDouble() + roi.height * 0.65),
                    Imgproc.FONT_HERSHEY_PLAIN,
                    0.80,
                    color,
                    1,
                )
            }

            val answerX = TemplateConfig.COLUMN_CENTERS_PX[col] - TemplateConfig.COLUMN_HALF_W_PX[col]
            Imgproc.putText(
                panel4,
                question.answer,
                Point(answerX.toDouble() + 2, TemplateConfig.HEADER_H * 0.72),
                Imgproc.FONT_HERSHEY_SIMPLEX,
                0.52,
                WHITE,
                2,
            )
        }
        label(panel4, "Panel 4: binary + fill percentages")

        val ensureWidth = { mat: Mat ->
            if (mat.width() != TemplateConfig.WARP_W) {
                val resized = Mat()
                val height = (mat.height().toDouble() * TemplateConfig.WARP_W / mat.width()).toInt()
                Imgproc.resize(mat, resized, Size(targetW, height.toDouble()))
                resized.copyTo(mat)
                resized.release()
            }
        }
        ensureWidth(panel1)
        ensureWidth(panel2)
        ensureWidth(panel3)
        ensureWidth(panel4)

        val combined = Mat()
        Core.vconcat(listOf(panel1, panel2, panel3, panel4), combined)

        val debugPath = originalPath.replace(Regex("\\.[^.]+$"), "_omr_debug.jpg")
        Imgcodecs.imwrite(debugPath, combined)

        panel1.release()
        panel2.release()
        panel3.release()
        panel4.release()
        combined.release()

        Log.d(TAG, "Debug image saved: $debugPath")
        debugPath
    } catch (e: Exception) {
        Log.e(TAG, "Debug image generation failed", e)
        null
    }

    private fun label(mat: Mat, text: String) {
        Imgproc.putText(
            mat,
            text,
            Point(12.0, 28.0),
            Imgproc.FONT_HERSHEY_SIMPLEX,
            0.65,
            WHITE,
            2,
        )
    }

    private fun GridMapper.CellROI.tl() = Point(x1.toDouble(), y1.toDouble())
    private fun GridMapper.CellROI.br() = Point(x2.toDouble(), y2.toDouble())
}
